# Future work

These are intentionally deferred until the JSONL archive and restore path have
more real-world use:

* Add a restore comparison mode that lists and counts existing filesystem items
  omitted from the archive. It will need traversal ordering compatible with the
  archive before it can report that set cleanly.
* Add a command that uses archived `size` and `mtime` fields to list items that
  changed since export. These fields remain informational during restore.
* Design managed compressed undo journals. Export already works with ordinary
  shell pipelines, but an undo journal is written by the program immediately
  before each mutation, so compression, flushing, and crash atomicity need one
  coherent design.
* Consider an explicit identity/deduplication report for hard links and
  repeated logical subtrees reached through `-L`.
