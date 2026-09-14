# Source review and development notes

Last reviewed: 2026-09-14

This is a lightweight source review, not a security audit. The project is still
barely tested, especially on real macOS filesystems other than the maintainer's
machine.

## Findings fixed during this review

1. **Explicit-directory output differed from `jdberry/tag`.** With `-e/-R`,
   descendants were printed with the directory argument prefixed. They are now
   displayed relative to each explicit directory, matching `jdberry/tag`.
2. **Color output leaked into pipes.** `-c` now emits ANSI color only when
   stdout is a terminal, matching `jdberry/tag` behavior.
3. **JSON plus a real mutation emitted `[]`.** Successful add/remove/set/copy
   operations now emit structured before/after JSON records.
4. **Long output names had one extra space.** Filename padding now matches
   `jdberry/tag` more closely before the tag-field tab.
5. **Relative child error paths could be ambiguous.** User-facing listing paths
   stay relative for compatibility, but metadata errors now identify the real
   filesystem path.
6. **Build settings could change without rebuilding.** `Makefile` is now a
   dependency of the binary, and builds explicitly select Swift 5 language
   mode for Swift 5.5 compatibility.
7. **macOS tests did not exercise real tag writes.** `make test` now performs a
   small ordered set/add/remove/reverse/copy integration test when run on macOS.

## Known limitations / risks

### 1. Apple's ordering contract is not explicit

Foundation exposes Finder tags as an array through `URLResourceKey.tagNamesKey`,
and current Finder behavior makes the array order useful. Apple does not appear
to promise that Finder's UI ordering semantics are a permanent API contract.
The whole project intentionally relies on the behavior that motivated it.

### 2. Read-modify-write races

`--add` and `--remove` read the complete tag array, compute a replacement, then
write it. Another process changing tags in between can have its change
silently overwritten. Avoiding this would require locking or another
coordination mechanism with substantially more complexity.

For Finder tags this is currently considered an acceptable tradeoff.

### 3. Multi-file operations are not transactional

If a command changes ten files and the eleventh fails, the first ten are not
rolled back. `--dry-run` is available when a preview matters.

### 4. Immediate read-back verification may be strict on unusual filesystems

Every write is read back and compared byte-for-byte at the Swift string-array
level, including order. This catches silent write failures, normalization, and
reordering. On a network or unusual filesystem with delayed metadata
visibility, it could theoretically report a failure even if the metadata
appears shortly afterward.

### 5. Filesystem support varies

Finder tags depend on macOS metadata/xattr support. Network shares, NASes,
foreign filesystems, synchronization tools, and copy utilities can drop or
transform that metadata. This tool cannot make an underlying filesystem support
Finder tags reliably.

### 6. `--usage` has an unavoidable optional-operand ambiguity

`--usage TAGS` is compatible and convenient, but if TAGS is optional then the
next bare token can also look like a path. The parser currently preserves the
accepted behavior from earlier versions.

Prefer `--usage=TAG`, `-uTAG`, or `--usage -- PATH` in scripts.

### 7. The tag-list grammar cannot represent every possible tag name

For compatibility with `jdberry/tag`, tag operands are comma-separated and
whitespace around each component is trimmed. A tag name containing a literal
comma cannot be specified unambiguously. `*` is also reserved by match/remove
semantics.

A future escaped or repeated-option grammar could remove this limitation, but
changing the existing grammar would hurt compatibility.

### 8. Symlink behavior is not explicitly specified or tested

Foundation/FileManager decides how resource values behave for symbolic links.
The current tests do not establish whether users expect tags to apply to a link
itself or its target in every case. This should be tested on macOS before
promising semantics.

### 9. Recursive traversal is synchronous

Large trees can take time and a metadata read is performed for each visited
item. There is no parallelism. Parallel reads might improve throughput, but
would make output ordering and error handling more complicated.

### 10. JSON buffers the whole result in memory

Text output streams as it is produced. JSON accumulates all records before
serialization so it can emit one valid array. This is simple and convenient,
but a huge recursive query can use significant memory.

A future `--jsonl` / NDJSON mode would stream naturally.

### 11. Relative JSON paths can be ambiguous with multiple directory roots

To match `jdberry/tag`, descendants of each explicit `-e/-R` directory are
shown relative to that root. If several roots contain `sub/file`, JSON can
therefore contain repeated `"path": "sub/file"` values.

Possible future fix: add a separate `root` and/or `absolutePath` JSON field
without changing text output.

### 12. Finder color discovery is private and fragile

Tag read/write uses public Foundation APIs. `--color` is different: Finder does
not expose its named-tag color map through the same API, so color discovery
best-effort parses Finder preference data. A future macOS release can break it.
Failure is intentionally non-fatal.

## Potential improvements / features

Roughly in order of usefulness:

1. **`--at INDEX` for add/insert.** Insert a new tag at an exact position rather
   than only appending it. This directly complements the project's ordered-tag
   purpose.
2. **`--move TAG INDEX`.** Reorder an existing tag without requiring callers to
   fetch and rewrite the whole array themselves.
3. **`--jsonl` / `--ndjson`.** Stream one JSON object per result, avoiding the
   memory cost of a giant JSON array.
4. **`--absolute` or richer JSON paths.** Useful with multiple recursive roots
   and for machine consumers.
5. **Paths from stdin / NUL-delimited input.** Helpful for very large file sets
   and unusual filenames, analogous to `find -print0 | xargs -0` workflows.
6. **Optional Spotlight-backed `--find`.** This could restore more
   `jdberry/tag` compatibility without changing the order-preserving core, but
   it should remain clearly separate from direct traversal.
7. **More macOS integration tests.** Especially spaces/newlines/non-ASCII in
   paths and tags, symlinks, directories, hidden files, package directories,
   APFS volumes, removable media, and network volumes.
8. **CI on multiple macOS/Swift versions.** The code is intended to compile on
   Swift 5.5, but the current environment only verifies Swift 5 language mode
   with a newer compiler. Testing with the maintainer's Apple Swift 5.5.2 is
   particularly valuable.
9. **Man page / completion scripts.** Worth adding only after the command-line
   interface settles.

## Deliberately not recommended yet

* Transaction/rollback machinery for multi-file tag edits: too much complexity
  for low-value metadata unless real users demonstrate a need.
* Parallel recursive mutation: concurrency would amplify read-modify-write race
  risks and make deterministic behavior harder to reason about.
* Reimplementing Finder xattrs directly: the Foundation abstraction is much
  cleaner and should remain the primary API unless a concrete limitation is
  found.
