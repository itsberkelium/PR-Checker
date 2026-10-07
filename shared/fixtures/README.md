# Shared test fixtures

Sample Bitbucket responses with the results both apps must produce. The macOS and Windows test suites load these same files, so a rule change shows up as a failing test on both sides until both apps follow it.

| File | Checks |
|---|---|
| `review-list.json` | Which PRs appear under *To review*, ids, links, badges |
| `activities.json` | Which activities count as comments by others |
| `build-stats.json` | Build result mapping |
| `servers.json` | Server URL validation and link ownership |

The rules are described in [docs/behavior.md](../../docs/behavior.md). All data is made up.
