import Foundation

func usage(code: Int32 = 0, detailed: Bool = false) -> Never {
    Diagnostics.finishParsing()
    let name = escapedDisplayText(programName)
    let text = detailed ? detailedHelp(name: name) : briefHelp(name: name)
    let stream = code == 0 ? FileHandle.standardOutput : FileHandle.standardError
    stream.write(Data((text + "\n").utf8))
    exit(code)
}

private func briefHelp(name: String) -> String {
    """
    \(name) - manage macOS Finder tags; preserve tag order
    Compatible with jdberry/tag where practical.

    Usage: \(name) [operation] [options] [path ...]

    operations:
      -l, --list                 List tags (default)
      -a, --add TAGS             Add tags
      -r, --remove TAGS          Remove tags; '*' removes all
      -s, --set TAGS             Replace all tags
          --fix                  Repair stored tags
          --copy SRC DST         Copy tags
          --move TAG POSITION    Reorder a tag
          --filter TAGS          List matching files with their tags
          --export [ROOT]        Export a JSONL archive
          --restore ARCHIVE      Restore tags from an archive

    options:
      -e, --enter                Enter listed directories
      -R, --recursive            Enter directories recursively
      -A, --all                  Include hidden files and directories
      -c, --color[=yes/no]       Show tag colors
          --file-info            Show file size and modification time
          --tagged-only          Process only files with tags
          --sorted-tags          Sort displayed or written tags
          --exclude PATH         Skip paths during traversal
          --dry-run              Preview changes
          --backup               Enable a temporary undo archive
      -v, --verbose              Show informational messages
      -h, --help                 Show brief help
          --version              Show version

    TAGS are comma-separated; matching ignores case. Listing defaults to cwd.
    Backup defaults on with -R, -e, stdin paths, or restore; otherwise off.
    Many options have --no-... negations; detailed help lists them.
    For detailed help: \(name) -hh (or \(name) -h -v)
    """
}

