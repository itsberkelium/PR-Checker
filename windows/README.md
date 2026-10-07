# PR Checker for Windows

A system tray app for Windows 10 (1809) and later, built with C#, .NET 10 and WinUI 3. It follows the same rules as the macOS app, described in [docs/behavior.md](../docs/behavior.md). See the [main README](../README.md) for features, notifications and privacy.

**Status: in development.** The core (API client, rules, notifications logic, storage) is done and tested. The tray app builds in CI and is being tried out; releases and updates aren't published yet.

## Layout

```
src/PRChecker.Core/        everything except the UI; cross-platform, builds and tests on macOS too
  ServerAddress.cs         server URL validation, link ownership, PR link building
  BitbucketClient.cs       REST calls with size/page limits and same-server redirects
  Models.cs                API payloads and the PrItem model
  PrStore.cs               polling, enrichment, notification triggering
  ChangeDetector.cs        snapshot diffing that decides what to announce
  AppSettings.cs           settings, per-server tokens, filters
  Storage.cs               token store interface, JSON settings and snapshot files
tests/PRChecker.Core.Tests/ xUnit tests, incl. the shared fixtures and a stub server
src/PRChecker.App/         WinUI 3 tray app
  Program.cs               Velopack hook, single instance, startup
  App.xaml.cs              tray app lifecycle, update checks, notification clicks
  TrayController.cs        tray icon with count badge and menu
  Views/                   PR list popup and Settings window
  Services/                Credential Manager tokens, notifications, Velopack updates, open at login
```

## Building and testing

Requires the .NET 10 SDK. The core and its tests run on Windows, macOS and Linux:

```bash
dotnet test --project tests/PRChecker.Core.Tests
```

The app (`src/PRChecker.App`) builds on Windows only, because the WinUI XAML compiler is Windows-only. To build a self-contained copy that runs from a folder:

```bash
dotnet publish src/PRChecker.App -c Release -r win-arm64 -o artifacts/PRChecker-win-arm64
```

Use `win-x64` for Intel/AMD PCs. CI publishes both for every push; download them from the run's **Artifacts** section.

`nuget.config` limits package sources to nuget.org, regardless of feeds configured on your machine.

## Data storage on Windows

| Data | Where |
|---|---|
| Bitbucket access token, one per server | Windows Credential Manager, `PRChecker/token:<server>` |
| Settings and last-seen PR state | `%LOCALAPPDATA%\PRChecker\` (`settings.json`, `snapshots\`) |

To remove everything: uninstall the app, delete the `PRChecker/token:` entries in Credential Manager, and delete `%LOCALAPPDATA%\PRChecker`.
