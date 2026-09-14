import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct ArchiveEntry {
    let path: String
    let tags: [String]
    let metadata: FileMetadata?
}

struct ArchiveSymlink {
    let path: String
    let resolvedPath: String
}

struct ArchiveDocument {
    let rootPath: String
    let entries: [ArchiveEntry]
    let symlinks: [ArchiveSymlink]
}

struct ArchiveStats {
    var visited = 0
    var tagged = 0
    var emitted = 0
    var errors = 0
    var unchanged = 0
    var changed = 0
    var restored = 0
    var missing = 0
    var warnings = 0
}

enum ArchiveError: LocalizedError {
    case invalidLine(line: Int, message: String)
    case missingRoot
    case multipleRoots
    case invalidRoot(String)
    case invalidPath(String)
    case duplicatePath(String)
    case duplicateSymlink(String)
    case invalidTags(String)
    case invalidMetadata(String)
    case unsupportedRecord(String)

    var errorDescription: String? {
        switch self {
        case let .invalidLine(line, message):
            return "archive line \(line): \(message)"
        case .missingRoot:
            return "archive has no @root record"
        case .multipleRoots:
            return "archive contains multiple roots; v1 accepts one root"
        case let .invalidRoot(path):
            return "archive root is not an absolute path: \(path)"
        case let .invalidPath(path):
            return "invalid archive item path: \(path)"
        case let .duplicatePath(path):
            return "duplicate archive item: \(path)"
        case let .duplicateSymlink(path):
            return "duplicate archive symlink: \(path)"
        case let .invalidTags(value):
            return "invalid archive tag list: \(value)"
        case let .invalidMetadata(value):
            return "invalid archive file metadata: \(value)"
        case let .unsupportedRecord(type):
            return "unsupported archive record type: \(type)"
        }
    }
}

private struct ArchiveBuilder {
    var rootPath: String?
    var entries: [ArchiveEntry] = []
    var symlinks: [ArchiveSymlink] = []
    var entryIndexes: [String: Int] = [:]
    var symlinkIndexes: [String: Int] = [:]
    var metadataByPath: [String: FileMetadata] = [:]

    mutating func setRoot(_ rawPath: String) throws {
        guard rawPath.hasPrefix("/"), !rawPath.unicodeScalars.contains("\0") else {
            throw ArchiveError.invalidRoot(rawPath)
        }
        let path = expandedFileURL(rawPath).path
        guard rootPath == nil else { throw ArchiveError.multipleRoots }
        rootPath = path
    }

    mutating func addMetadata(path: String, metadata: FileMetadata) throws {
        try validateRelativeArchivePath(path)
        guard metadata.size >= 0, metadata.modificationTime.isFinite else {
            throw ArchiveError.invalidMetadata(path)
        }
        guard metadataByPath[path] == nil else {
            throw ArchiveError.invalidMetadata("duplicate metadata for \(path)")
        }
        metadataByPath[path] = metadata
    }

    mutating func addEntry(path: String, tags: [String], metadata: FileMetadata? = nil) throws {
        try validateRelativeArchivePath(path)
        for tag in tags {
            if tag.isEmpty || tag.contains("\n") || tag.contains("\r") || tag.unicodeScalars.contains("\0") {
                throw ArchiveError.invalidTags(tag)
            }
        }

        if entryIndexes[path] != nil {
            throw ArchiveError.duplicatePath(path)
        }
        entryIndexes[path] = entries.count
        entries.append(ArchiveEntry(
            path: path,
            tags: tags,
            metadata: metadata ?? metadataByPath.removeValue(forKey: path)
        ))
    }

    mutating func addSymlink(path: String, resolvedPath: String) throws {
        try validateRelativeArchivePath(path)
        guard resolvedPath.hasPrefix("/"), !resolvedPath.unicodeScalars.contains("\0") else {
            throw ArchiveError.invalidPath(resolvedPath)
        }

        if symlinkIndexes[path] != nil {
            throw ArchiveError.duplicateSymlink(path)
        }
        symlinkIndexes[path] = symlinks.count
        symlinks.append(ArchiveSymlink(path: path, resolvedPath: resolvedPath))
    }

