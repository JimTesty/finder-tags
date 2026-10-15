# Changelog

## Unreleased

- Consolidate text rendering, separate CLI parsing from option validation, and
  organize Swift regression suites by feature with shared test helpers.
- Escape control characters and backslashes in text listings, previews, and
  diagnostics before adding terminal formatting. Preserve original stored
  names, JSON values, and NUL-delimited stdout.
- Reject restore path escapes through Unicode separators or parent symlinks;
  require the final summary on export archives and reject malformed field types.
- Replay undo journals in reverse order, restore explicit null colors exactly,
  and create backup files exclusively without overwriting existing paths.
- Reject CR/LF/NUL in all tag-name inputs, including CRLF and stored metadata.
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