private func detailedHelp(name: String) -> String {
    """
    \(name) - manipulate macOS Finder tags while preserving tag order

    finder-tags executable: tag
    Usage-compatible with jdberry/tag where noted.

    usage:
      \(name) [-l | --list] [options] [path ...]
      \(name) -a | --add TAGS [placement] [options] path ...
      \(name) -r | --remove TAGS [options] path ...
      \(name) -s | --set TAGS [options] path ...
      \(name) --fix [options] path ...
      \(name) -m | --match TAGS [options] [path ...]
      \(name) --filter TAGS [options] [path ...]
      \(name) -u | --usage TAGS [options] [path ...]
      \(name) -f | --find TAGS [options] [path ...]
      \(name) --move TAG POSITION [options] path ...
      \(name) --move TAG --before|--after TAG [options] path ...
      \(name) --copy SOURCE DESTINATION [--dry-run]
      \(name) --export [options] [ROOT]
      \(name) --restore ARCHIVE [--root DEST] [--dry-run]
      \(name) --convert ARCHIVE [options]

    Mutation TAGS uses a CSV-like comma-separated grammar. Shell quoting still
    works as usual, and quotes inside TAGS allow literal commas, for example:
      tag --set 'Red,"Project, Alpha","Needs review"' file
    CR, LF, and NUL in tag names are replaced with �, with warnings.

    operations:
      -l, --list                 List tags (default)
          --export               Export ordered tags for one root
          --restore ARCHIVE      Restore an archive (use '-' for stdin)
          --root DEST            Relocate the restore destination
          --convert ARCHIVE      Convert JSONL archive to human-readable text
      -a, --add TAGS             Add/re-case tags, preserving existing order
          --append TAGS          Alias for --add (insert new tags last)
          --prepend TAGS         Add new tags at first/left/bottom
      -r, --remove TAGS          Remove matching tags; '*' removes all tags
          --del, --delete TAGS    Aliases for --remove
      -s, --set TAGS             Replace all tags in the specified order
          --replace TAGS         Alias for --set
          --fix                  Repair invalid tag names
          --repair               Alias for --fix
          --copy SRC DST         Copy SRC's ordered tag names and colors to DST
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
          --sort-tags            Alias for --sorted-tags
      -V, --reverse              Reverse display order; export ignores it
      -C, --case-sensitive       Make tag matching case-sensitive
                                 (default matching is case-insensitive)

    output:
      -c, --color[=yes/no]       Display known Finder tag colors when appropriate
          --no-color             Alias for --color=off
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
          --compact-tags         Mimic Finder's mini color-circles with reversed
                                 first-character tags; implies --color and --reverse
          --garrulous            Alias for --one-per-line
          --no-garrulous         Alias for --comma-separated
      -p, --slash                Append '/' to directories and '@' to symlinks
          --print-symlinks       Show each symlink's stored destination (text)
      -0, --null                 Terminate with NUL; leave names unescaped
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
      -A, --all                  Include hidden files and directories (export
                                 includes them by default)
          --dot-files            Alias for --all
          --include-hidden       Alias for --all
      -e, --enter                Enumerate contents of explicit directories
      -R, -d, --recursive        Recursively enumerate directories
          --descend              Alias for --recursive
          --no-sort-files        Use filesystem/Spotlight order instead of sorting
          --resolve-symlinks0    Resolve symlinks supplied as path operands, like find -H
      -L, --follow-symlinks      Resolve/follow symlinks and symlinked directories
          --no-follow-symlinks   Do not follow symlinks during traversal (default)
          --exclude PATH         Skip matching paths/subtrees during traversal

    mutation safety:
          --dry-run              Show intended changes without writing; restore
                                 reports the same change count
          --dryrun               Alias for --dry-run
          --backup               Enable a temporary per-file undo archive
          --backup-path PATH     Enable a per-file undo archive at PATH
          --no-backup            Disable the undo archive
          --sync-backup          Sync each undo record before mutation

    Backup defaults to off for explicit command-line paths. It defaults to on
    with -R/--recursive, -e/--enter, stdin path input, or --restore, using a
    temporary undo archive for the whole operation. -R enables this default
    even when all supplied paths are files. Explicit backup options override it;
    the last one wins.

    other:
      -h, --help                 Show brief help; repeat -h or add -v for details
      -hh                       Show this detailed help (also -h -v)
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

    Filesystem enumeration sorts each directory's children by case-sensitive,
    locale-independent filename order (file10 before file2). Recursion is
    depth-first, processing each directory before its contents. --no-sort-files
    skips filename sorting, including during export; filesystem order is unspecified.
    --sorted-tags and --reverse affect tag order only.
    Explicit paths retain argument order; the shell expands and orders globs.
    Stdin paths follow command-line paths in input order. Spotlight --find sorts
    results by display name in ascending order unless --no-sort-files is used;
    unsorted Spotlight result order is unspecified.

    Symbolic links are not followed by default. --resolve-symlinks0 resolves
    symlinks supplied as path operands when their targets exist, like find -H;
    it does not follow symlinks encountered during traversal. --follow-symlinks
    (or -L) resolves symlinks, follows symlinked directories, and records
    structural target information in archive output, but never embeds target
    tags inside a symlink record. --print-symlinks displays the literal stored
    link destination without changing traversal; broken links are marked
    [BROKEN SYMLINK] on the filename (except in NUL-separated output).

    Export archives are always JSONL, include untagged items by default, and
    preserve stored tag order and color numbers. --reverse is ignored during export. --file-info
    is enabled by default for export and can be disabled with --no-file-info.
    --tagged-only is an opt-in filter. --exclude can be repeated; a single
    component such as .git matches at any depth, while a slash-containing path
    is relative to the traversal root. Use --convert ARCHIVE for human-readable
    output; its --reverse, --slash, --space-indent, --align-tags, and --color options affect
    only that display. Restore follows symlink targets only with the same
    --follow-symlinks setting recorded in the archive.
    --color settings: auto = terminal detection; yes/on/always/force = always;
    no/off/never/none = disabled. Bare --color and -c use auto.
    JSONL is never colored.

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

    Normal text and diagnostics escape control characters and backslashes.
    JSON values and NUL-delimited stdout preserve the original names.
    Use -- before a path beginning with '-'.
    """

}

func version() -> Never {
    Diagnostics.finishParsing()
    print("\(escapedDisplayText(programName)) \(programVersion)")
    exit(0)
}
