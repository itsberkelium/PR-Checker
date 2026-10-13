# Shared test fixtures

Sample API responses with the results both apps must produce. The macOS and Windows test suites load these same files, so a rule change shows up as a failing test on both sides until both apps follow it.

Responses are grouped by provider, one folder each; files at the top level don't depend on a provider.

| File | Checks |
|---|---|
| `servers.json` | Server URL validation and link ownership |
| `bitbucket-server/review-list.json` | Which PRs appear under *To review*, ids, links, badges |
| `bitbucket-server/merged-list.json` | Order and links of *Recently merged* |
| `bitbucket-server/activities.json` | Which activities count as comments by others |
| `bitbucket-server/build-stats.json` | Build result mapping |

A new provider gets its own folder with the same kinds of cases, in that provider's response format, so the same rules are checked against each one. Tests name a file by its path here without `.json`, e.g. `bitbucket-server/review-list`.

The rules are described in [docs/behavior.md](../../docs/behavior.md). All data is made up: no real company, project, people or server names.
