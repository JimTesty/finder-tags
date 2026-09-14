import Foundation

func usage(code: Int32 = 0) -> Never {
    let text = """
    \(programName) - manipulate macOS Finder tags while preserving tag order

    finder-tags executable: tag
    Usage-compatible with jdberry/tag where noted.

    usage:
      \(programName) [-l | --list] [options] [path ...]
      \(programName) -a | --add TAGS [placement] [options] path ...
      \(programName) -r | --remove TAGS [options] path ...
      \(programName) -s | --set TAGS [options] path ...
      \(programName) -m | --match TAGS [options] [path ...]
      \(programName) -u | --usage TAGS [options] [path ...]
      \(programName) -f | --find TAGS [options] [path ...]
      \(programName) --move TAG POSITION [options] path ...
      \(programName) --move TAG --before|--after TAG [options] path ...
      \(programName) --copy SOURCE DESTINATION [--dry-run]
      \(programName) --export [options] [ROOT]
      \(programName) --restore ARCHIVE [--root DEST] [--dry-run]

    TAGS uses a CSV-like comma-separated grammar. Shell quoting still works as
    usual, and quotes inside TAGS allow literal commas, for example:
      tag --set 'Red,"Project, Alpha","Needs review"' file
    CR, LF, and NUL are not valid inside tag names.

    operations:
      -l, --list                 List tags (default)
          --export               Export ordered tags for one root
          --restore ARCHIVE      Restore an archive (use '-' for stdin)
      -a, --add TAGS             Add/re-case tags, preserving existing order
          --append TAGS          Alias for --add (insert new tags last)
          --prepend TAGS         Add new tags at first/left/bottom
      -r, --remove TAGS          Remove matching tags; '*' removes all tags
      -s, --set TAGS             Replace all tags in the specified order
          --copy SRC DST         Replace DST's tags with SRC's ordered tags
      -m, --match TAGS           List traversed files matching all TAGS
      -u, --usage TAGS           Count tags on traversed files matching TAGS
      -f, --find TAGS            Spotlight search for files matching TAGS
          --move TAG POSITION    Move one existing tag to POSITION

    ordering/editing:
          --at POSITION          Placement for --add/--move; zero-based index or
                                first/left/bottom, last/right/top
          --before TAG           Place added/moved tag(s) before TAG
          --after TAG            Place added/moved tag(s) after TAG
          --sorted-tags          Sort displayed tags; mutating operations also
                                store their resulting tag arrays sorted
      -V, --reverse              Reverse display order only; do not rewrite
      -C, --case-sensitive       Make tag matching case-sensitive
                                (default matching is case-insensitive)

    output:
      -c, --color                Display known Finder tag colors when appropriate
      -n, --filename             Show filenames
      -N, --no-filename          Hide filenames
          --name/--no-name       Backward-compatible aliases
      -t, --tags                 Show tags
      -T, --no-tags              Hide tags
      -g, --one-per-line         Display one tag per line
      -G, --comma-separated      Display comma-separated tags (default)
          --garrulous            Alias for --one-per-line
          --no-garrulous         Alias for --comma-separated
      -p, --slash                Append '/' to directory names
      -0, --null                 Terminate text records with NUL
          --nul                  Backward-compatible alias for --null
          --absolute             Display absolute logical paths
          --file-info            Include file size and mtime in list/export output
          --jsonl                Emit one JSON object per line (NDJSON)
          --ndjson               Alias for --jsonl
          --tagged-only          List/export only items with at least one tag

    path input / enumeration:
          --stdin                Read additional newline-delimited paths on stdin
          --stdin0               Read additional NUL-delimited paths on stdin
          --files-from-stdin     Alias for --stdin
          --files0-from-stdin    Alias for --stdin0
      -A, --all                  Include hidden files while enumerating (export
                                includes them by default)
      -e, --enter                Enumerate contents of explicit directories
      -R, -d, --recursive        Recursively enumerate directories
          --no-follow-symlinks   Do not resolve/follow symlinked directories
          --follow-symlinks      Restore the default follow behavior

    mutation safety:
          --dry-run              Show intended changes without writing; restore
                                reports the same change count
          --dryrun               Alias for --dry-run
          --backup PATH          Write a per-file undo archive (default: temp)
          --no-backup             Disable the default undo archive
          --sync-backup           Sync each undo record before mutation

    other:
      -h, --help                 Show this help
      -v, --version              Show version

    TAG matching is case-insensitive by default, but stored case is preserved.
    Case-distinct stored tags are not merged. For example, adding Orange to an
    existing red,orange,yellow re-cases the unique match in place to
    red,Orange,yellow. Use --case-sensitive to append a distinct Orange instead.

    '*' means any tag for --match/--usage/--find and all tags for --remove. An
    empty TAGS expression matches files with no tags. --usage requires TAGS.

    Placement names map to Finder's visual stack: first/left/bottom = index 0,
    last/right/top = the end, because Finder draws the last/rightmost color on
    top. --before/--after use the same case-matching rules as other operations.

    --sorted-tags is opt-in. Read-only commands only sort their output; they do
    not rewrite metadata. Mutating commands sort the final stored array after
    applying the requested edit. Default behavior always preserves tag order.

    Symbolic links are followed by default. --no-follow-symlinks prevents
    recursive traversal through symlinked directories and avoids explicitly
    resolving symlink paths before Foundation tag I/O.

    Export archives are tagged-only, root-relative, and preserve stored tag
    order. Plaintext archives are suitable for reading and restore; --jsonl is
    the streaming machine-readable form. Restore follows current symlink
    targets and warns when they differ from the archived target. A tagged-only
    restore changes listed items only; it does not clear tags from unlisted
    items. --color accepts auto/yes, always/force, and never/no/none aliases;
    JSONL is never colored.

    Defaults match jdberry/tag where practical: list shows filename+tags;
    match/find show filenames only. With no paths, list/match/usage enumerate the
    current directory; find uses Spotlight's default search scope. Mutating
    operations require explicit paths.

    Important differences from jdberry/tag:
      * Stored tag order is preserved by default. --sorted-tags opts into sorted
        display/results and sorted mutation output.
      * --usage traverses paths directly; it does NOT use Spotlight.
      * --usage requires TAGS instead of making it optional.
      * --home/--local/--network are not implemented for --find.
      * --copy, --move, placement controls, --reverse, --case-sensitive,
        --sorted-tags, --absolute, stdin path input, --jsonl, and --dry-run are
        additions.
      * Quoted TAGS can contain commas; jdberry/tag's grammar cannot.
      * Symlinked targets/directories are followed intentionally by default.

    Use -- before a path beginning with '-'.
    """

    if code == 0 { print(text) } else { eprint(text) }
    exit(code)
}

func version() -> Never {
    print("\(programName) \(programVersion)")
    exit(0)
}
