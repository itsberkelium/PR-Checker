using System.Diagnostics;
using System.Runtime.InteropServices;
using Microsoft.Win32;
using PRChecker.Core;

namespace PRChecker.App.Services;

internal static partial class Platform
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string RunValue = "PRChecker";

    public static string DataDirectory =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PRChecker");

    public static string Version =>
        typeof(Platform).Assembly.GetName().Version is { } v ? $"{v.Major}.{v.Minor}.{v.Build}" : "?";

    /// <summary>Opens a PR link only if it points at the configured server.</summary>
    public static void OpenLink(string url, AppSettings settings)
    {
        if (settings.Server?.Owns(url) != true) return;
        Process.Start(new ProcessStartInfo(new Uri(url).AbsoluteUri) { UseShellExecute = true });
    }

    public static void OpenNotificationSettings() =>
        Process.Start(new ProcessStartInfo("ms-settings:notifications") { UseShellExecute = true });

    /// <summary>Starts with Windows via the per-user Run key.</summary>
    public static bool OpenAtLogin
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKey);
            return key?.GetValue(RunValue) is string;
        }
        set
        {
            using var key = Registry.CurrentUser.CreateSubKey(RunKey);
            if (value && Environment.ProcessPath is { } path) key.SetValue(RunValue, $"\"{path}\"");
            else key.DeleteValue(RunValue, throwOnMissingValue: false);
        }
    }

    private const uint MbYesNo = 0x4;
    private const uint MbIconQuestion = 0x20;
    private const uint MbDefButton2 = 0x100;
    private const int IdYes = 6;

    [LibraryImport("user32.dll", EntryPoint = "MessageBoxW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int MessageBox(IntPtr owner, string text, string caption, uint type);

    /// <summary>A standalone dialog: works from the tray menu, where there's no window to attach to.</summary>
    public static bool ConfirmQuit() =>
        MessageBox(IntPtr.Zero,
            L10n.QuitConfirmMessage, L10n.QuitConfirmTitle, MbYesNo | MbIconQuestion | MbDefButton2) == IdYes;
}
