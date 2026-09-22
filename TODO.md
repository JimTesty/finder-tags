# Future work

These are intentionally deferred until the JSONL archive and restore path have
more real-world use. Recursive traversal now sorts each directory's children
by literal filename, so unchanged exports have stable item order.

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