    func document() throws -> ArchiveDocument {
        guard let rootPath = rootPath else { throw ArchiveError.missingRoot }
        return ArchiveDocument(rootPath: rootPath, entries: entries, symlinks: symlinks)
    }
}

struct ArchiveReader {
    func read(path: String) throws -> ArchiveDocument {
        let data: Data
        if path == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            data = try Data(contentsOf: expandedFileURL(path))
        }

        guard let text = String(data: data, encoding: .utf8) else {
            throw ArchiveError.invalidLine(line: 1, message: "archive is not valid UTF-8")
        }
        let firstLine = text.components(separatedBy: "\n").first {
            let line = stripANSI($0).trimmingCharacters(in: .whitespacesAndNewlines)
            return !line.isEmpty
        } ?? ""

        if firstLine.hasPrefix("{") {
            return try readJSONLines(text)
        }
        return try readPlaintext(text)
    }

    private func readJSONLines(_ text: String) throws -> ArchiveDocument {
        var builder = ArchiveBuilder()
        let lines = text.components(separatedBy: "\n")

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            var line = stripANSI(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }

            guard let data = line.data(using: .utf8) else {
                throw ArchiveError.invalidLine(line: lineNumber, message: "not valid UTF-8")
            }
            let value: Any
            do {
                value = try JSONSerialization.jsonObject(with: data, options: [])
            } catch {
                throw ArchiveError.invalidLine(line: lineNumber, message: error.localizedDescription)
            }
            guard let object = value as? [String: Any] else {
                throw ArchiveError.invalidLine(line: lineNumber, message: "record is not a JSON object")
            }

            let type = object["type"] as? String
            if type == "summary" { continue }

            if type == "root" {
                guard let path = object["path"] as? String else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "root record lacks string path")
                }
                try builder.setRoot(path)
                continue
            }

            if type == "symlink" {
                guard let path = object["path"] as? String,
                      let resolvedPath = object["resolvedPath"] as? String
                else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "symlink record lacks path or resolvedPath")
                }
                try builder.addSymlink(path: path, resolvedPath: resolvedPath)
                if let tags = object["tags"] {
                    try builder.addEntry(
                        path: path,
                        tags: try jsonTags(tags, line: lineNumber),
                        metadata: try jsonMetadata(object, line: lineNumber)
                    )
                }
                continue
            }

            if let type = type, !type.isEmpty {
                throw ArchiveError.unsupportedRecord(type)
            }
            guard let path = object["path"] as? String,
                  let rawTags = object["tags"]
            else {
                throw ArchiveError.invalidLine(line: lineNumber, message: "file record needs string path and tags array")
            }
            try builder.addEntry(
                path: path,
                tags: try jsonTags(rawTags, line: lineNumber),
                metadata: try jsonMetadata(object, line: lineNumber)
            )
        }

        return try builder.document()
    }

    private func jsonTags(_ value: Any, line: Int) throws -> [String] {
        guard let values = value as? [Any] else {
            throw ArchiveError.invalidLine(line: line, message: "tags is not an array")
        }
        var result: [String] = []
        for value in values {
            guard let tag = value as? String else {
                throw ArchiveError.invalidLine(line: line, message: "tags must contain only strings")
            }
            result.append(tag)
        }
        return result
    }

    private func jsonMetadata(_ object: [String: Any], line: Int) throws -> FileMetadata? {
        guard object["size"] != nil || object["mtime"] != nil else { return nil }
        guard let size = object["size"] as? NSNumber,
              let mtime = object["mtime"] as? NSNumber else {
            throw ArchiveError.invalidLine(line: line, message: "size and mtime must be numbers")
        }
        let metadata = FileMetadata(size: size.int64Value, modificationTime: mtime.doubleValue)
        guard metadata.size >= 0, metadata.modificationTime.isFinite else {
            throw ArchiveError.invalidLine(line: line, message: "invalid size or mtime")
        }
        return metadata
    }

    private func readPlaintext(_ text: String) throws -> ArchiveDocument {
        var builder = ArchiveBuilder()
        let lines = text.components(separatedBy: "\n")
        var sawHeader = false

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            var line = stripANSI(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "# finder-tags archive v1" {
                sawHeader = true
                continue
            }
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            if line == "@root" || line.hasPrefix("@root ") || line.hasPrefix("@root\t") {
                let rawValue = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawValue.isEmpty else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "@root lacks a path")
                }
                do {
                    try builder.setRoot(parseArchiveField(rawValue))
                } catch let error as ArchiveError {
                    throw error
                } catch {
                    throw ArchiveError.invalidLine(line: lineNumber, message: error.localizedDescription)
                }
                continue
            }
            if line == "@symlink" || line.hasPrefix("@symlink ") || line.hasPrefix("@symlink\t") {
                let rest = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                let fields = rest.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 2 else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "@symlink needs path and resolved target separated by a tab")
                }
                do {
                    try builder.addSymlink(
                        path: parseArchiveField(fields[0]),
                        resolvedPath: parseArchiveField(fields[1])
                    )
                } catch let error as ArchiveError {
                    throw error
                } catch {
                    throw ArchiveError.invalidLine(line: lineNumber, message: error.localizedDescription)
                }
                continue
            }

            if line == "@metadata" || line.hasPrefix("@metadata ") || line.hasPrefix("@metadata\t") {
                let rest = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                let fields = rest.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard fields.count == 3,
                      let size = Int64(fields[1]),
                      let mtime = Double(fields[2]) else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "@metadata needs path, size, and mtime")
                }
                try builder.addMetadata(
                    path: parseArchiveField(fields[0]),
                    metadata: FileMetadata(size: size, modificationTime: mtime)
                )
                continue
            }

            guard let tab = line.firstIndex(of: "\t") else {
                throw ArchiveError.invalidLine(line: lineNumber, message: "item needs a tab between path and tags")
            }
            let rawPath = String(line[..<tab]).trimmingCharacters(in: .whitespaces)
            let rawTags = String(line[line.index(after: tab)...])
            do {
                let path = try parseArchiveField(rawPath)
                let tags = try parseArchiveTagList(rawTags)
                try builder.addEntry(path: path, tags: tags)
            } catch let error as ArchiveError {
                throw error
            } catch {
                throw ArchiveError.invalidLine(line: lineNumber, message: error.localizedDescription)
            }
        }

        if !sawHeader {
            throw ArchiveError.invalidLine(line: 1, message: "missing '# finder-tags archive v1' header")
        }
        return try builder.document()
    }
}

