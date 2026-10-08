# PR Checker

[![Release](https://img.shields.io/github/v/release/itsberkelium/PR-Checker)](https://github.com/itsberkelium/PR-Checker/releases/latest)
[![Build](https://github.com/itsberkelium/PR-Checker/actions/workflows/build.yml/badge.svg)](https://github.com/itsberkelium/PR-Checker/actions/workflows/build.yml)
[![Tag](https://img.shields.io/github/v/tag/itsberkelium/PR-Checker)](https://github.com/itsberkelium/PR-Checker/tags)

A menu bar (macOS) and system tray (Windows) app for **Bitbucket Server / Data Center** that shows the pull requests waiting for your review and the status of the ones you opened, and notifies you when something changes.

- **To review**: open PRs where you're a reviewer and haven't approved. PRs you marked *needs work* come back once the author pushes new commits.
- **Mine**: your open PRs with approvals, needs-work, merge conflicts, build status, comments and open tasks.
- The menu bar or tray icon shows how many PRs wait for your review, plus a `•` when one of your own PRs needs attention.
- Click any PR or notification to open it in the browser.

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/macos/menu-review-dark.png">
    <img src="docs/screenshots/macos/menu-review-light.png" width="400" alt="The To review tab listing pull requests with approval, comment and new-commit badges">
  </picture>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/screenshots/macos/menu-mine-dark.png">
    <img src="docs/screenshots/macos/menu-mine-light.png" width="400" alt="The Mine tab showing approvals, needs work, merge conflicts and build results">
  </picture>
</p>
<p align="center"><sub>macOS, with made-up data.</sub></p>

## Platforms

| | macOS | Windows |
|---|---|---|
| Status | Released | In development |
| Requires | macOS 15 or later | Windows 10 (1809) or later |
| Built with | Swift, SwiftUI | C#, .NET 10, WinUI 3 |
| Updates | Automatic (Sparkle), signed and notarized | Automatic (Velopack); unsigned for now |
| Code | [`macos/`](macos) | [`windows/`](windows) |

Both need Bitbucket Server or Data Center and a personal **HTTP access token** with *Read* permission (Profile → Manage account → HTTP access tokens). Both apps follow the same rules, described in [docs/behavior.md](docs/behavior.md).

## Install

**macOS:** download `PR-Checker-<version>.zip` from [Releases](../../releases), unzip it and move **PR Checker** to Applications. Open it, enter your server URL and token in Settings, and click **Save & Connect**. The app checks for updates once a week and asks before installing; to check right away, use **Settings → About → Check for Updates**

**Windows:** coming soon.

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

The operating system must also allow PR Checker's notifications. On macOS, that's System Settings → Notifications → PR Checker. If it doesn't allow them, Settings and the menu show a warning with a button that opens that page. Use **Send Test Notification** in Settings → General to check delivery. Click a notification to open its PR; close it to dismiss it.

Your own comments never notify you. Filters decide what gets announced, and changing a filter doesn't re-announce PRs the app already knew about. The first refresh after install or upgrade is silent.

## Settings

- **General:**
  - Notifications, with an option to hide PR details
  - Automation (macOS): run a command when a PR enters your review list or gets new commits, e.g. an automated pre-check. Values are passed as separate arguments, never through a shell.
  - Open at login
  - Refresh interval of 1–15 minutes. The app also refreshes after wake and when you open the list with stale data.
- **Bitbucket:**
  - Server URL and access token. They're saved only when **Save & Connect** succeeds.
  - **Sign Out**
  - Filters: hide drafts, and limit to project keys or `PROJECT/repo-slug` entries, comma-separated
- **About:** version and **Check for Updates**

## Privacy

PR Checker has no backend, accounts, analytics or telemetry. Your data stays on your computer and on your own Bitbucket server.

**What's stored, all locally on your computer:**

| Data | Where |
|---|---|
| Bitbucket access token, one per server | macOS Keychain / Windows Credential Manager |
| Server URL, refresh interval, filters, toggles | The app's settings file |
| Last-seen PR state per server and user: IDs, titles, links, reviewer names, comment times. Used only to decide what to notify. | The same settings file |

API responses aren't cached and no cookies are kept. 

**Network connections the app makes:**

- **Your Bitbucket server**, directly from your computer.
  - Your token is sent only to the server it was saved for. Switching servers requires that server's token.
  - Redirects to other hosts aren't followed.
  - Responses are limited in size and page count, and at most 4 requests run at a time.
- **The update feed**, at most once a week or when you choose *Check for Updates*. It's a plain download of a public file and sends no PR data or token. As with any web request, the host sees your IP address and the app version.

**Links:** clicking a PR or a notification opens it in your browser. Links are built from your configured server, and anything pointing elsewhere is never opened.

**Notifications:** they show PR titles, names and results unless you turn off **Show pull request details**. Turning notifications off, or signing out, clears the ones already delivered.

**To remove your data:**
- **Settings → Bitbucket → Sign Out** deletes the token and the stored PR state for that server.
- **To remove everything**, see [macOS](macos/README.md#data-storage-on-macos) or [Windows](windows/README.md#data-storage-on-windows).

## Development

| | |
|---|---|
| [`macos/`](macos/README.md) | Mac app: build, test, release |
| [`windows/`](windows/README.md) | Windows app: build, test, release |
| [`docs/behavior.md`](docs/behavior.md) | Rules both apps implement: review list, notifications, security limits |
| [`shared/fixtures/`](shared/fixtures) | Sample Bitbucket responses used by both test suites |
| [`Design/`](Design) | Icon sources for both platforms |
| [`.github/workflows/`](.github/workflows) | CI: builds and tests both apps on every push |

## License

[MIT](LICENSE)
