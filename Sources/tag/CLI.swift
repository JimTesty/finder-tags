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

    TAGS uses a CSV-like comma-separated grammar. Shell quoting still works as
    usual, and quotes inside TAGS allow literal commas, for example:
      tag --set 'Red,"Project, Alpha","Needs review"' file

    operations:
      -l, --list                 List tags (default)
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
      -c, --color                Display known Finder tag colors on a terminal
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
          --jsonl                Emit one JSON object per line (NDJSON)
          --ndjson               Alias for --jsonl

    path input / enumeration:
          --stdin                Read additional newline-delimited paths on stdin
          --stdin0               Read additional NUL-delimited paths on stdin
          --files-from-stdin     Alias for --stdin
          --files0-from-stdin    Alias for --stdin0
      -A, --all                  Include hidden files while enumerating
      -e, --enter                Enumerate contents of explicit directories
      -R, -d, --recursive        Recursively enumerate directories
          --no-follow-symlinks   Do not resolve/follow symlinked directories
          --follow-symlinks      Restore the default follow behavior

    mutation safety:
          --dry-run              Show intended changes without writing
          --dryrun               Alias for --dry-run

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

private func setOperation(_ operation: Operation, options: inout Options) {
    if options.operationWasSet {
        fail("operation may be specified only once")
    }
    options.operation = operation
    options.operationWasSet = true
}

private func setPosition(_ position: PositionSpec, options: inout Options, option: String) {
    if options.position != nil {
        fail("placement may be specified only once (conflict at \(option))")
    }
    options.position = position
}

private func requireValue(_ option: String, args: [String], index: inout Int) -> String {
    index += 1
    if index >= args.count { fail("\(option) requires an argument") }
    return args[index]
}

private func applyShortFlag(_ ch: Character, options: inout Options) {
    switch ch {
    case "l": setOperation(.list, options: &options)
    case "c": options.color = true
    case "V": options.reverse = true
    case "C": options.caseSensitive = true
    case "n": options.showNamesOverride = true
    case "N": options.showNamesOverride = false
    case "t": options.showTagsOverride = true
    case "T": options.showTagsOverride = false
    case "g": options.oneTagPerLine = true
    case "G": options.oneTagPerLine = false
    case "A": options.includeHidden = true
    case "e": options.enterDirectories = true
    case "R", "d": options.recursive = true
    case "p": options.slashDirectories = true
    case "0": options.nulTerminate = true
    case "h": usage()
    case "v": version()
    default: fail("unknown option: -\(ch)")
    }
}