final class ArchiveWriter {
    private let options: Options
    private let colors: FinderColors
    private var rootURL: URL?
    private var emittedSymlinks = Set<String>()
    private var didEmitRoot = false

    var stats = ArchiveStats()

    init(options: Options, colors: FinderColors) {
        self.options = options
        self.colors = colors
    }

    func emitRoot(_ root: URL) throws {
        rootURL = root.standardizedFileURL
        guard !didEmitRoot else { return }
        didEmitRoot = true

        if options.jsonLines {
            try writeJSON(["type": "root", "path": rootURL!.path])
        } else {
            writeText("# finder-tags archive v1")
            writeText("@root \(archiveQuote(rootURL!.path))")
        }
    }

    func emitTarget(_ target: Target, tags: [String]) throws {
        guard let rootURL = rootURL else { throw ArchiveError.missingRoot }
        stats.visited += 1
        let path = try relativePath(target.logicalURL, to: rootURL)

        if isSymbolicLink(target.logicalURL) && emittedSymlinks.insert(path).inserted {
            if options.jsonLines {
                try writeJSON([
                    "type": "symlink",
                    "path": path,
                    "resolvedPath": target.resolvedPath
                ])
            } else {
                writeText("@symlink \(archiveQuote(path))\t\(archiveQuote(target.resolvedPath))")
            }
            stats.emitted += 1
        }

        guard !tags.isEmpty else { return }
        stats.tagged += 1
        let metadata = options.fileInfo ? try fileMetadata(for: target.url) : nil
        if options.jsonLines {
            var object: [String: Any] = ["path": path, "tags": tags]
            if let metadata = metadata {
                object["size"] = metadata.size
                object["mtime"] = metadata.modificationTime
            }
            try writeJSON(object)
        } else {
            if let metadata = metadata {
                writeText("@metadata \(archiveQuote(path))\t\(metadata.size)\t\(metadata.modificationTime)")
            }
            let renderedTags = tags.map(colors.render).map(archiveQuote).joined(separator: ", ")
            writeText("\(archiveQuote(path))\t\(renderedTags)")
        }
        stats.emitted += 1
    }

