using System.Diagnostics;
using System.Windows.Forms;

namespace CheriflixUpdater;

internal static class Program
{
    [STAThread]
    private static void Main(string[] args)
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new UpdateForm(UpdateArguments.Parse(args)));
    }
}

internal sealed class UpdateForm : Form
{
    private readonly UpdateArguments _initialArguments;
    private readonly TextBox _stagingDirTextBox = new() { Dock = DockStyle.Fill };
    private readonly TextBox _installDirTextBox = new() { Dock = DockStyle.Fill };
    private readonly TextBox _entryExeTextBox = new() { Dock = DockStyle.Fill, Text = "cheriflix.exe" };
    private readonly TextBox _waitPidTextBox = new() { Dock = DockStyle.Fill };
    private readonly Label _statusLabel = new()
    {
        AutoSize = true,
        MaximumSize = new Size(640, 0),
        Text = "Choose the build folder and install location, then start the update.",
    };
    private readonly ProgressBar _progressBar = new()
    {
        Dock = DockStyle.Fill,
        Style = ProgressBarStyle.Continuous,
        Minimum = 0,
        Maximum = 1,
    };
    private readonly Button _startButton = new()
    {
        Text = "Start Update",
        AutoSize = true,
        AutoSizeMode = AutoSizeMode.GrowAndShrink,
    };
    private readonly Button _closeButton = new()
    {
        Text = "Close",
        AutoSize = true,
        AutoSizeMode = AutoSizeMode.GrowAndShrink,
    };
    private readonly List<Control> _editableControls = [];

    private bool _isRunning;

    public UpdateForm(UpdateArguments initialArguments)
    {
        _initialArguments = initialArguments;

        Text = "CHERIFLIX Updater";
        MinimumSize = new Size(760, 440);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false;

        _stagingDirTextBox.Text = initialArguments.StagingDir;
        _installDirTextBox.Text = initialArguments.InstallDir;
        _entryExeTextBox.Text = string.IsNullOrWhiteSpace(initialArguments.EntryExe)
            ? "cheriflix.exe"
            : initialArguments.EntryExe;
        _waitPidTextBox.Text = initialArguments.WaitPid?.ToString() ?? string.Empty;

        _startButton.Click += async (_, _) => await StartUpdateAsync();
        _closeButton.Click += (_, _) => Close();
        Shown += async (_, _) => await MaybeAutoStartAsync();

        Controls.Add(BuildLayout());
    }

    private Control BuildLayout()
    {
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 1,
            RowCount = 5,
            Padding = new Padding(18),
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var headerPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            ColumnCount = 1,
            AutoSize = true,
        };

        headerPanel.Controls.Add(new Label
        {
            AutoSize = true,
            Text = "Apply a new CHERIFLIX build",
            Font = new Font(Font, FontStyle.Bold),
            Margin = new Padding(0, 0, 0, 6),
        });
        headerPanel.Controls.Add(new Label
        {
            AutoSize = true,
            MaximumSize = new Size(660, 0),
            Text = "The updater replaces app files while keeping your database, user data, and logs. "
                + "If you launch it with arguments, it will fill the form and start automatically.",
            ForeColor = SystemColors.GrayText,
        });

