# PR Checker behavior

The rules both apps implement. The macOS app (`macos/`) is the reference implementation; the Windows app (`windows/`) must behave the same. Sample API responses for tests live in [`shared/fixtures/`](../shared/fixtures).

## Bitbucket API

All requests go to the configured server with `Authorization: Bearer <token>` and `Accept: application/json`.

| Purpose | Request |
|---|---|
| PRs I review / I authored | `GET rest/api/1.0/dashboard/pull-requests?role=REVIEWER\|AUTHOR&state=OPEN&limit=100&start=<n>` |
| Current user | `X-AUSERNAME` response header of any request; fallback `GET plugins/servlet/applinks/whoami` (plain text) |
| Comments on a PR | `GET rest/api/1.0/projects/{key}/repos/{slug}/pull-requests/{id}/activities?limit=50` |
| Build result of a commit | `GET rest/build-status/1.0/commits/stats/{commit}` |
| State of a PR that left the list | `GET rest/api/1.0/projects/{key}/repos/{slug}/pull-requests/{id}` → `state` |

Validating a connection uses `dashboard/pull-requests?limit=1` and reads the user from `X-AUSERNAME` (or `whoami`).

## Server address

- Must be `https`, with a host, no user name or password, no query and no fragment.
- Normalized: lowercase scheme and host, port 443 dropped, trailing slashes removed. The normalized URL is the server's **id**.
- A URL is **owned** by the server when it's `https`, same host (case-insensitive), same port, no credentials, and its path equals the context path or starts with `<context path>/`.

## Connection and token

- Server URL and token are a draft until **Save & Connect** succeeds. Nothing is sent while editing.
- A blank token reuses the saved token **only for the same server id**. A different server requires its own token; otherwise fail with "Enter the access token for this server." without any request.
- Save & Connect first validates the draft (one request). Only on success: save the token for that server (update in place, add if missing), then the server URL; remove the previous server's token when switching.
- A failed token write changes nothing (old server, old token stay).
- Tokens are stored per server id in the OS credential store; never in the settings file.
- Changing the connection or signing out cancels in-flight work and clears displayed data, caches and errors.
- **Sign Out** deletes the token and this server's stored snapshots, and clears delivered notifications. The server URL is kept.

## Review list ("To review")

From the REVIEWER dashboard, find my reviewer entry (matching user `name` or `slug`, case-insensitive). Let *pushed* = my `lastReviewedCommit` exists and differs from the PR's `fromRef.latestCommit`.

| My status | Shown? | "New commits" badge |
|---|---|---|
| `APPROVED` | No | – |
| `NEEDS_WORK` | Only if *pushed* | Yes |
| `UNAPPROVED` (or unknown) | Yes | If *pushed* |

PRs where I'm not a reviewer are skipped.

## PR item

- **id** = `{projectKey}/{repoSlug}#{number}` using the **target** (`toRef`) repository.
- **link** = `<server>/projects/{key}/repos/{slug}/pull-requests/{number}`, each identifier encoded as a single path component. Links from API responses are never used.
- Conflicts when `properties.mergeResult.outcome == "CONFLICTED"`. Comment and open-task counts from `properties`.
- **Needs attention** (mine only): any reviewer needs work, conflicts, failed build, or open tasks > 0.
- Lists are sorted by `updatedDate`, newest first.

## Filters

- **Hide drafts** (default on) hides `draft == true`.
- **Projects/repos**: comma-separated; trimmed, lowercased, empties dropped. A PR matches `projectkey` or `projectkey/reposlug`. Empty filter shows everything.
- Filters decide what's **shown and announced**, never what's tracked.

## Comments, builds and limits

- **Comments by others**: activities with `action == COMMENTED` and `commentAction` in `ADDED`, `REPLIED`, by anyone but me. "New" is decided by `createdDate`, never by activity id (ids aren't chronological).
- Fetch comments for every PR (including hidden ones); reuse cached results while the PR's `commentCount` and `updatedDate` are unchanged.
- **Build state**: `failed > 0` → failed, else `inProgress > 0` → running, else `successful > 0` → passed, else none. Only for my PRs; cache finished results (passed/failed) per commit.
- At most **4** requests in flight for comments, builds and state lookups.
- Pagination: at most **20 pages** of 100; a `nextPageStart` that doesn't increase fails the refresh ("inconsistent page sequence"); exceeding 20 pages fails with "more than 2000 open pull requests".
- Responses larger than **8 MiB** are rejected while downloading.
- HTTP 401/403 → token rejected; 429 → rate limited (reported, refresh still shows what it has); other non-2xx → error with the status code.
- Redirects are followed only when the target is **owned** by the server; otherwise the 3xx is returned as an error.
- No HTTP cache, no cookies.

## Refreshing

- Every *N* minutes (1, 2, 5 default, 10, 15), after wake, and when the list opens with data older than 60 s.
- Only one refresh runs at a time; a second request waits for it.
- Each refresh belongs to a connection generation; results from an older generation or a cancelled refresh are discarded.
- A refresh that fails keeps the previous lists and shows the error.

## Automation command

Optional, off by default. *Implemented on macOS; Windows: not yet.*

- After a successful refresh, run the configured command once for each PR in the (filtered) review list whose current commit hasn't triggered it yet: new review requests and PRs with new commits.
- Triggered commits are remembered per **server id + lowercased user name** as `{pr id}@{commit}`, pruned to PRs still in the list. While the option is off nothing is recorded, so turning it on runs for the current list.
- The command is split into arguments once (whitespace, `'…'`, `"…"`, backslash escapes; no variables, globbing or substitution), then placeholders are filled **inside each argument**: `{link} {commit} {project} {repo} {id} {source} {target} {title} {author}`. A leading `~/` expands to the home folder. PR content never passes through a shell. `{link}` is the link built from the server address.
- Runs without waiting; output is appended to a log file. Sign Out forgets the triggered commits for that server.

## Notifications

Snapshots are stored per **server id + lowercased user name**. The first refresh for a connection only records a snapshot (silent). Snapshots cover every tracked PR, including filtered-out ones.

Snapshot per PR in my review list: the newest comment time by others.
Snapshot per PR of mine: title, link, project, repo, number, whether it was shown, approvers, needs-work reviewers, conflicted, **settled build** (a running build keeps the previous settled value), newest comment time by others.

Announce only PRs that pass the filters; at most one notification per PR per refresh, lines joined by newlines:

| Situation | Title | Body |
|---|---|---|
| PR new in review list, without new commits | `Review requested by {author}` | PR title |
| PR new in review list, with new commits | `New commits to re-review` | PR title |
| Review PR: comments by others newer than snapshot | PR title | `💬 N new comment(s) from A, B` |
| Mine: new approver | PR title | `✅ Approved by {name}` |
| Mine: new needs-work | PR title | `✋ {name} marked it needs work` |
| Mine: conflicts appeared / resolved | PR title | `⚠️ Merge conflicts` / `🔧 Conflicts resolved` |
| Mine: settled build → failed | PR title | `❌ Build failed` |
| Mine: settled build failed → passed | PR title | `✅ Build fixed` |
| Mine: comments by others newer than snapshot | PR title | `💬 N new comment(s) from A, B` (authors in time order, unique) |
| Mine: shown PR left the list | Snapshot title | `🎉 Merged` / `🚫 Declined` / `No longer open` (state lookup failed) |

At most 10 departed-PR state lookups per refresh. With **Show pull request details** off, every notification is `PR Checker` / `A pull request has an update. Click to open it.` (the link still opens on click).

Clicking a notification opens its link only if the configured server owns it. Turning notifications off clears delivered ones.
