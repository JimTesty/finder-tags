#!/usr/bin/env swift

import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum Operation {
    case list
    case add([String])
    case remove([String])
    case set([String])
}

struct Options {
    var operation: Operation = .list
    var operationWasSet = false
    var color = false
    var showNames = true
    var showTags = true
    var garrulous = false
    var includeHidden = false
    var enterDirectories = false
    var recursive = false
    var slashDirectories = false
    var nulTerminate = false
    var paths: [String] = []
}

struct Target {
    let url: URL
    let displayPath: String
}

let program = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
let fm = FileManager.default
var hadError = false

func eprint(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String, code: Int32 = 64) -> Never {
    eprint("\(program): \(message)")
    exit(code)
}

func usage(code: Int32 = 0) -> Never {
    let text = """
    \(program) - manipulate and list macOS Finder tags, preserving tag order

    usage:
      \(program) [-l | --list] [options] [path ...]
      \(program) -a | --add TAGS [options] path ...
      \(program) -r | --remove TAGS [options] path ...
      \(program) -s | --set TAGS [options] path ...

    TAGS is a comma-separated list. Tag names are compared case-insensitively.

    operations:
      -l, --list             List tags (default)
      -a, --add TAGS         Append tags not already present
      -r, --remove TAGS      Remove matching tags; '*' removes all
      -s, --set TAGS         Replace all tags, in the order given

    output:
      -c, --color            Color known Finder tags using ANSI escapes
      -n, --name             Show filenames (default)
      -N, --no-name          Hide filenames
      -t, --tags             Show tags (default for list)
      -T, --no-tags          Hide tags
      -g, --garrulous        Put each tag on its own line
      -G, --no-garrulous     Put tags comma-separated (default)
      -p, --slash            Append '/' to directory names
      -0, --nul              Terminate output records with NUL

    enumeration:
      -A, --all              Include hidden files while enumerating
      -e, --enter            Enumerate contents of explicit directories
      -R, -d, --recursive    Recursively enumerate directories

    other:
      -h, --help             Show this help
      -v, --version          Show version

    With no paths, list enumerates the current directory. Mutating operations
    require explicit paths.

    Ordering guarantee:
      list    prints URLResourceKey.tagNamesKey in its returned order
      add     keeps existing order and appends new tags in argument order
      remove  keeps the relative order of tags that remain
      set     stores tags in argument order
    """
    if code == 0 { print(text) } else { eprint(text) }
    exit(code)
}

func version() -> Never {
    print("\(program) 2.0")
    exit(0)
}

func canonical(_ tag: String) -> String {
    tag.lowercased()
}

func parseTagList(_ raw: String) -> [String] {
    var seen = Set<String>()
    var result: [String] = []

    for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
        let tag = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { continue }
        let key = canonical(tag)
        if seen.insert(key).inserted { result.append(tag) }
    }
    return result
}

func setOperation(_ operation: Operation, options: inout Options) {
    if options.operationWasSet { fail("operation may be specified only once") }
    options.operation = operation
    options.operationWasSet = true
}

func requireValue(_ option: String, args: [String], index: inout Int) -> String {
    index += 1
    guard index < args.count else { fail("\(option) requires an argument") }
    return args[index]
}

