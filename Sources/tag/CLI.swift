import Foundation

func usage(code: Int32 = 0) -> Never {
    let text = """
    \(programName) - manipulate macOS Finder tags while preserving tag order

    usage:
      \(programName) [-l | --list] [options] [path ...]
      \(programName) -a | --add TAGS [options] path ...
      \(programName) -r | --remove TAGS [options] path ...
      \(programName) -s | --set TAGS [options] path ...
      \(programName) --copy SOURCE DESTINATION

    TAGS is a comma-separated list. Matching is case-insensitive.

    operations:
      -l, --list             List tags (default)
      -a, --add TAGS         Append new tags, preserving existing order
      -r, --remove TAGS      Remove tags; '*' removes all tags
      -s, --set TAGS         Replace all tags in the specified order
          --copy SRC DST     Replace DST's tags with SRC's tags

    output (list):
      -c, --color            Display known Finder tag colors
      -V, --reverse          Display tags in reverse stored order
      -n, --name             Show filenames (default)
      -N, --no-name          Hide filenames
      -t, --tags             Show tags (default)
      -T, --no-tags          Hide tags
      -g, --garrulous        Display one tag per line
      -G, --no-garrulous     Display comma-separated tags (default)
      -p, --slash            Append '/' to directory names
      -0, --nul              Terminate output records with NUL

    enumeration (list/add/remove/set):
      -A, --all              Include hidden files while enumerating
      -e, --enter            Enumerate contents of explicit directories
      -R, -d, --recursive    Recursively enumerate directories

    other:
      -h, --help             Show this help
      -v, --version          Show version

    With no paths, list enumerates the current directory. Mutating operations
    require explicit paths. Use -- before paths beginning with '-'.

    Ordering:
      list    displays the stored Foundation tag array unchanged, unless -V
      add     preserves existing order and appends new tags in argument order
      remove  preserves the relative order of tags that remain
      set     writes tags in argument order
      copy    writes the source tag array to the destination unchanged
    """

    if code == 0 { print(text) } else { eprint(text) }
    exit(code)
}

func version() -> Never {
    print("\(programName) 3.0")
    exit(0)
}

private func setOperation(_ operation: Operation, options: inout Options) {
    guard !options.operationWasSet else {
        fail("operation may be specified only once")
    }
    options.operation = operation
    options.operationWasSet = true
}

private func requireValue(_ option: String, args: [String], index: inout Int) -> String {
    index += 1
    guard index < args.count else { fail("\(option) requires an argument") }
    return args[index]
}

private func applyShortFlag(_ ch: Character, options: inout Options) {
    switch ch {
    case "l": setOperation(.list, options: &options)
    case "c": options.color = true
    case "V": options.reverse = true
    case "n": options.showNames = true
    case "N": options.showNames = false
    case "t": options.showTags = true
    case "T": options.showTags = false
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
                if let inlineValue = inlineValue { return inlineValue }
                return requireValue("--\(name)", args: args, index: &i)
            }

            switch name {
            case "list":
                guard inlineValue == nil else { fail("--list does not take an argument") }
                setOperation(.list, options: &options)
            case "add":
                setOperation(.add(parseTagList(operand())), options: &options)
            case "remove":
                setOperation(.remove(parseTagList(operand())), options: &options)
            case "set":
                setOperation(.set(parseTagList(operand())), options: &options)
            case "copy":
                guard inlineValue == nil else { fail("--copy does not take '=...'; use --copy SOURCE DESTINATION") }
                setOperation(.copy, options: &options)
            case "color": options.color = true
            case "reverse": options.reverse = true
            case "name": options.showNames = true
            case "no-name": options.showNames = false
            case "tags": options.showTags = true
            case "no-tags": options.showTags = false
            case "garrulous": options.oneTagPerLine = true
            case "no-garrulous": options.oneTagPerLine = false
            case "all": options.includeHidden = true
            case "enter": options.enterDirectories = true
            case "recursive", "descend": options.recursive = true
            case "slash": options.slashDirectories = true
            case "nul": options.nulTerminate = true
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

                if ch == "a" || ch == "r" || ch == "s" {
                    let remainder = String(chars.dropFirst(j + 1))
                    let raw = remainder.isEmpty
                        ? requireValue("-\(ch)", args: args, index: &i)
                        : remainder
                    let tags = parseTagList(raw)

                    switch ch {
                    case "a": setOperation(.add(tags), options: &options)
                    case "r": setOperation(.remove(tags), options: &options)
                    default: setOperation(.set(tags), options: &options)
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
        i += 1
    }

    switch options.operation {
    case .list:
        break
    case .copy:
        guard options.paths.count == 2 else {
            fail("--copy requires exactly SOURCE and DESTINATION")
        }
    case .add, .remove, .set:
        guard !options.paths.isEmpty else {
            fail("add/remove/set require at least one explicit path")
        }
    }

    return options
}
