using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using System.Runtime.InteropServices;
using Microsoft.Windows.AppLifecycle;
using PRChecker.App.Services;
using PRChecker.Core;
using Velopack;

namespace PRChecker.App;

public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        AppDomain.CurrentDomain.UnhandledException += (_, e) =>
        {
            if (e.ExceptionObject is Exception error) Log.Fatal("Unhandled exception", error);
        };
        try
        {
            Log.Info($"Starting {Platform.Version} ({RuntimeInformation.ProcessArchitecture}, {RuntimeInformation.OSDescription})");
            // The chosen language from the start, so even startup errors use it.
            Localizer.Apply(new JsonFileStore(Platform.DataDirectory).Load().Language);

            // Must run first: handles Velopack's install, update and uninstall hooks.
            VelopackApp.Build()
                .OnBeforeUninstallFastCallback(_ =>
                {
                    Platform.OpenAtLogin = false;
                    SystemToastNotifier.Unregister();
                })
                .Run();

            WinRT.ComWrappersSupport.InitializeComWrappers();
            if (RedirectToRunningInstance())
            {
                Log.Info("Already running; handed this launch to it");
                return 0;
            }

            Application.Start(callback =>
            {
                SynchronizationContext.SetSynchronizationContext(
                    new DispatcherQueueSynchronizationContext(DispatcherQueue.GetForCurrentThread()));
                _ = new App();
            });
            Log.Info("Exited");
            return 0;
        }
        catch (Exception error)
        {
            Log.Fatal("Startup failed", error);
            return 1;
        }
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
