# Future work

## Help-page cleanup

* Simplify `tag -h` / `--help`: reduce density and repetition, keep command
  descriptions short and action-focused, and leave detailed behavior in the
  manual or README. Defer the broader help-page redesign until a later pass.

## Imperfect-data recovery audit (2026-10-18)

Tag entries are now recovered individually, with warnings. The remaining
stopping points and silent fallbacks need these policies or larger changes:

* **Unreadable tag payloads** (`FileTagMetadata.read/decode`,
  `TagStore.readTags`): invalid plists, non-array roots, and filesystem read
  errors still fail that file; traversal continues with others. There is no
  trustworthy array to recover. Consider extending `--fix` with an explicit
  recovery mode that saves raw bytes before trying Foundation's name-only view. Never infer
  "no tags" from a failed read before an edit.
* **Exact undo of malformed metadata** (`UndoWriter`, `TagChange`): undo saves
  the recovered tags, not discarded empty entries or the original illegal
  characters, non-string values, and malformed suffixes. Exact recovery needs
  an additional raw-xattr preimage in the journal and a corresponding restore
  path. Reads and dry runs currently leave the original bytes alone.
* **Archive fields beyond tag names** (`ArchiveReader`, `ArchiveFormat`): bad
  size/mtime, informational header palette/exclusions, color types/counts,
  item kinds, symlink fields, duplicate export paths, unsupported records,
  invalid UTF-8/JSON, header/root/order/version errors, and missing export
  summaries can still reject the whole document. Consider omitting bad
  informational fields and recovering independently valid records with
  diagnostics. Do not guess color alignment, restore destinations, or a new
  format's meaning. Coordinate this with the completion/journal work below.
* **Restore preflight** (`RestoreEngine.run/destinationURL`): one unsafe path
  or parent-symlink inspection failure prevents all writes. A future partial
  recovery policy could reject that item and retain safe items; path escape
  checks and follow-symlink mode agreement must remain mandatory. Once
  preflight passes, individual missing/type-changed/unreadable items already
  report errors and allow the rest to continue.
* **Ambiguous or unavailable edit targets** (`TagStore.addChange`, movement
  and insertion matching): one ambiguous requested addition or missing anchor
  can stop the file's edit. Consider independent additions when their placement
  remains clear. Exact duplicate names are now renamed during recovery;
  case-insensitive matches among case-distinct names can still be ambiguous.
  Invalid indexes are not clamped.
* **Optional platform writes** (`TagStore.write`): failure to assign an initial
  color or synchronize the legacy Finder label still fails the edit, possibly
  after partial platform writes. Determine when preserving the primary tag
  array can proceed with a warning. Undo-write failures and read-back
  verification mismatches must remain errors.
* **File-type fallbacks** (`Output.itemKind`, `symbolicLinkInfo`,
  `isSymbolicLink`): some `try?` failures still become "file", "not a symlink",
  or "not a directory". Introduce explicit unavailable results and warnings
  where they affect output; never bypass restore's checked parent inspection.
  Directory enumeration/type failures already allow sibling work to continue
  but cannot recover inaccessible children. Spotlight startup/platform errors
  still stop that search; malformed individual results now warn and continue.
* **Path input encoding** (`readPathsFromStdin`): invalid UTF-8 is currently
  replaced silently before lookup. Decide between warning/skipping each bad
  path and supporting byte-preserving filesystem paths; avoid silently acting
  on a different name. Truncated or ambiguous tag/query syntax and missing
  required operands remain command errors rather than partial instructions.
* **Output I/O** (`Output`, archive/undo writers): older nonthrowing FileHandle
  write/close APIs can terminate or hide underlying write failures. Move to
  throwing APIs with explicit diagnostics and a policy for stopping after a
  broken output stream or failed journal write.

## Deferred audit work (2026-10-15)

* Full summary accounting and interrupted undo-journal recovery. Export archives
  now require their final summary, but counts and exporter error totals are not
  validated. Broader reader/writer recovery rules have low current value while
  export/restore is unused; no legacy-format migration work is planned.
* Eliminate concurrent path-replacement races with descriptor-based traversal
  and writes. Restore checks parent symlinks before writing and again per item,
  but locking down identity through Foundation's label/initial-color writes
  needs a larger I/O design. Defer that complexity for this local tool.

## Other future work

These are intentionally deferred until the JSONL archive and restore path have
more real-world use. Recursive traversal now sorts each directory's children
by literal filename by default, so unchanged exports have stable item order
unless --no-sort-files is used.

* Export/restore tags stored on dangling symlinks. Listings read the link's own
  tags, but archives currently omit unavailable referent tags while preserving
  the link's size and timestamp. The archive needs to distinguish tags on the
  link from tags on its target before restore can safely support both.
* Add a restore comparison mode that lists and counts existing filesystem items
  omitted from the archive. It will need traversal ordering compatible with the
  archive before it can report that set cleanly; this is useful but not urgent
  now that users can diff stable archives.
* Add a command that uses archived `size` and `mtime` fields to list items that
  changed since export. These fields remain informational during restore.
* Design managed compressed undo journals. Export already works with ordinary
  shell pipelines, but an undo journal is written by the program immediately
  before each mutation, so compression, flushing, and crash atomicity need one
  coherent design; undo durability is not a current priority.
* Add symlink-focused stress tests and decide how to present repeated logical
  subtrees reached through `-L`. Dedicated hard-link handling is not planned
  yet because repeated tag writes are safe.
* Consider additional `--exclude` pattern semantics and edge-case tests if the
  simple component/prefix form proves insufficient.
* Consider making the query expression an independent `--filter` pre-filter
  for other filesystem operations and archive records during restore. This
  needs explicit rules for operation composition, `--tagged-only`, archive
  summaries, and dry runs before implementation.
* Broaden macOS/filesystem compatibility testing and add CI when the public
  interface has seen more real-world use. `jdberry/tag` itself does not follow
  symlinks and has no `-L` equivalent, so compatibility work should stay focused
  on shared behavior.
