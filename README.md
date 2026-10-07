# PR Checker

A macOS menu bar app for **Bitbucket Server / Data Center** that shows the pull requests waiting for your review and the status of the ones you opened, and notifies you when something changes.

- **To review**: open PRs where you're a reviewer and haven't approved. PRs you marked *needs work* come back once the author pushes new commits.
- **Mine**: your open PRs with approvals, needs-work, merge conflicts, build status, comments and open tasks.
- The menu bar shows how many PRs wait for your review, plus a `•` when one of your own PRs needs attention.
- Click any PR or notification to open it in the browser.

## Requirements

- macOS 15 or later
- Bitbucket Server or Data Center
- A personal **HTTP access token** with *Read* permission (Profile → Manage account → HTTP access tokens)

## Install

1. Download `PR-Checker-<version>.zip` from [Releases](../../releases), unzip it and move **PR Checker** to Applications.
2. Open it, enter your server URL and token in Settings, and click **Save & Connect**.

The app is signed and notarized. It updates itself with [Sparkle](https://sparkle-project.org): it checks once a day and asks before installing. To check right away, use **⚙ → Check for Updates…**

The token is kept in your login Keychain. Everything else is stored in the app's preferences.

## Notifications

| When | For |
|---|---|
| A PR is added to your review list | To review |
| A PR you marked needs work gets new commits | To review |
| Someone else comments or replies | Both lists |
| Someone approves or marks needs work | Mine |
| Merge conflicts appear or get resolved | Mine |
| The build fails, or a failed build passes again | Mine |
| The PR is merged or declined | Mine |

Your own comments never notify you. Filters decide what gets announced, and changing a filter doesn't re-announce PRs the app already knew about. The first refresh after install or upgrade is silent.

## Settings

- **Server URL and access token**
- **Refresh interval:** 1–15 minutes. The app also refreshes after wake and when you open the list with stale data.
- **Filters:** hide drafts, and limit to project keys or `PROJECT/repo-slug` entries, comma-separated
- **Notifications** and **Open at login**

## Building from source

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open PRChecker.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't checked in.

To pre-fill a server URL in your builds (handy when you hand the app to a team), copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEFAULT_SERVER_URL`. That file is git-ignored.

Run the tests:

```bash
xcodebuild -project PRChecker.xcodeproj -scheme PRChecker test
```

## Releasing

`scripts/package.sh` does the whole release:

1. builds a Release archive signed with Developer ID
2. re-signs Sparkle's helpers
3. notarizes and staples the app
4. writes `dist/PR Checker.zip` and the Sparkle appcast

With `--publish`, it also uploads the update to the R2 bucket behind `SUFeedURL`.

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
- `npx wrangler login`, needed for `--publish`

To release from another account or host, change `DEVELOPMENT_TEAM`, `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_KEY` in `project.yml`, and `TEAM_ID` and `R2_BUCKET` in the script.

## Project layout

```
PRChecker/
  BitbucketClient.swift   REST calls: dashboard, activities, build status, PR state
  Models.swift            API payloads and the PRItem view model
  PRStore.swift           polling, enrichment, notification triggering
  ChangeDetector.swift    snapshot diffing that decides what to announce
  AppSettings.swift       preferences and filters
  Keychain.swift          token storage
  Notifier.swift          macOS notifications
  Updater.swift           Sparkle integration
  Views/                  menu bar popover, PR rows, settings window
PRCheckerTests/           Swift Testing suite
scripts/package.sh        sign, notarize, publish
```

## License

[MIT](LICENSE)
