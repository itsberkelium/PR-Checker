using System.Runtime.InteropServices;

namespace PRChecker.App.Services;

/// <summary>Standalone dialogs for updates; they work without any window open.</summary>
internal static partial class UpdatePrompt
{
    private const uint MbOk = 0x0;
    private const uint MbYesNo = 0x4;
    private const uint MbIconInformation = 0x40;
    private const int IdYes = 6;

    [LibraryImport("user32.dll", EntryPoint = "MessageBoxW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int MessageBox(IntPtr owner, string text, string caption, uint type);

    public static Task<bool> AskAsync(string version) => Task.FromResult(
        MessageBox(IntPtr.Zero,
            L10n.UpdateAvailableMessage(version, Platform.Version),
            L10n.UpdateAvailableTitle, MbYesNo | MbIconInformation) == IdYes);

    public static void Inform(string message) => MessageBox(IntPtr.Zero, message, "PR Checker", MbOk | MbIconInformation);
}