func parseArguments() -> Options {
    var options = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0

    while i < args.count {
        let arg = args[i]

        if arg == "--" {
            let rest = Array(args.dropFirst(i + 1))
            if !rest.isEmpty { options.pathInputExplicit = true }
            options.paths.append(contentsOf: rest)
            break
        }

        if arg.hasPrefix("--") {
            let parts = arg.dropFirst(2).split(
                separator: "=", maxSplits: 1, omittingEmptySubsequences: false
            )
            let name = String(parts[0])
            let inlineValue = parts.count == 2 ? String(parts[1]) : nil

            func operand() -> String {
                if let value = inlineValue { return value }
                return requireValue("--\(name)", args: args, index: &i)
            }

            switch name {
            case "list":
                if inlineValue != nil { fail("--list does not take an argument") }
                setOperation(.list, options: &options)
            case "add":
                setOperation(.add(parseTagList(operand())), options: &options)
            case "append":
                setOperation(.add(parseTagList(operand())), options: &options)
                setPosition(.last, options: &options, option: "--append")
            case "prepend":
                setOperation(.add(parseTagList(operand())), options: &options)
                setPosition(.first, options: &options, option: "--prepend")
            case "remove":
                setOperation(.remove(parseTagList(operand())), options: &options)
            case "set":
                setOperation(.set(parseTagList(operand())), options: &options)
            case "match":
                setOperation(.match(parseTagList(operand())), options: &options)
            case "usage":
                setOperation(.usage(parseTagList(operand())), options: &options)
            case "find":
                setOperation(.find(parseTagList(operand())), options: &options)
            case "copy":
                if inlineValue != nil {
                    fail("--copy does not take '=...'; use --copy SOURCE DESTINATION")
                }
                setOperation(.copy, options: &options)
            case "move":
                if inlineValue != nil {
                    fail("--move does not take '=...'; use --move TAG POSITION")
                }
                let tag = requireValue("--move", args: args, index: &i)
                var position: PositionSpec? = nil
                if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    position = parsePosition(requireValue("--move", args: args, index: &i))
                }
                setOperation(.move(tag, position), options: &options)
            case "at":
                setPosition(parsePosition(operand()), options: &options, option: "--at")
            case "before":
                setPosition(.before(operand()), options: &options, option: "--before")
            case "after":
                setPosition(.after(operand()), options: &options, option: "--after")
            case "sorted-tags", "sort-tags": options.sortedTags = true
            case "color": options.color = true
            case "reverse": options.reverse = true
            case "case-sensitive": options.caseSensitive = true
            case "filename", "name": options.showNamesOverride = true
            case "no-filename", "no-name": options.showNamesOverride = false
            case "tags": options.showTagsOverride = true
            case "no-tags": options.showTagsOverride = false
            case "one-per-line", "garrulous": options.oneTagPerLine = true
            case "comma-separated", "no-garrulous": options.oneTagPerLine = false
            case "all": options.includeHidden = true
            case "enter": options.enterDirectories = true
            case "recursive", "descend": options.recursive = true
            case "slash": options.slashDirectories = true
            case "null", "nul": options.nulTerminate = true
            case "absolute": options.absolutePaths = true
            case "jsonl", "ndjson": options.jsonLines = true
            case "dry-run", "dryrun": options.dryRun = true
            case "no-follow-symlinks": options.followSymlinks = false
            case "follow-symlinks": options.followSymlinks = true
            case "stdin", "files-from-stdin":
                if options.stdinPathMode != nil { fail("stdin path mode may be specified only once") }
                options.stdinPathMode = .lines
                options.pathInputExplicit = true
            case "stdin0", "files0-from-stdin":
                if options.stdinPathMode != nil { fail("stdin path mode may be specified only once") }
                options.stdinPathMode = .nul
                options.pathInputExplicit = true
            case "help": usage()
            case "version": version()
            default: fail("unknown option: --\(name)")
            }

            i += 1
            continue
        }

        if arg.hasPrefix("-") && arg != "-" {
            let chars = Array(arg.dropFirst())
            var j = 0

            while j < chars.count {
                let ch = chars[j]

                if ch == "a" || ch == "r" || ch == "s" || ch == "m" || ch == "u" || ch == "f" {
                    let remainder = String(chars.dropFirst(j + 1))
                    let raw = remainder.isEmpty
                        ? requireValue("-\(ch)", args: args, index: &i)
                        : remainder
                    let tags = parseTagList(raw)

                    switch ch {
                    case "a": setOperation(.add(tags), options: &options)
                    case "r": setOperation(.remove(tags), options: &options)
                    case "s": setOperation(.set(tags), options: &options)
                    case "m": setOperation(.match(tags), options: &options)
                    case "u": setOperation(.usage(tags), options: &options)
                    default: setOperation(.find(tags), options: &options)
                    }
                    break
                }

                applyShortFlag(ch, options: &options)
                j += 1
            }

            i += 1
            continue
        }

        options.paths.append(arg)
        options.pathInputExplicit = true
        i += 1
    }

    if let mode = options.stdinPathMode {
        options.paths.append(contentsOf: readPathsFromStdin(mode))
    }

    switch options.operation {
    case .list, .match, .usage, .find:
        break
    case .copy:
        if options.paths.count != 2 {
            fail("--copy requires exactly SOURCE and DESTINATION")
        }
    case .add, .remove, .set, .move:
        if options.paths.isEmpty {
            fail("this operation requires at least one explicit path")
        }
    }

    switch options.operation {
    case .add:
        break
    case .move(_, let explicitPosition):
        if explicitPosition != nil && options.position != nil {
            fail("--move POSITION cannot be combined with --at/--before/--after")
        }
        if explicitPosition == nil && options.position == nil {
            fail("--move requires POSITION or --at/--before/--after")
        }
    default:
        if options.position != nil {
            fail("--at/--before/--after are only valid with --add or --move")
        }
    }

    if options.dryRun && !options.isMutating {
        fail("--dry-run is only valid with --add, --remove, --set, --move, or --copy")
    }

    return options
}