    func finish() throws {
        if options.jsonLines {
            try writeJSON([
                "type": "summary",
                "operation": "export",
                "visited": stats.visited,
                "tagged": stats.tagged,
                "emitted": stats.emitted,
                "errors": stats.errors
            ])
        } else {
            eprint("\(programName): exported \(stats.tagged) tagged items (\(stats.visited) visited, \(stats.emitted) records, \(stats.errors) errors)")
        }
    }

    private func relativePath(_ logicalURL: URL, to rootURL: URL) throws -> String {
        let root = rootURL.standardizedFileURL.path
        let logical = logicalURL.standardizedFileURL.path
        if logical == root { return "." }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard logical.hasPrefix(prefix) else {
            throw ArchiveError.invalidPath(logical)
        }
        return String(logical.dropFirst(prefix.count))
    }

    private func writeJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    private func writeText(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }
}

final class UndoWriter {
    let path: String
    private let syncEachRecord: Bool
    private var handle: FileHandle?

    init(path: String, syncEachRecord: Bool) {
        self.path = path
        self.syncEachRecord = syncEachRecord
    }

    func record(target: Target, tags: [String]) throws {
        try openIfNeeded()
        let absolute = target.logicalURL.standardizedFileURL.path
        let relative = absolute == "/" ? "." : String(absolute.dropFirst())
        let renderedTags = tags.map(archiveQuote).joined(separator: ", ")
        let line = "\(archiveQuote(relative))\t\(renderedTags)\n"
        guard let handle = handle else { return }
        handle.write(Data(line.utf8))
        if syncEachRecord && fsync(handle.fileDescriptor) != 0 {
            throw ArchiveIOError.syncFailed(path: path, reason: String(cString: strerror(errno)))
        }
    }

    func finish() throws {
        guard let handle = handle else { return }
        handle.closeFile()
        self.handle = nil
    }

    private func openIfNeeded() throws {
        if handle != nil { return }
        let url = expandedFileURL(path)
        if fileManager.fileExists(atPath: url.path) {
            throw ArchiveIOError.alreadyExists(path: url.path)
        }
        guard fileManager.createFile(atPath: url.path, contents: nil, attributes: nil) else {
            throw ArchiveIOError.cannotCreate(path: url.path)
        }
        guard let file = FileHandle(forWritingAtPath: url.path) else {
            throw ArchiveIOError.cannotCreate(path: url.path)
        }
        handle = file
        file.write(Data("# finder-tags archive v1\n@root /\n".utf8))
        if syncEachRecord && fsync(file.fileDescriptor) != 0 {
            throw ArchiveIOError.syncFailed(path: path, reason: String(cString: strerror(errno)))
        }
        eprint("\(programName): undo archive: \(url.path)")
    }
}

enum ArchiveIOError: LocalizedError {
    case alreadyExists(path: String)
    case cannotCreate(path: String)
    case syncFailed(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .alreadyExists(path): return "undo archive already exists: \(path)"
        case let .cannotCreate(path): return "cannot create undo archive: \(path)"
        case let .syncFailed(path, reason): return "cannot sync undo archive \(path): \(reason)"
        }
    }
}

func defaultUndoArchivePath() -> String {
    let identifier = UUID().uuidString
    return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(
        "finder-tags-undo-\(identifier).archive"
    ).path
}

func archiveQuote(_ value: String) -> String {
    if !archiveFieldNeedsQuotes(value) { return value }
    var result = "\""
    for scalar in value.unicodeScalars {
        switch scalar.value {
        case 0x5c: result += "\\\\"
        case 0x22: result += "\\\""
        case 0x09: result += "\\t"
        case 0x0a: result += "\\n"
        case 0x0d: result += "\\r"
        default: result.append(Character(scalar))
        }
    }
    return result + "\""
}

