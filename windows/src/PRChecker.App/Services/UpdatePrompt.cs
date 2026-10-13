using System.Runtime.InteropServices;
using PRChecker.Core;

namespace PRChecker.App.Services;

/// <summary>Standalone dialogs for updates; they work without any window open.</summary>
internal static partial class UpdatePrompt
{
    private const uint MbOk = 0x0;
    private const uint MbYesNo = 0x4;
    private const uint MbIconInformation = 0x40;
    /// <summary>No owner window, so make sure the dialog isn't hidden behind Settings.</summary>
    private const uint MbFront = 0x00010000 /* MB_SETFOREGROUND */ | 0x00040000 /* MB_TOPMOST */;
    private const int IdYes = 6;

    [LibraryImport("user32.dll", EntryPoint = "MessageBoxW", StringMarshalling = StringMarshalling.Utf16)]
    private static partial int MessageBox(IntPtr owner, string text, string caption, uint type);

    public static Task<bool> AskAsync(string version) => Task.FromResult(
        MessageBox(IntPtr.Zero,
            L10n.UpdateAvailableMessage(version, Platform.Version),
            L10n.UpdateAvailableTitle, MbYesNo | MbIconInformation | MbFront) == IdYes);

    /// <summary>Going from a dev build back to the release; Velopack reports it as a downgrade.</summary>
    public static Task<bool> AskBackToStableAsync(string version) => Task.FromResult(
        MessageBox(IntPtr.Zero,
            L10n.BackToStableMessage(version, Platform.Version),
            L10n.BackToStableTitle, MbYesNo | MbIconInformation | MbFront) == IdYes);

    public static void Inform(string message) => MessageBox(IntPtr.Zero, message, "PR Checker", MbOk | MbIconInformation | MbFront);
}
