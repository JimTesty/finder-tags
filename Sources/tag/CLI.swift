import Foundation

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

private func parseColorMode(_ raw: String) -> ColorMode {
    switch raw.lowercased() {
    case "auto", "yes": return .auto
    case "always", "force": return .always
    case "no", "none", "never": return .never
    default:
        fail("invalid color mode '\(raw)'; use auto, always/force, or never/no")
    }
}

private func applyShortFlag(_ ch: Character, options: inout Options) {
    switch ch {
    case "l": setOperation(.list, options: &options)
    case "c": options.colorMode = .auto
    case "V": options.reverse = true; options.reverseWasSet = true
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
    case "L": options.followSymlinks = true
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
            case "export":
                if inlineValue != nil { fail("--export does not take an argument") }
                setOperation(.export, options: &options)
            case "convert":
                setOperation(.convert, options: &options)
                options.archivePath = operand()
            case "restore":
                setOperation(.restore, options: &options)
                options.archivePath = operand()
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
                validateSingleTagOperand(tag)
                var position: PositionSpec? = nil
                if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    position = parsePosition(requireValue("--move", args: args, index: &i))
                }
                setOperation(.move(tag, position), options: &options)
            case "at":
                setPosition(parsePosition(operand()), options: &options, option: "--at")
            case "before":
                let tag = operand()
                validateSingleTagOperand(tag)
                setPosition(.before(tag), options: &options, option: "--before")
            case "after":
                let tag = operand()
                validateSingleTagOperand(tag)
                setPosition(.after(tag), options: &options, option: "--after")
            case "sorted-tags", "sort-tags": options.sortedTags = true
            case "color":
                options.colorMode = inlineValue.map(parseColorMode) ?? .auto
            case "reverse": options.reverse = true; options.reverseWasSet = true
            case "case-sensitive": options.caseSensitive = true
            case "filename", "name": options.showNamesOverride = true
            case "no-filename", "no-name": options.showNamesOverride = false
            case "tags": options.showTagsOverride = true
            case "no-tags": options.showTagsOverride = false
            case "one-per-line", "garrulous": options.oneTagPerLine = true
            case "comma-separated", "no-garrulous": options.oneTagPerLine = false
            case "space-indent": options.spaceIndent = true
            case "all": options.includeHidden = true
            case "enter": options.enterDirectories = true
            case "recursive", "descend": options.recursive = true
            case "slash": options.slashDirectories = true
            case "print-symlinks": options.printSymlinks = true
            case "null", "nul": options.nulTerminate = true
            case "absolute": options.absolutePaths = true
            case "jsonl", "ndjson": options.jsonLines = true
            case "dry-run", "dryrun": options.dryRun = true
            case "tagged-only": options.taggedOnly = true
            case "file-info":
                options.fileInfo = true
                options.fileInfoWasSet = true
            case "no-file-info":
                options.fileInfo = false
                options.fileInfoWasSet = true
            case "root": options.restoreRoot = operand()
            case "backup":
                options.backupPath = operand()
                options.backupEnabled = true
            case "no-backup": options.backupEnabled = false
            case "sync-backup": options.syncBackup = true
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
    case .export:
        if options.paths.count > 1 {
            fail("--export accepts at most one root path")
        }
        if options.stdinPathMode != nil {
            fail("--export does not accept --stdin path input")
        }
    case .restore:
        if !options.paths.isEmpty {
            fail("--restore accepts the archive path followed by --root DEST, not filesystem paths")
        }
    case .convert:
        if !options.paths.isEmpty {
            fail("--convert accepts the archive path, not filesystem paths")
        }
    case .copy:
        if options.paths.count != 2 {
            fail("--copy requires exactly SOURCE and DESTINATION")
        }
    case .add, .remove, .set, .move:
        if options.paths.isEmpty {
            fail("this operation requires at least one explicit path")
        }
    }

    if options.fileInfoWasSet {
        switch options.operation {
        case .list, .export: break
        default: fail("--file-info is only valid with --list or --export")
        }
    }

    if options.spaceIndent {
        switch options.operation {
        case .convert:
            break
        case .list:
            if options.jsonLines { fail("--space-indent is only valid with text output") }
        default:
            fail("--space-indent is only valid with text output")
        }
    }

    switch options.operation {
    case .list, .export, .convert:
        break
    default:
        if options.taggedOnly {
            fail("--tagged-only is only valid with --list, --export, or --convert")
        }
    }

    switch options.operation {
    case .export:
        // Export is always canonical JSONL. Display-only options are ignored
        // there and remain available to --list and --convert.
        options.recursive = true
        options.includeHidden = true
        options.jsonLines = true
        if !options.fileInfoWasSet { options.fileInfo = true }
        if options.absolutePaths {
            fail("--absolute is not valid with --export; archive paths are root-relative")
        }
        if options.sortedTags {
            fail("--sorted-tags is not valid with --export")
        }
        if options.oneTagPerLine || options.nulTerminate {
            fail("text display formatting options are not valid with --export")
        }
    default:
        break
    }

    if options.restoreRoot != nil {
        switch options.operation {
        case .restore: break
        default: fail("--root is only valid with --restore")
        }
    }

    if options.backupPath != nil || !options.backupEnabled || options.syncBackup {
        if !options.isMutating {
            fail("backup options are only valid with a mutating operation")
        }
    }

    switch options.operation {
    case .restore:
        if options.archivePath == nil { fail("--restore requires an archive path or '-'") }
    case .convert:
        if options.archivePath == nil { fail("--convert requires an archive path or '-'") }
    default:
        break
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
        fail("--dry-run is only valid with --add, --remove, --set, --move, --copy, or --restore")
    }

    return options
}
