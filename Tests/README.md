# Tests

Run `make test` to build the CLI and run `cli.sh`.

`Swift/test-main.swift` runs the metadata, Finder color, text display, repair,
archive, and undo suites. `Swift/test-support.swift` provides shared assertions, CLI
execution, JSONL helpers, and fixtures. The runner compiles all production
sources except the CLI's `main.swift`; files under `Swift/` are included
automatically. Use distinct `-tests.swift` filenames for feature suites.

The repair suite checks raw xattr bytes after otherwise unchanged mutations,
`--fix` counts, dry runs, backups, repeat runs, copying, restore, and recursion.

The shell suite covers parsing, traversal, formatting, and macOS tag operations.
Swift metadata decoding and rendering checks are portable; tests requiring real
Finder metadata run only on macOS. `directory-order.swift` is a separate helper
for comparing traversal against Foundation's native directory order.

All fixtures belong under the current `Tests/.cli-work.*` directory. Each Swift
suite gets its own subdirectory through `TestContext`; `cli.sh` cleans up the
whole run on exit.

`compat-jdberry.sh` is the optional differential suite, invoked with
`make compat JDBERRY_TAG=/path/to/jdberry/tag`.
