using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

internal static class Program
{
    private const int SwShow = 5;
    private const int SwRestore = 9;
    private const string ForceRebuildEnvironmentVariable = "CHERIFLIX_LAUNCHER_REBUILD";
    private const string LauncherMutexName = @"Global\CHERIFLIX_Launcher_SingleInstance";

    private static readonly string[] WatchedDirectories =
    {
        "lib",
        "assets",
        "windows",
        "config",
        "branding",
    };

    private static readonly string[] WatchedFiles =
    {
        "pubspec.yaml",
        "pubspec.lock",
        ".metadata",
    };

    [STAThread]
    private static void Main()
    {
        using var instanceMutex = new Mutex(initiallyOwned: true, name: LauncherMutexName, createdNew: out var createdNew);
        if (!createdNew)
        {
            return;
        }

        var repoRoot = FindRepoRoot(AppDomain.CurrentDomain.BaseDirectory);
        if (repoRoot == null)
        {
            ShowError(
                "CHERIFLIX launcher could not find the project root.\r\n\r\n" +
                "Keep this launcher inside the CHERIFLIX workspace.");
            return;
        }

        var flutterPath = Path.Combine(repoRoot, ".tooling", "flutter", "bin", "flutter.bat");
        var releaseDir = Path.Combine(repoRoot, "build", "windows", "x64", "runner", "Release");
        var appExe = Path.Combine(releaseDir, "cheriflix.exe");
        var logDir = Path.Combine(repoRoot, ".tmp-run");
        var logPath = Path.Combine(logDir, "launcher-build.log");
        var tracePath = Path.Combine(logDir, "launcher-trace.log");
        var buildStampPath = Path.Combine(logDir, "windows-release.stamp");

        try
        {
            Directory.CreateDirectory(logDir);
            Trace(tracePath, "Launcher started.");
            Trace(tracePath, "Base directory: " + AppDomain.CurrentDomain.BaseDirectory);
            Trace(tracePath, "Repo root: " + repoRoot);

            if (!File.Exists(flutterPath))
            {
                Trace(tracePath, "Bundled Flutter SDK is missing.");
                ShowError(
                    "CHERIFLIX launcher could not find the bundled Flutter SDK.\r\n\r\n" +
                    flutterPath);
                return;
            }

            var runningApp = TryFindRunningApp(appExe);
            if (runningApp != null)
            {
                Trace(tracePath, "Existing app instance detected. Bringing it to front.");
                TryBringToFront(runningApp);
                runningApp.Dispose();
                return;
            }

            var forceRebuild = IsForceRebuildRequested();
            Trace(tracePath, "Force rebuild requested: " + forceRebuild);

            if (!File.Exists(appExe))
            {
                Trace(tracePath, "Release app is missing. Building it now.");
                if (!TryBuildRelease(
                        flutterPath,
                        repoRoot,
                        logPath,
                        tracePath,
                        buildStampPath,
                        "The latest CHERIFLIX build failed.",
                        "Building CHERIFLIX Windows release..."))
                {
                    return;
                }
            }
            else if (forceRebuild)
            {
                Trace(tracePath, "Forced rebuild requested. Rebuilding release app.");
                if (!TryBuildRelease(
                        flutterPath,
                        repoRoot,
                        logPath,
                        tracePath,
                        buildStampPath,
                        "CHERIFLIX could not refresh the Windows build.",
                        "Refreshing CHERIFLIX Windows build..."))
                {
                    return;
                }
            }
            else if (NeedsRebuild(repoRoot, appExe, buildStampPath))
            {
                Trace(tracePath, "Sources are newer than the release app. Rebuilding now.");
                if (!TryBuildRelease(
                        flutterPath,
                        repoRoot,
                        logPath,
                        tracePath,
                        buildStampPath,
                        "CHERIFLIX could not build the latest Windows version.",
                        "Changes detected. Rebuilding CHERIFLIX..."))
                {
                    return;
                }
            }

            if (!File.Exists(appExe))
            {
                Trace(tracePath, "Release executable is missing.");
                ShowError(
                    "CHERIFLIX launcher could not find the Windows release app.\r\n\r\n" +
                    appExe);
                return;
            }

            Trace(tracePath, "Launching app: " + appExe);
            Process.Start(new ProcessStartInfo
            {
                FileName = appExe,
                WorkingDirectory = releaseDir,
                UseShellExecute = true,
            });
            Trace(tracePath, "Launcher handoff completed.");
        }
        catch (Exception ex)
        {
            Trace(tracePath, "Unexpected error: " + ex);
            ShowError("CHERIFLIX launcher hit an unexpected error.\r\n\r\n" + ex.Message);
        }
    }

