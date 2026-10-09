# Localization

Every user-facing string of both apps, in English and Turkish, is in [`strings.json`](strings.json). Each entry has:
- an `id`
- optional typed `args`
- the text in each language; an English text can have `one`/`other` forms for counts
- the `platforms` that use it

[`generate.py`](generate.py) turns it into typed accessors:
- `macos/PRChecker/L10n.swift`, used as `L10n.toReviewTab(n: 3)`
- `windows/src/PRChecker.Core/L10n.cs`, used as `L10n.ToReviewTab(3)`

Each returns the string in the current language. Switching languages needs no restart, and a missing string is a build error rather than a fallback at runtime.

**Changing strings:**
1. Edit `strings.json`.
2. Run `shared/localization/generate.py`.
3. Commit the JSON and the two generated files.

The script checks that every language uses exactly the declared `{arguments}`. CI fails if the generated files don't match the JSON.

**Turkish translations are confirmed by the maintainer.** Ask before adding or changing one.

**Conventions for Turkish:**
- "PR" for pull request, read "pi-ar": PR'ı, PR'a, PR'lar.
- "commit" stays as is.
- Build is "derleme"; "token" stays as is.
- Formal "siz".
- Sentence case.
- Bitbucket's own menu names stay in English.
