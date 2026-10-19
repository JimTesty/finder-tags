import Foundation

private let maximumTagAlignment = 999_999

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
    case "auto": return .auto
    case "yes", "on", "always", "force": return .always
    case "off", "no", "none", "never": return .never
    default:
        fail("invalid color mode '\(raw)'; use auto, yes/on/always/force, or no/off/never/none")
    }
}

private func parseTagAlignment(_ raw: String) -> Int {
    guard let value = Int(raw), value >= 0, value <= maximumTagAlignment else {
        fail("invalid tag alignment '\(raw)'; use an integer from 0 through \(maximumTagAlignment)")
    }
    return value
}

private func parseExcludePattern(_ raw: String) -> String {
    var value = raw
    while value.hasPrefix("./") { value.removeFirst(2) }
    while value.hasSuffix("/") { value.removeLast() }

    guard !value.isEmpty, !value.hasPrefix("/") else {
        fail("--exclude requires a non-empty relative path")
    }
    let components = value.split(separator: "/", omittingEmptySubsequences: false)
    guard !components.contains(where: {
        let component = String($0)
        return component.isEmpty || component == "." || component == ".."
    }) else {
        fail("--exclude path may not contain empty, '.', or '..' components")
    }
    return value
}

private func applyShortFlag(_ ch: Character, options: inout Options) {
    switch ch {
    case "l": setOperation(.list, options: &options)
    case "c":
        options.colorMode = .auto
        Diagnostics.colorMode = options.colorMode
        options.colorWasSet = true
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
    case "h": options.helpRequests += 1
    case "q": options.verbosity -= 1
    case "v": options.verbosity += 1
    default: fail("unknown option: -\(ch)")
    }
}

func parseArguments() -> Options {
    // Wait for the final color setting before printing recoverable warnings.
    Diagnostics.beginParsing()
    var options = parseCommandLineArguments(Array(CommandLine.arguments.dropFirst()))
    Diagnostics.colorMode = options.colorMode
    Diagnostics.finishParsing()
    if options.helpRequests > 0 {
        usage(detailed: options.helpRequests > 1 || options.verbose)
    }
    if let mode = options.stdinPathMode {
        options.paths.append(contentsOf: readPathsFromStdin(mode))
    }

    validateAndApplyDefaults(&options)
    return options
}

