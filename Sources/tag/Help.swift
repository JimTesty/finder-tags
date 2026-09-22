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
      \(programName) --filter TAGS [options] [path ...]
      \(programName) -u | --usage TAGS [options] [path ...]
      \(programName) -f | --find TAGS [options] [path ...]
      \(programName) --move TAG POSITION [options] path ...
      \(programName) --move TAG --before|--after TAG [options] path ...
      \(programName) --copy SOURCE DESTINATION [--dry-run]
      \(programName) --export [options] [ROOT]
      \(programName) --restore ARCHIVE [--root DEST] [--dry-run]
      \(programName) --convert ARCHIVE [options]

    Mutation TAGS uses a CSV-like comma-separated grammar. Shell quoting still
    works as usual, and quotes inside TAGS allow literal commas, for example:
      tag --set 'Red,"Project, Alpha","Needs review"' file
    CR, LF, and NUL are not valid inside tag names.

    operations:
      -l, --list                 List tags (default)
          --export               Export ordered tags for one root
          --restore ARCHIVE      Restore an archive (use '-' for stdin)
          --convert ARCHIVE      Convert JSONL archive to human-readable text
      -a, --add TAGS             Add/re-case tags, preserving existing order
          --append TAGS          Alias for --add (insert new tags last)
          --prepend TAGS         Add new tags at first/left/bottom
      -r, --remove TAGS          Remove matching tags; '*' removes all tags
      -s, --set TAGS             Replace all tags in the specified order
          --copy SRC DST         Replace DST's tags with SRC's ordered tags
      -m, --match TAGS           List traversed files matching TAGS
          --filter TAGS          Match tags with list-style output
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
      -V, --reverse              Reverse display order; export ignores it
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
          --space-indent         Use two spaces instead of tab before tags
          --align-tags N         Pad file paths to N display columns, then use
                                 two spaces before tags; implies --space-indent
          --garrulous            Alias for --one-per-line
          --no-garrulous         Alias for --comma-separated
      -p, --slash                Append '/' to directories and '@' to symlinks
          --print-symlinks       Show each symlink's stored destination (text)
      -0, --null                 Terminate text records with NUL
          --nul                  Backward-compatible alias for --null
          --absolute             Display absolute logical paths
          --file-info            Include file size and mtime in list/match/find/export
          --no-file-info         Omit file size and mtime from export output
          --jsonl                Emit one JSON object per line (NDJSON)
          --ndjson               Alias for --jsonl
          --tagged-only          Process only items with at least one tag

    path input / enumeration:
          --stdin                Read additional newline-delimited paths on stdin
          --stdin0               Read additional NUL-delimited paths on stdin
          --files-from-stdin     Alias for --stdin
          --files0-from-stdin    Alias for --stdin0
      -A, --all                  Include hidden files while enumerating (export
                                 includes them by default)
      -e, --enter                Enumerate contents of explicit directories
      -R, -d, --recursive        Recursively enumerate directories
      -L, --follow-symlinks      Resolve/follow symlinks and symlinked directories
          --no-follow-symlinks   Do not resolve/follow symlinks (default)
          --exclude PATH         Skip matching paths/subtrees during traversal

    mutation safety:
          --dry-run              Show intended changes without writing; restore
                                 reports the same change count
          --dryrun               Alias for --dry-run
          --backup PATH          Write a per-file undo archive (default: temp)
          --no-backup            Disable the default undo archive
          --sync-backup          Sync each undo record before mutation

    other:
      -h, --help                 Show this help
      -v, --verbose              Show informational messages on stderr
          --version              Show version

    TAG matching is case-insensitive by default, but stored case is preserved.
    Case-distinct stored tags are not merged. For example, adding Orange to an
    existing red,orange,yellow re-cases the unique match in place to
    red,Orange,yellow. Use --case-sensitive to append a distinct Orange instead.

    Query TAGS for --match, --filter, --usage, and --find use comma for AND,
    pipe for OR, and a leading '-' for NOT. Precedence is comma < pipe < '-';
    parentheses override it. For example, 'Project,Red|Orange' means Project
    and either Red or Orange. Escape a pipe in an unquoted tag as '\\|'; quoted
    tags may contain operators literally. '*' requires at least one tag and
    '-*' requires no tags. An empty TAGS expression matches files with no tags.
    --usage requires TAGS.

    Placement names map to Finder's visual stack: first/left/bottom = index 0,
    last/right/top = the end, because Finder draws the last/rightmost color on
    top. --before/--after use the same case-matching rules as other operations.

    --sorted-tags is opt-in. Read-only commands only sort their output; they do
    not rewrite metadata. Mutating commands sort the final stored array after
    applying the requested edit. Default behavior always preserves tag order.

    Symbolic links are not followed by default. --follow-symlinks (or -L)
    resolves symlinks, follows symlinked directories, and records structural
    target information in archive output, but never embeds target tags inside
    a symlink record. --print-symlinks displays the literal stored link
    destination without changing traversal; dangling targets are marked NOT
    FOUND.

    Export archives are always JSONL, include untagged items by default, and
    preserve stored tag order. --reverse is ignored during export. --file-info
    is enabled by default for export and can be disabled with --no-file-info.
    --tagged-only is an opt-in filter. --exclude can be repeated; a single
    component such as .git matches at any depth, while a slash-containing path
    is relative to the traversal root. Use --convert ARCHIVE for human-readable
    output; its --reverse, --slash, --space-indent, --align-tags, and --color options affect
    only that display. Restore follows symlink targets only with the same
    --follow-symlinks setting recorded in the archive. --color accepts
    auto/yes, always/force, and never/no/none aliases; JSONL is never colored.

    Defaults match jdberry/tag where practical: list/filter show filename+tags;
    match/find show filenames only. With no paths, list/match/filter/usage
    enumerate the current directory; find uses Spotlight's default search scope.
    Mutating operations require explicit paths.

    Important differences from jdberry/tag:
      * Stored tag order is preserved by default. --sorted-tags opts into sorted
        display/results and sorted mutation output.
      * --usage traverses paths directly; it does NOT use Spotlight.
      * --usage requires TAGS instead of making it optional.
      * --home/--local/--network are not implemented for --find.
      * Quoted TAGS can contain commas; jdberry/tag's grammar cannot.

    Use -- before a path beginning with '-'.
    """

    if code == 0 { print(text) } else { eprint(text) }
    exit(code)
}

func version() -> Never {
    print("\(programName) \(programVersion)")
    exit(0)
}
