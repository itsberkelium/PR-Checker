# Privacy Policy

*Effective 9 October 2026. Applies to PR Checker for macOS and Windows.*

PR Checker is a free, open-source app with **no backend, no accounts, no analytics and no telemetry**. The developer doesn't collect, receive or store any data about you or your pull requests.

## Data stored on your computer

Everything PR Checker keeps stays on your computer:

| Data | macOS | Windows |
|---|---|---|
| Bitbucket access token, one per server | Login Keychain | Windows Credential Manager |
| Server URL and settings | `~/Library/Preferences/dev.berke.PRChecker.plist` | `%LOCALAPPDATA%\PRChecker\settings.json` |
| Last-seen pull request state, per server and user (IDs, titles, links, reviewer names, comment times), used only to decide what to notify you about | Same preferences file | `%LOCALAPPDATA%\PRChecker\snapshots\` |
| Diagnostic log: startup steps and errors, no tokens or pull request data | — | `%LOCALAPPDATA%\PRChecker\logs\pr-checker.log` |
| Automation log, only if you turn Automation on | `~/Library/Logs/PR Checker/automation.log` | — |

API responses aren't cached and no cookies are stored. Notifications show pull request titles and names unless you turn off **Show pull request details**. Notification Center keeps them until you clear them, turn notifications off or sign out.

## Connections PR Checker makes

- **Your Bitbucket server**, directly from your computer with your token.
  - The token is only ever sent to the server it was saved for.
  - What that server records is up to whoever runs it.
- **The update feed** at `gu-cdn.berke.dev`, served through Cloudflare, about once a week or when you check for updates.
  - It's a download of a public file. No pull request data, token or identifier is sent.
  - Like any web request, it reveals your IP address and the app's version to the host. Cloudflare processes this under its [privacy policy](https://www.cloudflare.com/privacypolicy/).
  - The developer doesn't use this information to identify anyone.
- **GitHub, only when you choose to.** Downloading a release or using **Report a Problem** opens github.com in your browser.
  - Report a Problem fills in the app version, operating system and language. Nothing is submitted until you post the issue yourself.
  - Issues are public. Don't include server URLs, pull request titles, names or tokens.
  - GitHub's [privacy statement](https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement) applies there.

## Your choices

- **Settings → Bitbucket → Sign Out** removes the token and the stored pull request state for that server.
- **To remove everything:** uninstall the app, delete its Keychain or Credential Manager entries, and delete the folders and files listed above.

## Changes and contact

Changes to this policy are published in this file; its history is on GitHub. For questions, open an issue at https://github.com/itsberkelium/PR-Checker/issues.
