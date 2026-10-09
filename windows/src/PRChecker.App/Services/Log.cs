using System.Runtime.InteropServices;
using PRChecker.Core;

namespace PRChecker.App.Services;

/// <summary>
/// A small local log for diagnosing startup problems: lifecycle steps and errors only, never
/// tokens or pull request data. Kept under 512 KB at %LOCALAPPDATA%\PRChecker\logs\pr-checker.log.
/// </summary>
internal static partial class Log
{
    private const long MaxBytes = 512 * 1024;
    private static readonly Lock Gate = new();

    public static string FilePath { get; } = Path.Combine(Platform.DataDirectory, "logs", "pr-checker.log");

    public static void Info(string message) => Write("INFO ", message);

    public static void Error(string context, Exception error) => Write("ERROR", $"{context}: {error}");

    private static void Write(string level, string message)
    {
        try
        {
            lock (Gate)
            {
                Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
                if (File.Exists(FilePath) && new FileInfo(FilePath).Length > MaxBytes) File.Delete(FilePath);
                File.AppendAllText(FilePath, $"{DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss.fff zzz} {level} {message}{Environment.NewLine}");
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }

    [LibraryImport("user32.dll", EntryPoint = "MessageBoxW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int MessageBox(IntPtr owner, string text, string caption, uint type);

    /// <summary>Logs a fatal error and tells the user, since a tray app has no window to show it in.</summary>
    public static void Fatal(string context, Exception error)
    {
        Error(context, error);
        MessageBox(IntPtr.Zero,
            L10n.StartupFailed($"{error.GetType().Name}: {error.Message}", FilePath),
            "PR Checker", 0x10 /* MB_ICONERROR */);
    }
}