func applyShortFlag(_ ch: Character, options: inout Options) {
    switch ch {
    case "l": setOperation(.list, options: &options)
    case "c": options.color = true
    case "n": options.showNames = true
    case "N": options.showNames = false
    case "t": options.showTags = true
    case "T": options.showTags = false
    case "g": options.garrulous = true
    case "G": options.garrulous = false
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
            let nameValue = arg.dropFirst(2).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(nameValue[0])
            let inlineValue = nameValue.count == 2 ? String(nameValue[1]) : nil

            func operand() -> String {
                if let inlineValue { return inlineValue }
                return requireValue("--\(name)", args: args, index: &i)
            }

            switch name {
            case "list":
                if inlineValue != nil { fail("--list does not take an argument") }
                setOperation(.list, options: &options)
            case "add": setOperation(.add(parseTagList(operand())), options: &options)
            case "remove": setOperation(.remove(parseTagList(operand())), options: &options)
            case "set": setOperation(.set(parseTagList(operand())), options: &options)
            case "color": options.color = true
            case "name": options.showNames = true
            case "no-name": options.showNames = false
            case "tags": options.showTags = true
            case "no-tags": options.showTags = false
            case "garrulous": options.garrulous = true
            case "no-garrulous": options.garrulous = false
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
                    let raw: String
                    if !remainder.isEmpty {
                        raw = remainder
                    } else {
                        raw = requireValue("-\(ch)", args: args, index: &i)
                    }

                    let tags = parseTagList(raw)
                    switch ch {
                    case "a": setOperation(.add(tags), options: &options)
                    case "r": setOperation(.remove(tags), options: &options)
                    default: setOperation(.set(tags), options: &options)
                    }
                    break
                } else {
                    applyShortFlag(ch, options: &options)
                }

                j += 1
            }

            i += 1
            continue
        }

        options.paths.append(arg)
        i += 1
    }

    switch options.operation {
    case .list: break
    case .add, .remove, .set:
        if options.paths.isEmpty { fail("add/remove/set require at least one explicit path") }
    }

    return options
}

func expandedURL(for path: String) -> URL {
    let expanded = NSString(string: path).expandingTildeInPath
    return URL(fileURLWithPath: expanded)
}

func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
}

func relativePath(of child: URL, under directory: URL) -> String {
    let base = directory.standardizedFileURL.path
    let full = child.standardizedFileURL.path
    guard full.hasPrefix(base) else { return child.lastPathComponent }

    var relative = String(full.dropFirst(base.count))
    while relative.first == "/" { relative.removeFirst() }
    return relative
}

func joinedDisplayPath(_ base: String, _ relative: String) -> String {
    if base.isEmpty { return relative }
    if base == "/" { return "/" + relative }
    return base.hasSuffix("/") ? base + relative : base + "/" + relative
}

func enumerateDirectory(_ directory: Target, recursive: Bool, options: Options, body: (Target) -> Void) {
    var enumOptions: FileManager.DirectoryEnumerationOptions = []
    if !options.includeHidden { enumOptions.insert(.skipsHiddenFiles) }
    if !recursive { enumOptions.insert(.skipsSubdirectoryDescendants) }

    guard let enumerator = fm.enumerator(
        at: directory.url,
        includingPropertiesForKeys: [.isDirectoryKey, .tagNamesKey],
        options: enumOptions,
        errorHandler: { url, error in
            eprint("\(program): \(url.path): \(error.localizedDescription)")
            hadError = true
            return true
        }
    ) else {
        eprint("\(program): unable to enumerate \(directory.displayPath)")
        hadError = true
        return
    }

    for case let url as URL in enumerator {
        let rel = relativePath(of: url, under: directory.url)
        body(Target(url: url, displayPath: joinedDisplayPath(directory.displayPath, rel)))
    }
}

func forEachTarget(options: Options, body: (Target) -> Void) {
    if options.paths.isEmpty {
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        enumerateDirectory(Target(url: cwd, displayPath: ""), recursive: options.recursive, options: options, body: body)
        return
    }

    for path in options.paths {
        let url = expandedURL(for: path)

        guard fm.fileExists(atPath: url.path) else {
            eprint("\(program): does not exist: \(path)")
            hadError = true
            continue
        }

        let target = Target(url: url, displayPath: path)
        body(target)

        if isDirectory(url) && (options.enterDirectories || options.recursive) {
            enumerateDirectory(target, recursive: options.recursive, options: options, body: body)
        }
    }
}

func readTags(_ target: Target) throws -> [String] {
    try target.url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
}