private func archiveFieldNeedsQuotes(_ value: String) -> Bool {
    if value.isEmpty || value.hasPrefix("#") || value.hasPrefix("@") { return true }
    for scalar in value.unicodeScalars {
        if CharacterSet.whitespacesAndNewlines.contains(scalar)
            || scalar.value == 0x2c || scalar.value == 0x09
            || scalar.value == 0x22 || scalar.value == 0x5c
        {
            return true
        }
    }
    return false
}

private func validateRelativeArchivePath(_ path: String) throws {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.unicodeScalars.contains("\0") else {
        throw ArchiveError.invalidPath(path)
    }
    if path == "." { return }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    if components.contains(where: {
        let component = String($0)
        return component.isEmpty || component == "." || component == ".."
    }) {
        throw ArchiveError.invalidPath(path)
    }
}

private func parseArchiveField(_ raw: String) throws -> String {
    let value = raw.trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty else { throw ArchiveError.invalidPath(raw) }
    if value.first != "\"" {
        if value.contains("\"") || value.contains("\\") || value.contains("\t") {
            throw ArchiveError.invalidPath(raw)
        }
        return value
    }

    let chars = Array(value)
    guard chars.last == "\"" else { throw ArchiveError.invalidPath(raw) }
    var result = ""
    var index = 1
    while index < chars.count - 1 {
        let ch = chars[index]
        if ch == "\\" {
            index += 1
            guard index < chars.count - 1 else { throw ArchiveError.invalidPath(raw) }
            switch chars[index] {
            case "\\": result.append("\\")
            case "\"": result.append("\"")
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            default: throw ArchiveError.invalidPath(raw)
            }
        } else {
            result.append(ch)
        }
        index += 1
    }
    return result
}

private func parseArchiveTagList(_ raw: String) throws -> [String] {
    if raw.trimmingCharacters(in: .whitespaces).isEmpty { return [] }

    let chars = Array(raw)
    var result: [String] = []
    var current = ""
    var quoted = false
    var afterQuote = false

    func appendCurrent() throws {
        let value = quoted ? current : current.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { throw ArchiveError.invalidTags(raw) }
        if value.contains("\n") || value.contains("\r") || value.unicodeScalars.contains("\0") {
            throw ArchiveError.invalidTags(value)
        }
        result.append(value)
        current = ""
        quoted = false
        afterQuote = false
    }

    var index = 0
    while index < chars.count {
        let ch = chars[index]
        if quoted {
            if ch == "\\" {
                index += 1
                guard index < chars.count else { throw ArchiveError.invalidTags(raw) }
                switch chars[index] {
                case "\\": current.append("\\")
                case "\"": current.append("\"")
                case "n": current.append("\n")
                case "r": current.append("\r")
                case "t": current.append("\t")
                default: throw ArchiveError.invalidTags(raw)
                }
            } else if ch == "\"" {
                quoted = false
                afterQuote = true
            } else {
                current.append(ch)
            }
        } else if afterQuote {
            if ch.isWhitespace {
                // Padding between a quoted tag and its comma is harmless.
            } else if ch == "," {
                try appendCurrent()
            } else {
                throw ArchiveError.invalidTags(raw)
            }
        } else if ch == "\"" {
            if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ArchiveError.invalidTags(raw)
            }
            current = ""
            quoted = true
        } else if ch == "," {
            try appendCurrent()
        } else {
            current.append(ch)
        }
        index += 1
    }

    if quoted || afterQuote || !current.isEmpty {
        try appendCurrent()
    }
    return result
}

private func stripANSI(_ value: String) -> String {
    let chars = Array(value)
    var result = ""
    var index = 0
    while index < chars.count {
        if chars[index] == "\u{001B}" && index + 1 < chars.count && chars[index + 1] == "[" {
            index += 2
            while index < chars.count {
                let end = chars[index]
                index += 1
                if end == "m" { break }
            }
        } else {
            result.append(chars[index])
            index += 1
        }
    }
    return result
}
