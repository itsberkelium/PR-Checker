# PR Checker for Windows

A system tray app for Windows 10 (1809) and later, built with C#, .NET 10 and WinUI 3. It follows the same rules as the macOS app, described in [docs/behavior.md](../docs/behavior.md). See the [main README](../README.md) for features, notifications and privacy.

**Status: released**, tested on Windows 11 (ARM64 and x64). Not yet available on Windows: the Automation command from the macOS app.

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
  Services/                Credential Manager tokens, notifications, Velopack updates, open at login, log
scripts/publish.sh         upload a release built by CI and create the GitHub release
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

## Releasing

Releases are built in CI and published from a maintainer's Mac or PC, so no Cloudflare credentials are stored in GitHub.

1. Bump `<Version>` in `Directory.Build.props`. Velopack compares it to decide what's newer.
2. Commit and push, then start **Actions → Windows release → Run workflow**.
   - It tests the core, publishes both architectures, and packs them with Velopack. Each architecture gets a `Setup.exe`, a portable zip and its update feed (`releases.<rid>.json`).
   - It also builds a delta update against the version currently on the CDN.
3. Publish that run, with optional release notes:

   ```bash
   windows/scripts/publish.sh <run-id> notes.md
   ```

   This:
   - uploads the packages, then the feeds, to `gu-cdn.berke.dev/pr-checker/windows/`, and checks that the live feeds list the new version
   - tags the commit CI built `windows-v<version>` and creates the GitHub release "PR Checker for Windows <version>" with the installers. The notes file's content opens the notes, and install instructions are added after it.
   - points the README's Windows badge at the new release

Installed apps check the feed once a week, or right away via **Settings → About → Check for updates**. They ask before installing.

**About the packages:**
- The app is installed per user into `%LOCALAPPDATA%\PRCheckerApp`, with a Start menu shortcut.
- Each architecture has its own update channel (`win-arm64`, `win-x64`).
- The installers aren't code-signed yet, so SmartScreen asks once.
- Updates are verified against the SHA-256 checksums in the feed, which is served over HTTPS.

## Notifications

The app uses the Windows App SDK's notifications when they're available. They need the Windows App Runtime's "Singleton" package, which self-contained apps don't install, so on many PCs the app falls back to Windows' built-in toast API instead. That fallback only needs a per-user registry entry with the app's name and icon. With it, clicking a notification opens the PR while PR Checker is running, which a tray app normally is. The log shows which one is in use.

## Data storage on Windows

| Data | Where |
|---|---|
| Bitbucket access token, one per server | Windows Credential Manager, `PRChecker/token:<server>` |
| Settings and last-seen PR state | `%LOCALAPPDATA%\PRChecker\` (`settings.json`, `snapshots\`) |
| Diagnostic log: startup steps and errors, no tokens or PR data, max 512 KB | `%LOCALAPPDATA%\PRChecker\logs\pr-checker.log` |
| Notification name and icon, only when Windows' built-in notifications are used | `HKCU\Software\Classes\AppUserModelId\Berke.PRChecker` |

To remove everything:
1. Uninstall PR Checker in **Settings → Apps**. This also removes the open-at-login and notification registry entries.
2. Delete the `PRChecker/token:` entries in Credential Manager.
3. Delete `%LOCALAPPDATA%\PRChecker`.
