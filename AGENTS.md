# Repository-specific agent notes

- `Tests/cli.sh` keeps fixtures under `Tests/.cli-work.*`. Its Darwin branch
  performs real Finder-tag writes; the portable portion covers parser and
  traversal behavior. Keep cleanup scoped to each run's work directory.
- The shell tests grep Foundation's JSONSerialization output. JSONSerialization
  escapes `/` as `\/`, so nested JSON path assertions need fixed-string
  patterns containing the backslash.
- `private/` is intentionally ignored and contains maintainer planning notes.
  Do not stage or publish files from it unless explicitly requested.
