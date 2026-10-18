# Tests

Run `make test` to build the CLI and run `cli.sh`.

`Swift/test-main.swift` runs the metadata, file info, Unicode, Finder color,
text display, repair, archive, and undo suites. `Swift/test-support.swift`
provides shared assertions, CLI execution, JSONL helpers, and fixtures. The runner compiles all production
sources except the CLI's `main.swift`; files under `Swift/` are included
automatically. Use distinct `-tests.swift` filenames for feature suites.

The repair suite checks raw xattr bytes after otherwise unchanged mutations,
`--fix` counts, dry runs, backups, repeat runs, copying, restore, and recursion.

The file info suite checks missing-field placeholders and broken symlinks,
including the link's own timestamp, tags, and colors, with and without `-L`.
It also checks the final warning count, marker colors and tag alignment, and
literal filenames in JSONL and NUL-separated output.

The Unicode suite covers Chinese and other scripts, combining accents,
supplementary-plane CJK, and emoji. It checks decoding, parsing, selective
repairs, and macOS tag writes, copying, export/restore, and `--fix` preservation.

The shell suite covers parsing, traversal, formatting, and macOS tag operations.
The text display suite checks diagnostic prefix colors, parser warnings, and
escaping of control characters in messages and executable names.
Swift metadata decoding and rendering checks are portable; tests requiring real
Finder metadata run only on macOS. `directory-order.swift` is a separate helper
for comparing traversal against Foundation's native directory order.

All fixtures belong under the current `Tests/.cli-work.*` directory. Each Swift
suite gets its own subdirectory through `TestContext`; `cli.sh` cleans up the
whole run on exit.

`compat-jdberry.sh` is the optional differential suite, invoked with
`make compat JDBERRY_TAG=/path/to/jdberry/tag`.