func writeTags(_ tags: [String], to target: Target) throws {
    try (target.url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
}

let ansiReset = "\u{001B}[m"
let ansiByFinderColorCode: [Int: String] = [
    1: "\u{001B}[48;5;241m", // gray
    2: "\u{001B}[42m",       // green
    3: "\u{001B}[48;5;129m", // purple
    4: "\u{001B}[44m",       // blue
    5: "\u{001B}[43m",       // yellow
    6: "\u{001B}[41m",       // red
    7: "\u{001B}[48;5;208m"  // orange
]

func loadFinderTagColors() -> [String: String] {
    // Finder does not expose individual tag colors through tagNamesKey. This
    // optional display feature follows jdberry/tag's best-effort Finder plist read.
    let home = fm.homeDirectoryForCurrentUser
    let candidates = [
        home.appendingPathComponent("Library/SyncedPreferences/com.apple.finder.plist"),
        home.appendingPathComponent("Library/Preferences/com.apple.finder.plist")
    ]

    for url in candidates {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = plist as? [String: Any],
              let values = root["values"] as? [String: Any],
              let finderTagDict = values["FinderTagDict"] as? [String: Any],
              let value = finderTagDict["value"] as? [String: Any],
              let entries = value["FinderTags"] as? [[String: Any]]
        else { continue }

        var result: [String: String] = [:]
        for entry in entries {
            guard let name = entry["n"] as? String,
                  let number = entry["l"] as? NSNumber,
                  let escape = ansiByFinderColorCode[number.intValue]
            else { continue }
            result[canonical(name)] = escape
        }
        return result
    }

    return [:]
}

func colorized(_ tag: String, colors: [String: String], enabled: Bool) -> String {
    guard enabled, let escape = colors[canonical(tag)] else { return tag }
    return escape + tag + ansiReset
}

func outputRecord(_ string: String, nul: Bool) {
    FileHandle.standardOutput.write(Data(string.utf8))
    FileHandle.standardOutput.write(Data([nul ? 0 : 10]))
}

func displayPath(_ target: Target, slashDirectories: Bool) -> String {
    guard slashDirectories, isDirectory(target.url), !target.displayPath.hasSuffix("/") else {
        return target.displayPath
    }
    return target.displayPath + "/"
}

func emit(_ target: Target, tags: [String], options: Options, colors: [String: String]) {
    let name = options.showNames ? displayPath(target, slashDirectories: options.slashDirectories) : nil
    let shownTags = options.showTags ? tags.map { colorized($0, colors: colors, enabled: options.color) } : []

    if options.garrulous {
        if let name { outputRecord(name, nul: options.nulTerminate) }
        for tag in shownTags {
            outputRecord((name == nil ? "" : "    ") + tag, nul: options.nulTerminate)
        }
        return
    }

    if let name {
        if shownTags.isEmpty {
            outputRecord(name, nul: options.nulTerminate)
        } else {
            let padding = max(1, 31 - name.count)
            outputRecord(name + String(repeating: " ", count: padding) + "\t" + shownTags.joined(separator: ","), nul: options.nulTerminate)
        }
    } else if !shownTags.isEmpty {
        outputRecord(shownTags.joined(separator: ","), nul: options.nulTerminate)
    }
}

let options = parseArguments()
let colors = options.color ? loadFinderTagColors() : [:]

forEachTarget(options: options) { target in
    do {
        switch options.operation {
        case .list:
            emit(target, tags: try readTags(target), options: options, colors: colors)

        case .set(let requested):
            try writeTags(requested, to: target)

        case .add(let requested):
            var tags = try readTags(target)
            var seen = Set(tags.map(canonical))
            for tag in requested where seen.insert(canonical(tag)).inserted { tags.append(tag) }
            try writeTags(tags, to: target)

        case .remove(let requested):
            let existing = try readTags(target)
            let removeAll = requested.contains("*")
            let unwanted = Set(requested.map(canonical))
            let revised: [String] = removeAll ? [] : existing.filter { !unwanted.contains(canonical($0)) }
            try writeTags(revised, to: target)
        }
    } catch {
        eprint("\(program): \(target.displayPath): \(error.localizedDescription)")
        hadError = true
    }
}

exit(hadError ? 74 : 0)