        var fieldsPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Fill,
            ColumnCount = 3,
            RowCount = 4,
            AutoSize = true,
            Margin = new Padding(0, 20, 0, 0),
        };
        fieldsPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130F));
        fieldsPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100F));
        fieldsPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110F));

        AddFieldRow(
            fieldsPanel,
            rowIndex: 0,
            label: "Build folder",
            input: _stagingDirTextBox,
            actionText: "Browse...",
            onAction: () => BrowseForFolder(_stagingDirTextBox));
        AddFieldRow(
            fieldsPanel,
            rowIndex: 1,
            label: "Install folder",
            input: _installDirTextBox,
            actionText: "Browse...",
            onAction: () => BrowseForFolder(_installDirTextBox));
        AddFieldRow(
            fieldsPanel,
            rowIndex: 2,
            label: "Entry EXE",
            input: _entryExeTextBox,
            actionText: "Reset",
            onAction: () => _entryExeTextBox.Text = "cheriflix.exe");
        AddFieldRow(
            fieldsPanel,
            rowIndex: 3,
            label: "Wait PID",
            input: _waitPidTextBox,
            actionText: "Clear",
            onAction: () => _waitPidTextBox.Clear());

        var statusPanel = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            ColumnCount = 1,
            RowCount = 2,
            AutoSize = true,
            Margin = new Padding(0, 18, 0, 0),
        };
        statusPanel.Controls.Add(_progressBar);
        statusPanel.Controls.Add(new Panel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            Padding = new Padding(0, 10, 0, 0),
            Controls = { _statusLabel },
        });

        var actionsPanel = new FlowLayoutPanel
        {
            Dock = DockStyle.Fill,
            FlowDirection = FlowDirection.RightToLeft,
            AutoSize = true,
            Margin = new Padding(0, 18, 0, 0),
        };
        actionsPanel.Controls.Add(_closeButton);
        actionsPanel.Controls.Add(_startButton);

        root.Controls.Add(headerPanel, 0, 0);
        root.Controls.Add(fieldsPanel, 0, 2);
        root.Controls.Add(statusPanel, 0, 3);
        root.Controls.Add(actionsPanel, 0, 4);

        return root;
    }

    private void AddFieldRow(
        TableLayoutPanel panel,
        int rowIndex,
        string label,
        Control input,
        string actionText,
        Action onAction)
    {
        panel.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var labelControl = new Label
        {
            Text = label,
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Margin = new Padding(0, 10, 12, 0),
        };

        input.Margin = new Padding(0, 6, 12, 0);
        input.Anchor = AnchorStyles.Left | AnchorStyles.Right;
        _editableControls.Add(input);

        var actionButton = new Button
        {
            Text = actionText,
            AutoSize = true,
            AutoSizeMode = AutoSizeMode.GrowAndShrink,
            Anchor = AnchorStyles.Right,
            Margin = new Padding(0, 6, 0, 0),
        };
        actionButton.Click += (_, _) => onAction();
        _editableControls.Add(actionButton);

        panel.Controls.Add(labelControl, 0, rowIndex);
        panel.Controls.Add(input, 1, rowIndex);
        panel.Controls.Add(actionButton, 2, rowIndex);
    }

    private async Task MaybeAutoStartAsync()
    {
        if (!_initialArguments.HasRequiredValues)
        {
            return;
        }

        _statusLabel.Text = "Arguments detected. Starting the update automatically...";
        await StartUpdateAsync();
    }

    private async Task StartUpdateAsync()
    {
        if (_isRunning)
        {
            return;
        }

        var waitPid = default(int?);
        if (!string.IsNullOrWhiteSpace(_waitPidTextBox.Text))
        {
            if (!int.TryParse(_waitPidTextBox.Text.Trim(), out var parsedPid) || parsedPid <= 0)
            {
                ShowValidationError("Wait PID must be blank or a positive number.");
                return;
            }

            waitPid = parsedPid;
        }

        var arguments = new UpdateArguments(
            _stagingDirTextBox.Text.Trim(),
            _installDirTextBox.Text.Trim(),
            _entryExeTextBox.Text.Trim(),
            waitPid);

        var validationError = ValidateArguments(arguments);
        if (validationError is not null)
        {
            ShowValidationError(validationError);
            return;
        }

        SetRunningState(true);

        try
        {
            var progress = new Progress<UpdateProgress>(ReportProgress);
            await Task.Run(() => ApplyUpdate(arguments, progress));

            _statusLabel.Text = "Update complete. Launching CHERIFLIX...";
            _progressBar.Style = ProgressBarStyle.Continuous;
            _progressBar.Maximum = 1;
            _progressBar.Value = 1;
            await Task.Delay(1200);
            Close();
        }
        catch (Exception ex)
        {
            SetRunningState(false);
            _statusLabel.Text = "Update failed. Review the error and try again.";
            MessageBox.Show(
                this,
                ex.Message,
                "CHERIFLIX Updater",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private void ReportProgress(UpdateProgress progress)
    {
        _statusLabel.Text = progress.Status;

        if (progress.IsIndeterminate)
        {
            if (_progressBar.Style != ProgressBarStyle.Marquee)
            {
                _progressBar.Style = ProgressBarStyle.Marquee;
            }

            return;
        }

        if (_progressBar.Style != ProgressBarStyle.Continuous)
        {
            _progressBar.Style = ProgressBarStyle.Continuous;
        }

        _progressBar.Maximum = Math.Max(progress.Total, 1);
        _progressBar.Value = Math.Min(Math.Max(progress.Current, 0), _progressBar.Maximum);
    }

    private void SetRunningState(bool isRunning)
    {
        _isRunning = isRunning;
        UseWaitCursor = isRunning;

        foreach (var control in _editableControls)
        {
            control.Enabled = !isRunning;
        }

        _startButton.Enabled = !isRunning;
        _closeButton.Enabled = !isRunning;
    }

    private void ShowValidationError(string message)
    {
        _statusLabel.Text = message;
        MessageBox.Show(
            this,
            message,
            "CHERIFLIX Updater",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning);
    }

    private void BrowseForFolder(TextBox target)
    {
        using var dialog = new FolderBrowserDialog
        {
            ShowNewFolderButton = true,
        };

        if (Directory.Exists(target.Text))
        {
            dialog.SelectedPath = target.Text;
        }

        if (dialog.ShowDialog(this) == DialogResult.OK)
        {
            target.Text = dialog.SelectedPath;
        }
    }

    private static string? ValidateArguments(UpdateArguments arguments)
    {
        if (string.IsNullOrWhiteSpace(arguments.StagingDir))
        {
            return "Build folder is required.";
        }

        if (!Directory.Exists(arguments.StagingDir))
        {
            return $"Build folder was not found: {arguments.StagingDir}";
        }

        if (string.IsNullOrWhiteSpace(arguments.InstallDir))
        {
            return "Install folder is required.";
        }

        if (string.IsNullOrWhiteSpace(arguments.EntryExe))
        {
            return "Entry EXE is required.";
        }

        var normalizedStaging = NormalizeDirectory(arguments.StagingDir);
        var normalizedInstall = NormalizeDirectory(arguments.InstallDir);

        if (normalizedStaging.Equals(normalizedInstall, StringComparison.OrdinalIgnoreCase))
        {
            return "Build folder and install folder must be different locations.";
        }

        if (IsSameOrChildOf(normalizedStaging, normalizedInstall) ||
            IsSameOrChildOf(normalizedInstall, normalizedStaging))
        {
            return "Build folder and install folder cannot be nested inside each other.";
        }

        return null;
    }

    private static string NormalizeDirectory(string path)
    {
        return Path.GetFullPath(path).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
    }

    private static bool IsSameOrChildOf(string parentPath, string childPath)
    {
        var parentWithSeparator = parentPath + Path.DirectorySeparatorChar;
        var childWithSeparator = childPath + Path.DirectorySeparatorChar;
        return childWithSeparator.StartsWith(parentWithSeparator, StringComparison.OrdinalIgnoreCase);
    }

    private static void ApplyUpdate(UpdateArguments arguments, IProgress<UpdateProgress> progress)
    {
        if (!Directory.Exists(arguments.StagingDir))
        {
            throw new InvalidOperationException($"Build folder was not found: {arguments.StagingDir}");
        }

        if (!Directory.Exists(arguments.InstallDir))
        {
            progress.Report(new UpdateProgress(
                $"Creating install folder: {arguments.InstallDir}",
                0,
                1,
                IsIndeterminate: true));
            Directory.CreateDirectory(arguments.InstallDir);
        }

        if (arguments.WaitPid is int pid)
        {
            progress.Report(new UpdateProgress(
                $"Waiting for process {pid} to exit...",
                0,
                1,
                IsIndeterminate: true));
            WaitForProcessExit(pid, TimeSpan.FromSeconds(30));
        }

        progress.Report(new UpdateProgress("Scanning update files...", 0, 1, IsIndeterminate: true));

        CopyDirectory(arguments.StagingDir, arguments.InstallDir, new[]
        {
            "cheriflix.db",
            "user_data",
            "logs",
        }, progress);

        var entryPath = Path.Combine(arguments.InstallDir, arguments.EntryExe);
        if (!File.Exists(entryPath))
        {
            throw new InvalidOperationException($"Entry executable not found after update: {entryPath}");
        }

        progress.Report(new UpdateProgress("Launching CHERIFLIX...", 1, 1, IsIndeterminate: true));
        Process.Start(new ProcessStartInfo
        {
            FileName = entryPath,
            WorkingDirectory = arguments.InstallDir,
            UseShellExecute = true,
        });
    }

    private static void WaitForProcessExit(int pid, TimeSpan timeout)
    {
        try
        {
            using var process = Process.GetProcessById(pid);
            process.WaitForExit((int)timeout.TotalMilliseconds);
        }
        catch (ArgumentException)
        {
            // The app already exited.
        }
    }

    private static void CopyDirectory(
        string sourceDirectory,
        string targetDirectory,
        IReadOnlyCollection<string> filesToSkip,
        IProgress<UpdateProgress> progress)
    {
        Directory.CreateDirectory(targetDirectory);

        var directories = Directory
            .EnumerateDirectories(sourceDirectory, "*", SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(sourceDirectory, path))
            .Where(relativePath => !ShouldSkip(relativePath, filesToSkip))
            .ToList();

        foreach (var relativePath in directories)
        {
            Directory.CreateDirectory(Path.Combine(targetDirectory, relativePath));
        }

        var files = Directory
            .EnumerateFiles(sourceDirectory, "*", SearchOption.AllDirectories)
            .Select(path => new FileCopyEntry(path, Path.GetRelativePath(sourceDirectory, path)))
            .Where(entry => !ShouldSkip(entry.RelativePath, filesToSkip))
            .ToList();

        if (files.Count == 0)
        {
            progress.Report(new UpdateProgress("No files were found in the build folder.", 1, 1, IsIndeterminate: false));
            return;
        }

        for (var index = 0; index < files.Count; index += 1)
        {
            var file = files[index];
            var destination = Path.Combine(targetDirectory, file.RelativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(file.SourcePath, destination, overwrite: true);

            progress.Report(new UpdateProgress(
                $"Copying {file.RelativePath}",
                index + 1,
                files.Count,
                IsIndeterminate: false));
        }
    }

    private static bool ShouldSkip(string relativePath, IReadOnlyCollection<string> skipTokens)
    {
        foreach (var token in skipTokens)
        {
            if (relativePath.Contains(token, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }

        return false;
    }
}

internal sealed record UpdateArguments(
    string StagingDir,
    string InstallDir,
    string EntryExe,
    int? WaitPid)
{
    public bool HasRequiredValues =>
        !string.IsNullOrWhiteSpace(StagingDir) &&
        !string.IsNullOrWhiteSpace(InstallDir) &&
        !string.IsNullOrWhiteSpace(EntryExe);

    public static UpdateArguments Parse(string[] args)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

        for (var index = 0; index < args.Length; index += 1)
        {
            var current = args[index];
            if (!current.StartsWith("--", StringComparison.Ordinal))
            {
                continue;
            }

            var key = current[2..];
            if (index + 1 >= args.Length)
            {
                break;
            }

            values[key] = args[index + 1];
            index += 1;
        }

        int? waitPid = null;
        if (values.TryGetValue("wait-pid", out var pidValue) &&
            int.TryParse(pidValue, out var parsedPid) &&
            parsedPid > 0)
        {
            waitPid = parsedPid;
        }

        return new UpdateArguments(
            values.GetValueOrDefault("staging-dir", string.Empty),
            values.GetValueOrDefault("install-dir", string.Empty),
            values.GetValueOrDefault("entry-exe", string.Empty),
            waitPid);
    }
}

internal sealed record UpdateProgress(
    string Status,
    int Current,
    int Total,
    bool IsIndeterminate);

internal sealed record FileCopyEntry(string SourcePath, string RelativePath);
