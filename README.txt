macOS Finder tag utilities (Swift)

show-tags.swift
---------------
A small Foundation-based CLI inspired by jdberry/tag, deliberately preserving
the order returned/stored by URLResourceKey.tagNamesKey.

Common examples:

    ./show-tags.swift
        List files in the current directory and their tags.

    ./show-tags.swift file1 file2
        List tags on explicit files.

    ./show-tags.swift -c file
        Color known Finder tags with ANSI background colors.

    ./show-tags.swift -a 'Work,Important' file
        Add tags. Existing tag order is preserved; new tags are appended in
        command-line order.

    ./show-tags.swift -r 'Work,Old' file
        Remove tags case-insensitively while preserving remaining tag order.

    ./show-tags.swift -r '*' file
        Remove all tags.

    ./show-tags.swift -s 'First,Second,Third' file
        Replace all tags in exactly the specified order.

    ./show-tags.swift -R directory
        List the directory itself and then recursively list its contents.

    ./show-tags.swift -e directory
        List the directory itself and its immediate contents.

Run ./show-tags.swift --help for all options.

Ordering
--------
Unlike jdberry/tag 0.10.0, this script never sorts tags for display and never
turns them into an unordered set while modifying them:

  * list:   prints Foundation's tagNames array as returned
  * add:    preserves existing order and appends new unique tags
  * remove: filters the existing array in place
  * set:    writes the requested array in command-line order

Duplicate tag names are treated case-insensitively. For --set and --add, the
first spelling wins.

Colors
------
-c / --color follows jdberry/tag's approach: it best-effort reads Finder's
private synced-preferences tag-color table and emits approximate ANSI
background colors. This is intentionally optional. Tag reading/writing itself
uses the public Foundation URL resource-value API and does not parse Finder
xattrs or Spotlight metadata.

copy-tags.swift
---------------
    ./copy-tags.swift SOURCE DESTINATION

Destructively replaces DESTINATION's complete tag list with SOURCE's list.
The array order is copied unchanged. If SOURCE has no tags, DESTINATION ends
with no tags.

Requirements
------------
macOS with Swift available, normally from Xcode Command Line Tools or Xcode.

Attribution
-----------
The CLI shape and optional Finder-tag color lookup are inspired by jdberry/tag
(MIT licensed). Its license is included as jdberry-tag-LICENSE.txt.
