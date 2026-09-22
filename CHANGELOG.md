# Changelog

## 8.0 -- 2026-09-16

Initial public release baseline.

- Preserve Finder's stored tag order by default, with opt-in sorting and
  ordered add, remove, set, move, and copy operations.
- Provide a shared query grammar for `--match`, `--filter`, `--usage`, and
  `--find`, with comma AND, pipe OR, negation, and optional parentheses.
  `--match` remains filename-only by default while `--filter` shows tags.
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
