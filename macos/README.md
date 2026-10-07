# PR Checker for macOS

A native SwiftUI menu bar app. See the [main README](../README.md) for features, notifications and privacy. Shared behavior rules are in [docs/behavior.md](../docs/behavior.md).

All commands below run from this `macos/` folder.

## Building from source

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open PRChecker.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't checked in.

To pre-fill a server URL in your builds, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEFAULT_SERVER_URL`. That file is git-ignored, but the URL is readable in the built app's `Info.plist`, so don't set it for builds you publish.

Run the tests (CI runs them on every push):

```bash
xcodebuild -project PRChecker.xcodeproj -scheme PRChecker test
```

Regenerate the main README's screenshots from made-up data. This builds a Debug build and renders offscreen, with no network or real settings:

```bash
./scripts/screenshots.sh
```

## Releasing

`scripts/package.sh` does the whole release:

1. builds a Release archive signed with Developer ID
2. re-signs Sparkle's helpers
3. notarizes and staples the app
4. writes `dist/PR Checker.zip` and the Sparkle appcast

With `--publish`, it also uploads the update to the R2 bucket behind `SUFeedURL`, under the same path as the feed. With `--local`, it signs the app and installs it into `/Applications` to try changes, skipping notarization and publishing.

```bash
# 1. Bump MARKETING_VERSION in project.yml
# 2. Build, notarize and publish the update
./scripts/package.sh --publish
```

**One-time setup**

- A **Developer ID Application** certificate in your login keychain
- Notary credentials:
  `xcrun notarytool store-credentials "PRChecker" --apple-id <apple-id> --team-id <team-id>`
- Sparkle's EdDSA signing key, created with `generate_keys` from Sparkle's `bin/`. Its public key is `SPARKLE_PUBLIC_KEY` in `project.yml`. **Back up the private key.** Without it, installed apps reject every future update.
- `npx wrangler@4.148.0 login`, needed for `--publish`. The script pins wrangler and Sparkle to exact versions; bump them deliberately.

To release from another account or host, change `DEVELOPMENT_TEAM`, `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_KEY` in `project.yml`, and `TEAM_ID` and `R2_BUCKET` in the script.

## Project layout

```
PRChecker/
  BitbucketClient.swift   REST calls with size/page limits and same-server redirects
  ServerAddress.swift     server URL validation, link ownership, PR link building
  Models.swift            API payloads and the PRItem view model
  PRStore.swift           polling, enrichment, notification triggering
  ChangeDetector.swift    snapshot diffing that decides what to announce
  AppSettings.swift       preferences and filters
  Keychain.swift          per-server token storage
  Notifier.swift          macOS notifications
  Updater.swift           Sparkle integration
  Views/                  menu bar popover, PR rows, settings window
  Debug/                  screenshot renderer with made-up data (Debug builds only)
  Assets.xcassets/        app icon
PRCheckerTests/           Swift Testing suite, incl. security tests against a stub server
scripts/package.sh        sign, notarize, publish
scripts/screenshots.sh    regenerate ../docs/screenshots/macos
```

## Data storage on macOS

| Data | Where |
|---|---|
| Bitbucket access token, one per server | Login Keychain, service `dev.berke.PRChecker` |
| Settings and last-seen PR state | `~/Library/Preferences/dev.berke.PRChecker.plist` |

To remove everything: quit and delete the app, delete the `dev.berke.PRChecker` items in Keychain Access, and run `defaults delete dev.berke.PRChecker`.