    private static Process TryFindRunningApp(string appExe)
    {
        var normalizedTarget = Path.GetFullPath(appExe);
        var processName = Path.GetFileNameWithoutExtension(appExe);
        Process fallbackMatch = null;

        foreach (var process in Process.GetProcessesByName(processName))
        {
            try
            {
                var processPath = process.MainModule?.FileName;
                if (string.IsNullOrEmpty(processPath))
                {
                    if (fallbackMatch == null)
                    {
                        fallbackMatch = process;
                        continue;
                    }

                    process.Dispose();
                    continue;
                }

                if (Path.GetFullPath(processPath).Equals(normalizedTarget, StringComparison.OrdinalIgnoreCase))
                {
                    fallbackMatch?.Dispose();
                    return process;
                }

                if (fallbackMatch == null)
                {
                    fallbackMatch = process;
                    continue;
                }

                process.Dispose();
            }
            catch
            {
                if (fallbackMatch == null)
                {
                    fallbackMatch = process;
                    continue;
                }

                process.Dispose();
            }
        }

        return fallbackMatch;
    }

    private static void TryBringToFront(Process process)
    {
        IntPtr windowHandle;

        try
        {
            process.Refresh();
            windowHandle = process.MainWindowHandle;
            if (windowHandle == IntPtr.Zero)
            {
                try
                {
                    process.WaitForInputIdle(2000);
                }
                catch
                {
                }

                process.Refresh();
                windowHandle = process.MainWindowHandle;
            }
        }
        catch
        {
            return;
        }

        if (windowHandle == IntPtr.Zero)
        {
            return;
        }

        if (IsIconic(windowHandle))
        {
            ShowWindowAsync(windowHandle, SwRestore);
        }
        else
        {
            ShowWindowAsync(windowHandle, SwShow);
        }

        AllowSetForegroundWindow(process.Id);
        SetForegroundWindow(windowHandle);
    }

    private static string FindRepoRoot(string startDirectory)
    {
        var current = new DirectoryInfo(startDirectory);
        while (current != null)
        {
            var pubspecPath = Path.Combine(current.FullName, "pubspec.yaml");
            var flutterPath = Path.Combine(current.FullName, ".tooling", "flutter", "bin", "flutter.bat");
            if (File.Exists(pubspecPath) && File.Exists(flutterPath))
            {
                return current.FullName;
            }

            current = current.Parent;
        }

        return null;
    }

    private static bool NeedsRebuild(string repoRoot, string appExe, string buildStampPath)
    {
        if (!File.Exists(appExe))
        {
            return true;
        }

        var lastBuiltAt = File.GetLastWriteTimeUtc(appExe);
        if (File.Exists(buildStampPath))
        {
            var stampTime = File.GetLastWriteTimeUtc(buildStampPath);
            if (stampTime > lastBuiltAt)
            {
                lastBuiltAt = stampTime;
            }
        }

        return GetLatestSourceTimestamp(repoRoot) > lastBuiltAt;
    }

    private static bool IsForceRebuildRequested()
    {
        var rawValue = Environment.GetEnvironmentVariable(ForceRebuildEnvironmentVariable);
        if (string.IsNullOrWhiteSpace(rawValue))
        {
            return false;
        }

        return rawValue.Equals("1", StringComparison.OrdinalIgnoreCase) ||
               rawValue.Equals("true", StringComparison.OrdinalIgnoreCase) ||
               rawValue.Equals("yes", StringComparison.OrdinalIgnoreCase);
    }

