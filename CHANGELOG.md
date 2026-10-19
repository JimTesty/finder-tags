# Changelog

## 9.0 -- Unreleased

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
