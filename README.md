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

The app is signed and notarized. It updates itself with [Sparkle](https://sparkle-project.org): it checks once a week and asks before installing. To check right away, use **Settings → About → Check for Updates…**

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

macOS must also allow PR Checker's notifications (System Settings → Notifications → PR Checker). If it doesn't, Settings and the menu show a warning with a button that opens that page. Use **Send Test Notification** in Settings → General to check delivery. Click a notification to open its PR; close it to dismiss it.

Your own comments never notify you. Filters decide what gets announced, and changing a filter doesn't re-announce PRs the app already knew about. The first refresh after install or upgrade is silent.

## Settings

- **General:**
  - Notifications, with an option to hide PR details
  - Open at login
  - Refresh interval of 1–15 minutes. The app also refreshes after wake and when you open the list with stale data.
- **Bitbucket:**
  - Server URL and access token. They're saved only when **Save & Connect** succeeds.
  - **Sign Out**
  - Filters: hide drafts, and limit to project keys or `PROJECT/repo-slug` entries, comma-separated
- **About:** version and **Check for Updates…**

## Privacy

PR Checker has no backend, accounts, analytics or telemetry. Your data stays on your Mac and on your own Bitbucket server.

**What's stored, all locally on your Mac:**

| Data | Where |
|---|---|
| Bitbucket access token, one per server | Your login Keychain |
| Server URL, refresh interval, filters, toggles | The app's preferences (`~/Library/Preferences/dev.berke.PRChecker.plist`) |
| Last-seen PR state per server and user: IDs, titles, links, reviewer names, comment times. Used only to decide what to notify. | The same preferences file |

API responses aren't cached and no cookies are kept. The app uses a private network session with caching and cookies turned off.

**Network connections the app makes:**

- **Your Bitbucket server**, directly from your Mac.
  - Your token is sent only to the server it was saved for. Switching servers requires that server's token.
  - Redirects to other hosts aren't followed.
  - Responses are limited in size and page count, and at most 4 requests run at a time.
- **The update feed** (`SUFeedURL`), at most once a week or when you choose *Check for Updates…*. It's a plain download of a public file and sends no PR data or token. Sparkle's optional system-profile reporting is off. As with any web request, the host sees your IP address and the app version.

**Links:** clicking a PR or a notification opens it in your browser. Links are built from your configured server, and anything pointing elsewhere is never opened.

**Notifications:** they show PR titles, names and results unless you turn off **Show pull request details**. Turning notifications off, or signing out, clears the ones already delivered.

**To remove your data:**
- **Settings → Bitbucket → Sign Out** deletes the token and the stored PR state for that server.
- **To remove everything:**
  1. Quit the app and delete it.
  2. Delete the `dev.berke.PRChecker` items in Keychain Access.
  3. Run `defaults delete dev.berke.PRChecker`.

## Building from source

Requires Xcode 26 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
xcodegen generate
open PRChecker.xcodeproj
```

The Xcode project is generated from `project.yml` and isn't checked in.

To pre-fill a server URL in your builds, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set `DEFAULT_SERVER_URL`. That file is git-ignored, but the URL is readable in the built app's `Info.plist`, so don't set it for builds you publish.

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
  Assets.xcassets/        app icon
PRCheckerTests/           Swift Testing suite, incl. security tests against a stub server
Design/                   icon sources: macOS (SVG, 1024 PNG, .icns), Windows (SVG, .ico)
scripts/package.sh        sign, notarize, publish
```

## License

[MIT](LICENSE)
