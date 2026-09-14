macOS Finder tag utilities (Swift)

show-tags.swift FILE
    Prints Finder tag names, one per line, in the order returned by
    Foundation's URLResourceKey.tagNamesKey. No output means no tags.

copy-tags.swift SOURCE DESTINATION
    Replaces DESTINATION's complete Finder tag list with SOURCE's list.
    This is destructive: existing destination tags are removed, and if
    SOURCE has no tags, DESTINATION is left with no tags.

Examples:
    ./show-tags.swift ~/Desktop/example.pdf
    ./copy-tags.swift source.pdf destination.pdf

Requires macOS with Swift available (normally via Xcode Command Line Tools
or Xcode). Errors are written to stderr and produce a nonzero exit status.
