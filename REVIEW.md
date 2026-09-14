# Source review and development notes

Last reviewed: 2026-09-14

This is a lightweight source review, not a security audit. The code has shell
coverage and macOS integration tests, but the project is still **not thoroughly
tested** across machines, macOS versions, filesystems, and workloads.

## Known limitations / risks

### 1. Apple's ordering contract is not explicit

Foundation exposes Finder tags as an array through `URLResourceKey.tagNamesKey`,
and current Finder behavior makes the array order useful. Apple does not appear
to promise that Finder's UI ordering semantics are a permanent API contract.
The project intentionally relies on the behavior that motivated it.

### 2. Read-modify-write races

`--add`, `--remove`, and `--move` read the complete tag array, compute a
replacement, then write it. Another process changing tags in between can have
its change overwritten. Avoiding this robustly would require locking or file
coordination with considerably more complexity.

For Finder tags this is currently considered an acceptable tradeoff.

### 3. Multi-file operations are not transactional

If a command changes ten files and the eleventh fails, the first ten are not
rolled back. `--dry-run` is available when a preview matters.

### 4. Immediate read-back verification may be strict on unusual filesystems

Every write is immediately read back and compared at the Swift string-array
level, including order. This catches silent persistence, normalization, and
reordering failures. On a network or unusual filesystem with delayed metadata
visibility, it could report failure even if metadata becomes visible shortly
afterward.

### 5. Filesystem support varies

Finder tags depend on macOS metadata/xattr support. Network shares, NASes,
foreign filesystems, synchronization tools, and copy utilities can drop or
transform that metadata. This tool cannot make an underlying filesystem support
Finder tags reliably.

### 6. Case-insensitive comparison may not exactly reproduce Finder forever

The implementation uses Swift/Foundation Unicode case folding with a fixed
POSIX locale for default case-insensitive tag matching. That is a reasonable
approximation to Finder behavior, but Apple's exact internal comparison rules
are not documented here and could differ for unusual Unicode strings.

Case-distinct stored strings are preserved. When an operation is ambiguous
among multiple case-fold-equivalent stored tags, `--add`/`--move` prefer exact
spelling where possible and otherwise report ambiguity rather than guessing.

### 7. Symlink traversal can escape the requested tree

Symlinks are intentionally resolved because Finder's visible tags belong to the
target. Recursive traversal follows symlinked directories and suppresses cycles
using the active chain of resolved directory paths.

Consequently, `tag -R --set ... directory` can modify a target outside
`directory` if a descendant symlink points there. This is deliberate but worth
remembering for recursive mutations.

A target can also be visited more than once through different non-cyclic aliases.
That is useful for traversal semantics but means the same underlying file could
be processed repeatedly.

### 8. Recursive traversal is synchronous

Large trees can take time and a metadata read is performed for each visited
item. There is no parallelism. Parallel reads might improve throughput, but
would make deterministic output and mutation/error behavior more complicated.

### 9. Plain text cannot unambiguously encode every tag/path

Quoted input now supports commas inside tag names, but the default output still
uses commas between tags. A tag containing a comma is therefore ambiguous in
that text format. One-tag-per-line output is also ambiguous if a tag itself
contains a newline.

`--jsonl` is the recommended machine-readable format because JSON escaping
preserves those strings structurally.

`*` remains reserved as a wildcard for match/usage/remove, so those operations
cannot target a literal tag named `*`.

### 10. Relative output paths can be ambiguous with multiple roots

To match `jdberry/tag`, descendants of each explicit `-e/-R` directory are
shown relative to that root. If several roots each contain `sub/file`, text and
JSONL can therefore contain repeated `sub/file` paths.

A future JSONL `root`/`absolutePath` field or `--absolute` switch could remove
that ambiguity without changing compatibility-oriented text output.

### 11. Finder color discovery is private and fragile

Tag read/write uses public Foundation APIs. `--color` is different: Finder does
not expose its named-tag color map through the same API, so color discovery
best-effort parses Finder preference data. A future macOS release can break it.
Failure is intentionally non-fatal.

The color lookup is case-insensitive and may not distinguish hypothetical
case-distinct Finder tag definitions with different colors.

### 12. Compatibility testing has an intentional blind spot around `--usage`

`Tests/compat-jdberry.sh` differentially checks the common direct-file/traversal
features against a locally installed `jdberry/tag`, but does not make
`--usage` a strict pass/fail comparison. Upstream uses Spotlight and this tool
uses direct traversal, so newly created sample files may not be visible to both
engines at the same moment.

## Potential improvements / features

Roughly in order of usefulness:

1. **`--before TAG` / `--after TAG`.** More convenient than calculating a
   numeric `--at`/`--move` index in scripts that know neighboring tags.
2. **`--absolute` and richer JSONL path fields.** Include the logical root and
   resolved/absolute path for multi-root and symlink-heavy machine workflows.
3. **Paths from stdin / NUL-delimited input.** Helpful for very large file sets
   and unusual filenames, analogous to `find -print0 | xargs -0` workflows.
4. **Optional `--no-follow-symlinks`.** The current follow behavior is useful
   and Finder-like, but a defensive override could be valuable for recursive
   mutations.
5. **Optional Spotlight-backed `--find`.** This could restore more
   `jdberry/tag` compatibility without changing the order-preserving core.
6. **More macOS integration tests.** Especially Unicode case folding,
   comma/quote/newline-containing tags, package directories, APFS volumes,
   removable media, network volumes, aliases/hard links, and permission errors.
7. **CI on multiple macOS/Swift versions.** Particularly Apple Swift 5.5.x and
   current Swift/macOS.
8. **Man page / shell completions.** Worth adding once the command-line
   interface is stable.

## Deliberately not recommended yet

* Transaction/rollback machinery for multi-file tag edits: too much complexity
  for low-value metadata unless real users demonstrate a need.
* Parallel recursive mutation: concurrency would amplify read-modify-write race
  risks and make deterministic behavior harder to reason about.
* Reimplementing Finder xattrs directly: the Foundation abstraction is much
  cleaner and should remain the primary API unless a concrete limitation is
  found.
