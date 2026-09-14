import Foundation

func usage(code: Int32 = 0) -> Never {
    let text = """
    \(programName) - manipulate macOS Finder tags while preserving tag order

    finder-tags executable: tag
    Usage-compatible with the non-Spotlight parts of jdberry/tag.

    usage:
      \(programName) [-l | --list] [options] [path ...]
      \(programName) -a | --add TAGS [options] path ...
      \(programName) -r | --remove TAGS [options] path ...
      \(programName) -s | --set TAGS [options] path ...
      \(programName) -m | --match TAGS [options] [path ...]
      \(programName) -u | --usage [TAGS] [options] [path ...]
      \(programName) --copy SOURCE DESTINATION [--dry-run]

    TAGS is a comma-separated list. Matching is case-insensitive.
    '*' means any tag for --match/--usage and all tags for --remove.
    An empty TAGS expression matches files with no tags.

    operations:
      -l, --list                 List tags (default)
      -a, --add TAGS             Append new tags, preserving existing order
      -r, --remove TAGS          Remove tags; '*' removes all tags
      -s, --set TAGS             Replace all tags in the specified order
          --copy SRC DST         Replace DST's tags with SRC's ordered tags
      -m, --match TAGS           List traversed files matching all TAGS
      -u, --usage [TAGS]         Count tags on matching traversed files

    output:
      -c, --color                Display known Finder tag colors
      -V, --reverse              Reverse tag display order (does not rewrite)
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
          --json                 Emit structured JSON instead of text

    mutation safety:
          --dry-run              Show intended changes without writing
          --dryrun               Alias for --dry-run

    enumeration:
      -A, --all                  Include hidden files while enumerating
      -e, --enter                Enumerate contents of explicit directories
      -R, -d, --recursive        Recursively enumerate directories

    other:
      -h, --help                 Show this help
      -v, --version              Show version

    Defaults match jdberry/tag where practical: list shows filename+tags;
    match shows filenames only. With no paths, list/match/usage enumerate the
    current directory. Mutating operations require explicit paths.

    Important differences from jdberry/tag:
      * Stored tag order is preserved; tags are never sorted for display.
      * --usage traverses paths directly; it does NOT use Spotlight and does
        not search the whole system. Use -R to recurse.
      * --find and --home/--local/--network are not implemented.
      * With -e/-R, explicit directory arguments are printed once, then their
        descendants are displayed relative to that directory, like jdberry/tag.
      * --copy, --reverse, --json, and --dry-run are additions.

    For --usage, no TAGS means '*'. Because TAGS is optional, prefer
    "--usage='*' PATH", "--usage=Work PATH", or "-uWork PATH" when paths
    are also present. "--usage '*' PATH" remains accepted.
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

private func requireValue(_ option: String, args: [String], index: inout Int) -> String {
    index += 1
    if index >= args.count { fail("\(option) requires an argument") }
    return args[index]
}

private func optionalUsageValue(
    inlineValue: String?,
    args: [String],
    index: inout Int
) -> String {
    if let value = inlineValue { return value }
    let next = index + 1
    if next < args.count && !args[next].hasPrefix("-") {
        index = next
        return args[next]
    }
    return "*"
}

private func applyShortFlag(_ ch: Character, options: inout Options) {
    switch ch {
    case "l": setOperation(.list, options: &options)
    case "c": options.color = true
    case "V": options.reverse = true
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
            options.paths.append(contentsOf: args.dropFirst(i + 1))
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
            case "remove":
                setOperation(.remove(parseTagList(operand())), options: &options)
            case "set":
                setOperation(.set(parseTagList(operand())), options: &options)
            case "match":
                setOperation(.match(parseTagList(operand())), options: &options)
            case "usage":
                let raw = optionalUsageValue(
                    inlineValue: inlineValue, args: args, index: &i
                )
                setOperation(.usage(parseTagList(raw)), options: &options)
            case "copy":
                if inlineValue != nil {
                    fail("--copy does not take '=...'; use --copy SOURCE DESTINATION")
                }
                setOperation(.copy, options: &options)
            case "color": options.color = true
            case "reverse": options.reverse = true
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
            case "json": options.json = true
            case "dry-run", "dryrun": options.dryRun = true
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

                if ch == "a" || ch == "r" || ch == "s" || ch == "m" {
                    let remainder = String(chars.dropFirst(j + 1))
                    let raw = remainder.isEmpty
                        ? requireValue("-\(ch)", args: args, index: &i)
                        : remainder
                    let tags = parseTagList(raw)

                    switch ch {
                    case "a": setOperation(.add(tags), options: &options)
                    case "r": setOperation(.remove(tags), options: &options)
                    case "s": setOperation(.set(tags), options: &options)
                    default: setOperation(.match(tags), options: &options)
                    }
                    break
                }

                if ch == "u" {
                    let remainder = String(chars.dropFirst(j + 1))
                    let raw: String
                    if remainder.isEmpty {
                        raw = optionalUsageValue(inlineValue: nil, args: args, index: &i)
                    } else {
                        raw = remainder
                    }
                    setOperation(.usage(parseTagList(raw)), options: &options)
                    break
                }

                applyShortFlag(ch, options: &options)
                j += 1
            }

            i += 1
            continue
        }

        options.paths.append(arg)
        i += 1
    }

    switch options.operation {
    case .list, .match, .usage:
        break
    case .copy:
        if options.paths.count != 2 {
            fail("--copy requires exactly SOURCE and DESTINATION")
        }
    case .add, .remove, .set:
        if options.paths.isEmpty {
            fail("add/remove/set require at least one explicit path")
        }
    }

    if options.dryRun && !options.isMutating {
        fail("--dry-run is only valid with --add, --remove, --set, or --copy")
    }

    return options
}