    private static DateTime GetLatestSourceTimestamp(string repoRoot)
    {
        var latest = DateTime.MinValue;
        var ignoredLauncherDirectory = Path.Combine(repoRoot, "windows", "launcher") + Path.DirectorySeparatorChar;

        foreach (var file in WatchedFiles)
        {
            var fullPath = Path.Combine(repoRoot, file);
            if (File.Exists(fullPath))
            {
                var timestamp = File.GetLastWriteTimeUtc(fullPath);
                if (timestamp > latest)
                {
                    latest = timestamp;
                }
            }
        }

        foreach (var directory in WatchedDirectories)
        {
            var fullPath = Path.Combine(repoRoot, directory);
            if (!Directory.Exists(fullPath))
            {
                continue;
            }

            foreach (var filePath in Directory.EnumerateFiles(fullPath, "*", SearchOption.AllDirectories))
            {
                if (filePath.StartsWith(ignoredLauncherDirectory, StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                var timestamp = File.GetLastWriteTimeUtc(filePath);
                if (timestamp > latest)
                {
                    latest = timestamp;
                }
            }
        }

        return latest;
    }

    private static BuildResult RunBuild(string flutterPath, string repoRoot, string logPath)
    {
        var firstAttempt = RunBuildAttempt(
            flutterPath,
            repoRoot,
            "build windows --release --no-pub");
        if (firstAttempt.ExitCode == 0)
        {
            var firstLog = new StringBuilder();
            firstLog.AppendLine("Attempt 1: flutter build windows --release --no-pub");
            firstLog.AppendLine(firstAttempt.Output);
            File.WriteAllText(logPath, firstLog.ToString());
            return firstAttempt;
        }

        var secondAttempt = RunBuildAttempt(
            flutterPath,
            repoRoot,
            "build windows --release");
        var combinedLog = new StringBuilder();
        combinedLog.AppendLine("Attempt 1: flutter build windows --release --no-pub");
        combinedLog.AppendLine(firstAttempt.Output);
        combinedLog.AppendLine();
        combinedLog.AppendLine("Attempt 2: flutter build windows --release");
        combinedLog.AppendLine(secondAttempt.Output);
        File.WriteAllText(logPath, combinedLog.ToString());
        return new BuildResult(secondAttempt.ExitCode, combinedLog.ToString());
    }

    private static BuildResult RunBuildAttempt(
        string flutterPath,
        string repoRoot,
        string arguments)
    {
        var output = new StringBuilder();
        var startInfo = new ProcessStartInfo
        {
            FileName = flutterPath,
            Arguments = arguments,
            WorkingDirectory = repoRoot,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };

        using var process = new Process();
        process.StartInfo = startInfo;
        process.OutputDataReceived += (_, args) =>
        {
            if (args.Data != null)
            {
                output.AppendLine(args.Data);
            }
        };
        process.ErrorDataReceived += (_, args) =>
        {
            if (args.Data != null)
            {
                output.AppendLine(args.Data);
            }
        };

        process.Start();
        process.BeginOutputReadLine();
        process.BeginErrorReadLine();
        process.WaitForExit();

        return new BuildResult(process.ExitCode, output.ToString());
    }

    private static bool TryBuildRelease(
        string flutterPath,
        string repoRoot,
        string logPath,
        string tracePath,
        string buildStampPath,
        string errorMessage,
        string statusMessage)
    {
        BuildResult buildResult;
        try
        {
            buildResult = RunBuildWithProgressWindow(
                flutterPath,
                repoRoot,
                logPath,
                statusMessage);
        }
        catch (Exception ex)
        {
            Trace(tracePath, "Build failed with exception: " + ex);
            ShowError(
                errorMessage + "\r\n\r\n" +
                "Build log: " + logPath + "\r\n\r\n" +
                ex.Message);
            return false;
        }

        if (buildResult.ExitCode != 0)
        {
            Trace(tracePath, "Build failed with exit code " + buildResult.ExitCode + ".");
            ShowError(
                errorMessage + "\r\n\r\n" +
                "Build log: " + logPath + "\r\n\r\n" +
                buildResult.GetTail(24));
            return false;
        }

        UpdateBuildStamp(buildStampPath);
        Trace(tracePath, "Build completed and stamp updated.");
        return true;
    }

    private static BuildResult RunBuildWithProgressWindow(
        string flutterPath,
        string repoRoot,
        string logPath,
        string statusMessage)
    {
        using (var dialog = new BuildProgressDialog(statusMessage))
        {
            dialog.Show();
            dialog.BringToFront();
            dialog.Update();

            var startedAt = DateTime.UtcNow;
            var buildTask = Task.Run(() => RunBuild(flutterPath, repoRoot, logPath));
            while (!buildTask.Wait(60))
            {
                dialog.TickActivity(DateTime.UtcNow - startedAt);
                dialog.Refresh();
                Application.DoEvents();
            }

            dialog.SetCompleted();
            Application.DoEvents();
            return buildTask.GetAwaiter().GetResult();
        }
    }

    private static void UpdateBuildStamp(string buildStampPath)
    {
        File.WriteAllText(buildStampPath, DateTime.UtcNow.ToString("O"));
    }

    private static void ShowError(string message)
    {
        MessageBox.Show(message, "CHERIFLIX", MessageBoxButtons.OK, MessageBoxIcon.Error);
    }

    private static void Trace(string tracePath, string message)
    {
        File.AppendAllText(
            tracePath,
            "[" + DateTime.Now.ToString("O") + "] " + message + Environment.NewLine);
    }

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AllowSetForegroundWindow(int processId);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsIconic(IntPtr windowHandle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr windowHandle);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindowAsync(IntPtr windowHandle, int command);

    private sealed class BuildResult
    {
        public BuildResult(int exitCode, string output)
        {
            ExitCode = exitCode;
            Output = output ?? string.Empty;
        }

        public int ExitCode { get; }

        public string Output { get; }

        public string GetTail(int maxLines)
        {
            var lines = Output.Split(new[] { "\r\n", "\n" }, StringSplitOptions.RemoveEmptyEntries);
            if (lines.Length <= maxLines)
            {
                return Output;
            }

            var tail = new StringBuilder();
            for (var i = lines.Length - maxLines; i < lines.Length; i++)
            {
                tail.AppendLine(lines[i]);
            }

            return tail.ToString();
        }
    }

    private sealed class BuildProgressDialog : Form
    {
        private readonly string _baseStatusMessage;
        private readonly Label _statusLabel;
        private readonly Label _elapsedLabel;
        private readonly ProgressBar _progressBar;
        private readonly char[] _spinnerFrames = { '|', '/', '-', '\\' };
        private int _pulseValue = 12;
        private int _pulseDirection = 1;
        private int _dotCount;
        private int _spinnerIndex;

        public BuildProgressDialog(string statusMessage)
        {
            _baseStatusMessage = statusMessage;
            Text = "CHERIFLIX";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            MaximizeBox = false;
            MinimizeBox = false;
            ControlBox = false;
            ShowIcon = false;
            TopMost = true;
            Width = 500;
            Height = 190;

            var titleLabel = new Label
            {
                Text = "Rebuilding CHERIFLIX",
                AutoSize = true,
                Left = 18,
                Top = 14,
                Font = new System.Drawing.Font("Segoe UI", 12F, System.Drawing.FontStyle.Bold),
            };

            _statusLabel = new Label
            {
                Text = _baseStatusMessage,
                AutoSize = true,
                Left = 18,
                Top = 48,
                Font = new System.Drawing.Font("Segoe UI", 9F),
            };

            _progressBar = new ProgressBar
            {
                Left = 18,
                Top = 80,
                Width = 446,
                Height = 18,
                Style = ProgressBarStyle.Blocks,
                Minimum = 0,
                Maximum = 100,
                Value = _pulseValue,
            };

            _elapsedLabel = new Label
            {
                Text = "Elapsed: 00:00",
                AutoSize = true,
                Left = 18,
                Top = 112,
                Font = new System.Drawing.Font("Segoe UI", 9F),
            };

            var hintLabel = new Label
            {
                Text = "This window closes automatically when rebuild finishes.",
                AutoSize = true,
                Left = 18,
                Top = 136,
                ForeColor = System.Drawing.Color.DimGray,
                Font = new System.Drawing.Font("Segoe UI", 8.5F),
            };

            Controls.Add(titleLabel);
            Controls.Add(_statusLabel);
            Controls.Add(_progressBar);
            Controls.Add(_elapsedLabel);
            Controls.Add(hintLabel);
        }

        public void TickActivity(TimeSpan elapsed)
        {
            _pulseValue += _pulseDirection * 5;
            if (_pulseValue >= 96)
            {
                _pulseValue = 96;
                _pulseDirection = -1;
            }
            else if (_pulseValue <= 12)
            {
                _pulseValue = 12;
                _pulseDirection = 1;
            }
            _progressBar.Value = _pulseValue;

            _dotCount = (_dotCount + 1) % 4;
            _spinnerIndex = (_spinnerIndex + 1) % _spinnerFrames.Length;
            _statusLabel.Text = _spinnerFrames[_spinnerIndex] + " " + _baseStatusMessage + new string('.', _dotCount);

            _elapsedLabel.Text = "Elapsed: " + elapsed.ToString(@"mm\:ss");
        }

        public void SetCompleted()
        {
            _progressBar.Value = 100;
            _statusLabel.Text = "Finalizing and launching CHERIFLIX...";
        }
    }
}