private func parseCommandLineArguments(_ args: [String]) -> Options {
    var options = Options()
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
            var takesValue = false

            func rejectInlineValue() {
                if inlineValue != nil { fail("--\(name) does not take an argument") }
            }

            func operand() -> String {
                takesValue = true
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
            case "remove", "del", "delete":
                setOperation(.remove(parseTagList(operand())), options: &options)
            case "set", "replace":
                setOperation(.set(parseTagList(operand())), options: &options)
            case "fix", "repair":
                setOperation(.fix, options: &options)
            case "match":
                setOperation(.match(parseTagQuery(operand())), options: &options)
            case "filter":
                setOperation(.filter(parseTagQuery(operand())), options: &options)
            case "usage":
                setOperation(.usage(parseTagQuery(operand())), options: &options)
            case "find":
                setOperation(.find(parseTagQuery(operand())), options: &options)
            case "copy":
                if inlineValue != nil {
                    fail("--copy does not take '=...'; use --copy SOURCE DESTINATION")
                }
                setOperation(.copy, options: &options)
            case "move":
                if inlineValue != nil {
                    fail("--move does not take '=...'; use --move TAG POSITION")
                }
                let tag = validatedSingleTagOperand(requireValue("--move", args: args, index: &i))
                var position: PositionSpec? = nil
                if i + 1 < args.count && !args[i + 1].hasPrefix("-") {
                    position = parsePosition(requireValue("--move", args: args, index: &i))
                }
                setOperation(.move(tag, position), options: &options)
            case "at":
                setPosition(parsePosition(operand()), options: &options, option: "--at")
            case "before":
                let tag = validatedSingleTagOperand(operand())
                setPosition(.before(tag), options: &options, option: "--before")
            case "after":
                let tag = validatedSingleTagOperand(operand())
                setPosition(.after(tag), options: &options, option: "--after")
            case "sorted-tags", "sort-tags": options.sortedTags = true
            case "color":
                takesValue = true
                options.colorMode = inlineValue.map(parseColorMode) ?? .auto
                Diagnostics.colorMode = options.colorMode
                options.colorWasSet = true
            case "no-color":
                options.colorMode = .never
                Diagnostics.colorMode = options.colorMode
                options.colorWasSet = true
            case "reverse": options.reverse = true; options.reverseWasSet = true
            case "case-sensitive": options.caseSensitive = true
            case "filename", "name": options.showNamesOverride = true
            case "no-filename", "no-name": options.showNamesOverride = false
            case "tags": options.showTagsOverride = true
            case "no-tags": options.showTagsOverride = false
            case "one-per-line", "garrulous": options.oneTagPerLine = true
            case "comma-separated", "no-garrulous": options.oneTagPerLine = false
            case "space-indent": options.spaceIndent = true
            case "align-tags":
                options.alignTags = parseTagAlignment(operand())
                options.spaceIndent = true
            case "compact-tags":
                options.compactTags = true
                if !options.colorWasSet { options.colorMode = .auto }
                Diagnostics.colorMode = options.colorMode
                options.reverse = true
                options.reverseWasSet = true
            case "all", "dot-files", "include-hidden": options.includeHidden = true
            case "enter": options.enterDirectories = true
            case "recursive", "descend": options.recursive = true
            case "no-sort-files": options.sortFiles = false
            case "slash": options.slashDirectories = true
            case "print-symlinks": options.printSymlinks = true
            case "exclude": options.excludePatterns.append(parseExcludePattern(operand()))
            case "null", "nul": options.nulTerminate = true
            case "absolute": options.absolutePaths = true
            case "jsonl", "ndjson": options.jsonLines = true
            case "dry-run", "dryrun": options.dryRun = true
            case "quiet": options.verbosity -= 1
            case "verbose": options.verbosity += 1
            case "tagged-only": options.taggedOnly = true
            case "file-info":
                options.fileInfo = true
                options.fileInfoWasSet = true
            case "no-file-info":
                options.fileInfo = false
                options.fileInfoWasSet = true
            case "root": options.restoreRoot = operand()
            case "backup":
                options.backupPath = nil
                options.backupOverride = true
            case "backup-path":
                options.backupPath = operand()
                options.backupOverride = true
            case "no-backup": options.backupOverride = false
            case "sync-backup": options.syncBackup = true
            case "no-follow-symlinks": options.followSymlinks = false
            case "follow-symlinks": options.followSymlinks = true
            case "resolve-symlinks0": options.resolveSymlinksForArguments = true
            case "stdin", "files-from-stdin":
                if options.stdinPathMode != nil { fail("stdin path mode may be specified only once") }
                options.stdinPathMode = .lines
                options.pathInputExplicit = true
            case "stdin0", "files0-from-stdin":
                if options.stdinPathMode != nil { fail("stdin path mode may be specified only once") }
                options.stdinPathMode = .nul
                options.pathInputExplicit = true
            case "help": rejectInlineValue(); options.helpRequests += 1
            case "version": rejectInlineValue(); version()
            default: fail("unknown option: --\(name)")
            }

            if !takesValue { rejectInlineValue() }
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
                    switch ch {
                    case "a": setOperation(.add(parseTagList(raw)), options: &options)
                    case "r": setOperation(.remove(parseTagList(raw)), options: &options)
                    case "s": setOperation(.set(parseTagList(raw)), options: &options)
                    case "m": setOperation(.match(parseTagQuery(raw)), options: &options)
                    case "u": setOperation(.usage(parseTagQuery(raw)), options: &options)
                    default: setOperation(.find(parseTagQuery(raw)), options: &options)
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

    return options
}

private func validateAndApplyDefaults(_ options: inout Options) {
    func ignored(_ specified: Bool, _ option: String, _ reason: String) {
        if specified && options.verbose {
            reportWarning("\(option) ignored: \(reason)")
        }
    }

    switch options.operation {
    case .list, .match, .filter, .usage, .find:
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
        if options.jsonLines {
            fail("--jsonl is not valid with --convert; conversion produces text")
        }
    case .copy:
        if options.paths.count != 2 {
            fail("--copy requires exactly SOURCE and DESTINATION")
        }
    case .add, .remove, .set, .fix, .move:
        if options.paths.isEmpty {
            fail("this operation requires at least one explicit path")
        }
    }

    if options.fileInfoWasSet {
        switch options.operation {
        case .list, .match, .filter, .find, .export: break
        default:
            ignored(true, options.fileInfo ? "--file-info" : "--no-file-info",
                    "this operation does not collect file metadata")
            options.fileInfo = false
        }
    }

    if !options.excludePatterns.isEmpty {
        switch options.operation {
        case .list, .export, .match, .filter, .usage, .add, .remove, .set, .fix, .move:
            break
        default:
            fail("--exclude is only valid with filesystem traversal operations")
        }
    }

    if !options.sortFiles {
        switch options.operation {
        case .list, .export, .match, .filter, .usage, .find, .add, .remove, .set, .fix, .move:
            break
        default:
            ignored(true, "--no-sort-files", "this operation does not enumerate or search files")
        }
    }

    if case .export = options.operation {
        // Export is always canonical JSONL. Display-only options are ignored
        // there and remain available to --list and --convert.
        options.recursive = true
        options.includeHidden = true
        options.jsonLines = true
        if !options.fileInfoWasSet { options.fileInfo = true }
        ignored(options.absolutePaths, "--absolute", "archive paths are root-relative")
        ignored(options.sortedTags, "--sorted-tags", "archives preserve stored tag order")
        ignored(options.reverseWasSet, "--reverse", "archives preserve stored tag order")
    }

    let fileList: Bool
    switch options.operation {
    case .list, .match, .filter, .find, .convert: fileList = true
    default: fileList = false
    }
    let textFileList = fileList && !options.jsonLines
    let formattingReason = options.jsonLines
        ? "output is JSONL" : "this operation does not produce file-list output"
    if !textFileList {
        ignored(options.alignTags != nil, "--align-tags", formattingReason)
        ignored(options.compactTags, "--compact-tags layout", formattingReason)
        ignored(options.oneTagPerLine, "--one-per-line", formattingReason)
    }
    var spaceIndentApplies = textFileList
    if case .usage = options.operation { spaceIndentApplies = !options.jsonLines }
    ignored(options.spaceIndent && options.alignTags == nil && !spaceIndentApplies,
            "--space-indent", formattingReason)
    ignored(options.nulTerminate && options.jsonLines, "--null", "JSONL uses newline-delimited records")
    let previewPaths = options.isMutating && options.dryRun && !options.jsonLines
    ignored(options.slashDirectories && !textFileList && !previewPaths, "--slash", formattingReason)
    if case .convert = options.operation {
        ignored(options.absolutePaths, "--absolute", "conversion displays recorded archive paths")
    }

    if options.restoreRoot != nil {
        switch options.operation {
        case .restore: break
        default: fail("--root is only valid with --restore")
        }
    }

    if options.backupPath != nil || options.backupOverride != nil || options.syncBackup {
        if !options.isMutating {
            ignored(options.backupOverride != nil, "backup options", "this operation does not mutate files")
            ignored(options.syncBackup, "--sync-backup", "this operation does not mutate files")
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
            if options.isMutating {
                fail("--at/--before/--after are only valid with --add or --move")
            }
            ignored(true, "--at/--before/--after", "this operation does not edit tag placement")
        }
    }

    ignored(options.dryRun && !options.isMutating, "--dry-run", "this operation does not mutate files")
}
