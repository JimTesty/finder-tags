# Tests

Run `make test` to build the CLI and run `cli.sh`.

`Swift/test-main.swift` runs the help, stdin, verbosity, metadata, file info,
Unicode, Finder color, text display, mutation feedback, inspection, repair,
archive, and undo suites. `Swift/test-support.swift`
provides shared assertions, CLI execution, JSONL helpers, and fixtures. The runner compiles all production
sources except the CLI's `main.swift`; files under `Swift/` are included
automatically. Use distinct `-tests.swift` filenames for feature suites.

The help suite checks brief and detailed output, flag order and repetition,
stdin handling, and help-like text used as literal tag operands.

The stdin suite checks invalid UTF-8 and NUL rejection before any mutations,
unchanged explicit and piped targets, CRLF handling, and literal CR/LF paths.
The verbosity suite checks cumulative quiet/verbose flags, preserved previews,
JSONL and diagnostics, quiet summaries, and visible backup paths.
The mutation feedback suite checks action descriptions, single-target and bulk
unchanged reports, summaries, skip reasons, traversal roots, stdin, copy, fix,
restore, colors, raw placement followed by sorting, reversed display, and JSONL.
The inspection suite uses symlink loops for deterministic unavailable metadata,
checking preserved listing tags, omitted unknown types and target fields, and
restore error counts rather than false missing-item counts.

The repair suite checks raw xattr bytes after otherwise unchanged mutations,
`--fix` counts, dry runs, backups, repeat runs, copying, restore, and recursion.

The undo suite checks backup defaults for explicit paths, recursion flags,
entered directories, stdin paths, and restore, plus explicit overrides and
coverage of every changed target in a mixed operation. It collects the default
undo archives reported by its commands into the run's fixtures for cleanup.
It also checks that backup creation failures abort before later targets are
visited and suggest `--no-backup` for both direct mutations and restore.

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
On macOS it also uses `/usr/bin/script` to check default automatic color in a
real terminal, disabled color, early parser diagnostics, and uncolored JSONL.
Swift metadata decoding and rendering checks are portable; tests requiring real
Finder metadata run only on macOS. `directory-order.swift` is a separate helper
for comparing traversal against Foundation's native directory order.

All fixtures belong under the current `Tests/.cli-work.*` directory. Each Swift
suite gets its own subdirectory through `TestContext`; `cli.sh` cleans up the
whole run on exit.

`compat-jdberry.sh` is the optional differential suite, invoked with
`make compat JDBERRY_TAG=/path/to/jdberry/tag`.
