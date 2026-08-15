[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = 'D:\OrangeWordPressLocal'
$source = 'D:\orange-wordpress-staging'
$php = Join-Path $root 'runtime\php\php.exe'
$mariaBin = Join-Path $root 'runtime\mariadb\bin'
$mariadbd = Join-Path $mariaBin 'mariadbd.exe'
$mariadb = Join-Path $mariaBin 'mariadb.exe'
$mariadbAdmin = Join-Path $mariaBin 'mariadb-admin.exe'
$data = Join-Path $root 'data\mysql'
$site = Join-Path $root 'site'
$logs = Join-Path $root 'logs'
$ini = Join-Path $root 'my.ini'
$secretFile = Join-Path $root 'db-password.txt'
$dbName = 'staging_site'
$dbUser = 'wp_local'
$dbPort = 3307
$webPort = 8080

function Write-Utf8([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}

New-Item -ItemType Directory -Force $root, $data, $site, $logs | Out-Null
if (-not (Test-Path $php) -or -not (Test-Path $mariadbd)) { throw 'Portable PHP/MariaDB runtimes are not ready.' }
if (-not (Test-Path $secretFile)) { Write-Utf8 $secretFile (([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')).Substring(0, 40)) }
$password = (Get-Content -Raw $secretFile).Trim()

$iniText = @"
[client]
port=$dbPort
host=127.0.0.1

[mysqld]
basedir=$($root.Replace('\','/'))/runtime/mariadb
datadir=$($data.Replace('\','/'))
port=$dbPort
bind-address=127.0.0.1
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_520_ci
max_allowed_packet=256M
skip-name-resolve
"@
Write-Utf8 $ini $iniText

if (-not (Test-Path (Join-Path $data 'mysql'))) {
    & (Join-Path $mariaBin 'mariadb-install-db.exe') "--datadir=$data" "--config=$ini" "--password=$password" "--port=$dbPort" '--silent'
    if ($LASTEXITCODE -ne 0) { throw "MariaDB initialization failed ($LASTEXITCODE)." }
}
if (-not (Get-NetTCPConnection -LocalPort $dbPort -State Listen -ErrorAction SilentlyContinue)) {
    $dbProc = Start-Process $mariadbd -ArgumentList @("--defaults-file=$ini") -WorkingDirectory $mariaBin -WindowStyle Hidden -PassThru
    $ready = $false
    foreach ($i in 1..60) {
        Start-Sleep 1
        & $mariadbAdmin "--defaults-file=$ini" '--user=root' "--password=$password" '--protocol=tcp' '--skip-ssl' ping 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        if ($dbProc.HasExited) { throw 'MariaDB stopped while starting.' }
    }
    if (-not $ready) { throw 'MariaDB did not become ready.' }
}
$sql = "CREATE DATABASE IF NOT EXISTS $dbName CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci; CREATE USER IF NOT EXISTS '$dbUser'@'127.0.0.1' IDENTIFIED BY '$password'; ALTER USER '$dbUser'@'127.0.0.1' IDENTIFIED BY '$password'; GRANT ALL PRIVILEGES ON $dbName.* TO '$dbUser'@'127.0.0.1'; FLUSH PRIVILEGES;"
& $mariadb "--defaults-file=$ini" '--user=root' "--password=$password" '--protocol=tcp' '--skip-ssl' '--execute' $sql 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw "MariaDB database setup failed ($LASTEXITCODE)." }

$importMarker = Join-Path $root '.database-imported'
if (-not (Test-Path $importMarker)) {
    $dump = Join-Path $source 'database.sql.gz'
    if (-not (Test-Path $dump)) { throw "Database dump not found: $dump" }
    $p = [Diagnostics.Process]::new()
    $p.StartInfo.FileName = $mariadb
    $p.StartInfo.Arguments = "--defaults-file=$ini --user=root --password=$password --protocol=tcp --skip-ssl --database=$dbName"
    $p.StartInfo.UseShellExecute = $false
    $p.StartInfo.RedirectStandardInput = $true
    [void]$p.Start()
    $in = [IO.File]::OpenRead($dump)
    $in.CopyTo($p.StandardInput.BaseStream)
    $p.StandardInput.Close()
    $in.Dispose()
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "Database import failed ($($p.ExitCode))." }
    Write-Utf8 $importMarker (Get-Date -Format o)
}

$extractMarker = Join-Path $root '.site-extracted'
if (-not (Test-Path $extractMarker)) {
    $archive = Join-Path $source 'site-files.tar.gz'
    if (-not (Test-Path $archive)) { throw "Site archive not found: $archive" }
    $winrar = 'C:\Program Files\WinRAR\WinRAR.exe'
    if (-not (Test-Path $winrar)) { throw 'WinRAR is required for this large archive on the native fallback.' }
    $extractProc = Start-Process -FilePath $winrar -ArgumentList @('x','-y','-xcache\*','-xwp-content\cache\*','-x.wp-cli\cache\*',$archive,($site + '\')) -Wait -PassThru
    if ($extractProc.ExitCode -ne 0) { throw "WinRAR extraction failed ($($extractProc.ExitCode))." }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $site 'wp-includes\version.php'))) { throw 'WordPress archive extraction failed.' }
    Write-Utf8 $extractMarker (Get-Date -Format o)
}

$phpIni = Join-Path $root 'php.ini'
$phpIniText = @"
[PHP]
extension_dir = "$($root.Replace('\','/'))/runtime/php/ext"
date.timezone = Australia/Hobart
memory_limit = 512M
upload_max_filesize = 256M
post_max_size = 256M
max_execution_time = 300
display_errors = Off
log_errors = On
error_log = "$($logs.Replace('\','/'))/php-error.log"
extension=php_curl.dll
extension=php_exif.dll
extension=php_fileinfo.dll
extension=php_gd.dll
extension=php_intl.dll
extension=php_mbstring.dll
extension=php_mysqli.dll
extension=php_openssl.dll
extension=php_pdo_mysql.dll
extension=php_soap.dll
extension=php_zip.dll
"@
Write-Utf8 $phpIni $phpIniText

$config = Join-Path $site 'wp-config.php'
if (-not (Test-Path $config)) { throw 'wp-config.php was not found in the extracted site.' }
$configText = Get-Content -Raw $config
foreach ($pair in @(
    @{ Name='DB_NAME'; Value=$dbName },
    @{ Name='DB_USER'; Value=$dbUser },
    @{ Name='DB_PASSWORD'; Value=$password },
    @{ Name='DB_HOST'; Value="127.0.0.1:$dbPort" }
)) {
    $pattern = '(?is)(define\s*\(\s*["'']' + $pair.Name + '["'']\s*,\s*)["''][^"'']*["''](\s*\)\s*;)'
    $replacement = '$1' + "'" + $pair.Value + "'" + '$2'
    $configText = [regex]::Replace($configText, $pattern, $replacement)
}
if ($configText -notmatch 'ORANGE_NATIVE_LOCAL_BEGIN') {
    $safety = @"
 /* ORANGE_NATIVE_LOCAL_BEGIN */
 define('WP_HOME', 'http://127.0.0.1:$webPort');
 define('WP_SITEURL', 'http://127.0.0.1:$webPort');
 define('WP_ENVIRONMENT_TYPE', 'staging');
 define('WP_HTTP_BLOCK_EXTERNAL', true);
 define('WP_ACCESSIBLE_HOSTS', '127.0.0.1,localhost');
 define('DISALLOW_FILE_EDIT', true);
 /* ORANGE_NATIVE_LOCAL_END */
"@
    $anchor = "/* That's all, stop editing! Happy publishing. */"
    if ($configText.Contains($anchor)) { $configText = $configText.Replace($anchor, $safety + [Environment]::NewLine + $anchor) } else { $configText += [Environment]::NewLine + $safety + [Environment]::NewLine }
}
Write-Utf8 $config $configText

$cli = Join-Path $root 'wp-cli.phar'
if (-not (Test-Path $cli)) { Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar' -OutFile $cli -UseBasicParsing }
$replaceMarker = Join-Path $root '.urls-replaced'
if (-not (Test-Path $replaceMarker)) {
    foreach ($old in @('https://vanvakarnee.com','http://vanvakarnee.com','https://www.vanvakarnee.com','http://www.vanvakarnee.com')) {
        & $php '-c' $phpIni $cli 'search-replace' $old "http://127.0.0.1:$webPort" '--all-tables' '--skip-columns=guid' '--skip-plugins' '--skip-themes' '--allow-root' "--path=$site" '--quiet' 2>$null
    }
    Write-Utf8 $replaceMarker (Get-Date -Format o)
}

$router = @'
<?php
$path = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$candidate = __DIR__ . DIRECTORY_SEPARATOR . 'site' . str_replace('/', DIRECTORY_SEPARATOR, rawurldecode($path));
if ($path !== '/' && is_file($candidate)) { return false; }
require __DIR__ . DIRECTORY_SEPARATOR . 'site' . DIRECTORY_SEPARATOR . 'index.php';
'@
Write-Utf8 (Join-Path $root 'router.php') $router

$start = @'
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$php = Join-Path $root 'runtime\php\php.exe'
$ini = Join-Path $root 'my.ini'
$phpIni = Join-Path $root 'php.ini'
$mariadbd = Join-Path $root 'runtime\mariadb\bin\mariadbd.exe'
$mariadbAdmin = Join-Path $root 'runtime\mariadb\bin\mariadb-admin.exe'
$password = (Get-Content -Raw (Join-Path $root 'db-password.txt')).Trim()
if (-not (Get-NetTCPConnection -LocalPort 3307 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process $mariadbd -ArgumentList @("--defaults-file=$ini") -WorkingDirectory (Join-Path $root 'runtime\mariadb\bin') -WindowStyle Hidden | Out-Null
    for($i=0;$i -lt 60;$i++){ Start-Sleep 1; & $mariadbAdmin "--defaults-file=$ini" '--user=root' "--password=$password" '--protocol=tcp' ping 2>$null | Out-Null; if($LASTEXITCODE -eq 0){break} }
}
if (-not (Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue)) {
    Start-Process $php -ArgumentList @('-c',$phpIni,'-S','127.0.0.1:8080','-t','site','router.php') -WorkingDirectory $root -WindowStyle Hidden | Out-Null
    Start-Sleep 2
}
Start-Process 'http://127.0.0.1:8080'
'@
Write-Utf8 (Join-Path $root 'start-local.ps1') $start

$stop = @'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$web = Get-NetTCPConnection -LocalPort 8080 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($web) { Stop-Process -Id $web.OwningProcess -Force -ErrorAction SilentlyContinue }
$password = (Get-Content -Raw (Join-Path $root 'db-password.txt')).Trim()
$admin = Join-Path $root 'runtime\mariadb\bin\mariadb-admin.exe'
$ini = Join-Path $root 'my.ini'
& $admin "--defaults-file=$ini" '--user=root' "--password=$password" '--protocol=tcp' shutdown 2>$null | Out-Null
'@
Write-Utf8 (Join-Path $root 'stop-local.ps1') $stop
$nl = [Environment]::NewLine
Write-Utf8 (Join-Path $root 'Start Local WordPress.cmd') ("@echo off$nl" + "powershell.exe -ExecutionPolicy Bypass -File ""%~dp0start-local.ps1""$nl")
Write-Utf8 (Join-Path $root 'Stop Local WordPress.cmd') ("@echo off$nl" + "powershell.exe -ExecutionPolicy Bypass -File ""%~dp0stop-local.ps1""$nl")
Write-Utf8 (Join-Path $root 'README.txt') ("Local WordPress staging is installed on D:.$nl" + "Start Local WordPress.cmd opens http://127.0.0.1:8080.$nl" + "Stop Local WordPress.cmd stops it.$nl" + "The server binds to localhost only; it is not shared on the network.$nl")

& (Join-Path $root 'start-local.ps1')
Write-Output "LOCAL_WORDPRESS_READY http://127.0.0.1:$webPort"
