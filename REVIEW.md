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
among multiple case-fold-equivalent stored tags, operations that require one
specific tag prefer exact spelling where possible and otherwise report
ambiguity rather than guessing.

### 7. Symlink behavior has two layers

Default traversal explicitly resolves/follows symlinks, which means recursive
work can escape the requested tree through a directory symlink. Cycles are
suppressed by resolved directory identity, but the same target can still be
visited through different non-cyclic aliases.

`--no-follow-symlinks` prevents recursive descent through symlinked directories
and skips the program's explicit path resolution. Foundation itself ultimately
controls how tag resource values behave when directly asked about a symlink, so
this option should primarily be viewed as a traversal-safety control rather than
a promise to create independent symlink metadata.

### 8. Recursive traversal is synchronous

Large trees can take time and a metadata read is performed for each visited
item. There is no parallelism. Parallel reads might improve throughput, but
would make deterministic output and mutation/error behavior more complicated.

### 9. Plain text cannot unambiguously encode every tag/path

Quoted input supports commas inside tag names, but default output still uses
commas between tags. A tag containing a comma is therefore ambiguous in that
text format. One-tag-per-line output is also ambiguous if a tag itself contains
a newline.

`--jsonl` is the recommended machine-readable format because JSON escaping
preserves those strings structurally.

`*` remains reserved as a wildcard for match/usage/find/remove, so those
operations cannot target a literal tag named `*`.

### 10. Relative text paths can be ambiguous with multiple roots

To match `jdberry/tag`, descendants of each explicit `-e/-R` directory are
shown relative to that root. If several roots each contain `sub/file`, plain
text can therefore contain repeated `sub/file` paths.

Use `--absolute` or JSONL's `root`, `absolutePath`, and `resolvedPath` fields
when disambiguation matters.

### 11. Finder color discovery is private and fragile

Tag read/write uses public Foundation APIs. `--color` is different: Finder does
not expose its named-tag color map through the same API, so color discovery
best-effort parses Finder preference data. A future macOS release can break it.
Failure is intentionally non-fatal.

The color lookup is case-insensitive and may not distinguish hypothetical
case-distinct Finder tag definitions with different colors.

### 12. Spotlight results can be stale

`--find` uses `NSMetadataQuery`, so discovery depends on Spotlight indexing and
can lag immediately after metadata changes. For each result, the program rereads
the live Foundation tag array before displaying it, which avoids using the
index's tag ordering and filters obvious stale matches, but Spotlight can still
omit a newly matching file until it is indexed.

`--usage` deliberately uses direct traversal instead, so compatibility testing
cannot compare fresh `--usage` results strictly against `jdberry/tag`'s
Spotlight-backed implementation.

## Potential improvements / features

1. **CI on multiple macOS/Swift versions.** Useful once the repository is public
   and stable enough to justify maintaining a matrix.
2. **`--home` / `--local` / `--network` Spotlight scopes.** These would complete
   more of `jdberry/tag`'s `--find` interface if users need them.
3. **More differential Spotlight tests.** `--find`/`--usage` comparisons need
   indexing-aware fixtures or waits to avoid flaky fresh-file results.
4. **Optional filesystem identity deduplication.** Hard links and multiple
   non-cyclic symlink aliases can intentionally cause the same underlying file
   to be processed more than once. A future opt-in dedupe mode could help bulk
   mutations where path identity does not matter.

## Deliberately not recommended yet

* Transaction/rollback machinery for multi-file tag edits: too much complexity
  for low-value metadata unless real users demonstrate a need.
* Parallel recursive mutation: concurrency would amplify read-modify-write race
  risks and make deterministic behavior harder to reason about.
* Reimplementing Finder xattrs directly: the Foundation abstraction is much
  cleaner and should remain the primary API unless a concrete limitation is
  found.
