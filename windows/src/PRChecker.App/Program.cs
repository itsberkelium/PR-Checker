using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.Windows.AppLifecycle;
using Velopack;

namespace PRChecker.App;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        // Must run first: handles Velopack's install, update and uninstall hooks.
        VelopackApp.Build().Run();

        WinRT.ComWrappersSupport.InitializeComWrappers();
        if (RedirectToRunningInstance()) return 0;

        Application.Start(_ =>
        {
            SynchronizationContext.SetSynchronizationContext(
                new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
            _ = new App();
        });
        return 0;
    }

    /// <summary>
    /// One tray icon only: a second launch (or a notification click while running) is handed to
    /// the running instance. Redirecting on a separate thread avoids a known STA deadlock.
    /// </summary>
    private static bool RedirectToRunningInstance()
    {
        var current = AppInstance.FindOrRegisterForKey("PRChecker");
        if (current.IsCurrent) return false;

        var activation = AppInstance.GetCurrent().GetActivatedEventArgs();
        Task.Run(() => current.RedirectActivationToAsync(activation).AsTask()).Wait();
        return true;
    }
}
