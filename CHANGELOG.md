# Changelog

## 9.0 -- Unreleased

- Accept harmless inapplicable presentation options across commands, including
  mutation layout flags, text formatting with JSONL, and export display flags.
  Ignore read-only backup/dry-run/placement flags and inapplicable file ordering;
  warn about benign ignores only under verbose. Retain target, edit, and format
  safety errors. Quiet now hides undo archive path announcements, without
  disabling backups or hiding backup failures.
- Report verified mutation actions and resulting tags on stdout by default,
  using `(empty)` for no tags. Honor display sorting/reversal and tag colors;
  identify paths for bulk work and distinguish children across traversal roots.
  Add concise bulk summaries and single-target unchanged confirmations.
  Verbose adds stored before-tags, color numbers, unchanged items, skip reasons,
  and full totals without duplicate action reports. Quiet retains its existing
  diagnostics, previews, and requested output policy.
- Clarify that placement uses raw stored order, `--reverse` is display-only,
  and `--sorted-tags` sorts the stored result last, potentially overriding placement.
- Default color to `auto` for output and diagnostics. Clarify that color also
  applies to file-info decorations, broken-link markers, and diagnostic prefixes.
- Keep `-L` traversal of dangling links working without attempting descent;
  permission failures and symlink loops remain errors. Add focused tests for
  stdin validation, unavailable metadata, cumulative verbosity, backup aborts,
  and terminal versus redirected color output.
- Reject malformed UTF-8 stdin paths before processing any files. Preserve
  embedded CR characters, recognize CRLF only at line boundaries, and reject
  NUL bytes in line-delimited paths.
- Replace guessed filesystem types and existence results with checked
  `stat`/`lstat` lookups. Keep readable listing tags with warnings and omit an
  unknown JSONL kind; required export, backup, traversal, and restore checks
  report errors. Restore no longer counts inspection failures as missing.
- Preserve unknown symlink target status instead of reporting a missing
  target. Omit unavailable target fields with diagnostics and retain known
  link destinations; report explicit-operand resolution failures.
- Add cumulative `-q`/`--quiet` and `-v`/`--verbose` controls. Quiet hides routine
  text summaries while preserving diagnostics, previews, and
  requested output.
- Stop the whole operation on backup creation, record-write, or sync failures
  before the pending mutation. Use throwing backup write/close APIs, report
  creation failures with their OS reason, and suggest `--no-backup` on failure.
- Make `-h` / `--help` brief, with detailed help via `-hh` or `-h -v` in either
  order. Keep negations, aliases, and advanced options in detailed help.
- Add `--no-color` as an alias for `--color=off`, accepting `off` alongside
  the existing color modes. Prefer `--filter` in brief help and show `--tagged-only`.
- Accept `--color=on` and make `yes` and `on` force color. `--color=auto` and
  bare `--color` / `-c` use terminal detection. Show `--color[=yes/no]` in help.
- Add `--repair`, `--include-hidden`, and `--replace` as synonyms for `--fix`,
  `--all`, and `--set`, with completions and documentation.
- Add `--del` and `--delete` as synonyms for `--remove`, available in shell
  completions and documentation without expanding the brief help.
- Default backup to off for explicit command-line mutation targets, and to on
  for the whole operation with recursive or entered traversal, stdin path
  input, or restore. Recursive flags enable backup even with file-only paths;
  explicit backup options still override the default.
- Use `--backup` to enable a temporary undo archive and `--backup-path PATH`
  to enable one at a chosen path, replacing the former `--backup PATH` syntax.
- Rename duplicate tag names with repeated U+FFFD suffixes, preserving order
  and colors and avoiding existing names. Warn on renames, count each repaired
  entry once, and warn when identical command-line tags are collapsed.
- Persist metadata repairs during mutations even when recovered before/after
  tags match. Add `--fix` with fixed/deleted counts, dry-run previews, traversal,
  and backup support. Verify that written metadata no longer needs repair.
- Consolidate text rendering, separate CLI parsing from option validation, and
  organize Swift regression suites by feature with shared test helpers.
- Escape control characters and backslashes in text listings, previews, and
  diagnostics before adding terminal formatting. Preserve original stored
  names, JSON values, and NUL-delimited stdout.
- Reject restore path escapes through Unicode separators or parent symlinks;
  require the final summary on export archives and reject malformed field types.
- Replay undo journals in reverse order, restore explicit null colors exactly,
  and create backup files exclusively without overwriting existing paths.
- Recover imperfect tag entries individually with warnings: replace each
  CR/LF/NUL with U+FFFD, ignore empty names, convert non-string entries to text,
  and preserve malformed color suffixes as part of the repaired name. Apply
  name repairs to command-line operands and archive tags too, preserving
  each retained archive tag's aligned color.
- Keep tag output when optional file info or directory suffixes are unavailable,
  report skipped malformed Spotlight results, and count metadata warnings in
  export/restore summaries. Omit dangling symlinks' unavailable target file info.
- Keep launcher build output on stderr, honor sorted tags during restore and
  conversion, reject operands on boolean switches, and accept CRLF stdin paths.
- Make ordinary JSONL item paths consistently root-relative, with `.` for the
  root item. Copy source paths are absolute; text conversion rejects JSONL mode.
- Render each tag using its stored color number, including custom tags and
  explicit no-color values, without Finder preference or name-based guesses.
- Preserve colors during copying and edits, including color-only copies. Save
  per-item colors in export and undo archives and restore them. Older version 3
  archives remain readable; unknown color numbers are retained unchanged.
- Add `--dot-files` as an alias for `--all`/`-A` to include hidden files and
  directories during filesystem traversal.
- Add `--no-sort-files` to preserve filesystem enumeration order, including
  during export, and disable Spotlight display-name sorting. File order is
  unspecified with this option; sorted traversal remains the default.

## 8.0 -- 2026-09-16

Initial public release baseline.

- Preserve Finder's stored tag order by default, with opt-in sorting and
  ordered add, remove, set, move, and copy operations.
- Provide a shared query grammar for `--match`, `--filter`, `--usage`, and
  `--find`, with comma AND, pipe OR, negation, and optional parentheses.
  `--match` remains filename-only by default while `--filter` shows tags.
- Provide `--verbose` / `-v` informational messages on stderr; `--version` is
  now long-only.
- Provide direct filesystem traversal, stable literal filename ordering, hidden
  item handling, stdin path input, and simple traversal exclusions.
- Export and restore canonical root-relative JSONL archives with dry-run support,
  file metadata, tag-color definitions, per-file undo archives, and explicit
  symlink-following policy.
- Provide JSONL-to-human-readable conversion with file-info, color, slash,
  symlink, reverse, and indentation controls.
- Include shell tests, macOS Finder-tag integration checks, and optional
  compatibility testing against `jdberry/tag`.

Known limitations are documented in [`REVIEW.md`](REVIEW.md). In particular,
restore is not transactional, Finder metadata behavior varies by filesystem,
and archive comparison/change-detection commands remain future work.
