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
    case invalidHeader(String)
    case unsupportedRecord(String)

    var errorDescription: String? {
        switch self {
        case let .invalidLine(line, message):
            return "archive line \(line): \(message)"
        case .missingRoot:
            return "archive has no @root record"
        case .multipleRoots:
            return "archive contains multiple roots; v2 accepts one root"
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
        case let .invalidHeader(value):
            return "invalid archive header: \(value)"
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
    var header: ArchiveHeader?

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
        var normalizedTags = tags
        if header?.reverse == true { normalizedTags.reverse() }
        entries.append(ArchiveEntry(
            path: path,
            tags: normalizedTags,
            metadata: metadata ?? metadataByPath.removeValue(forKey: path)
        ))
    }

    mutating func setHeader(_ newHeader: ArchiveHeader) throws {
        guard header == nil else {
            throw ArchiveError.invalidHeader("multiple header records")
        }
        guard entries.isEmpty, symlinks.isEmpty, metadataByPath.isEmpty else {
            throw ArchiveError.invalidHeader("header must precede archive records")
        }
        header = newHeader
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

        guard firstLine.first == "{" else {
            throw ArchiveError.invalidLine(line: 1, message: "missing JSON archive header")
        }
        let header = try archiveHeader(from: jsonObject(from: firstLine), line: 1)
        switch header.encoding {
        case .plain: return try readPlaintext(text)
        case .jsonl: return try readJSONLines(text)
        }
    }

    private func readJSONLines(_ text: String) throws -> ArchiveDocument {
        var builder = ArchiveBuilder()
        let lines = text.components(separatedBy: "\n")
        var sawHeader = false

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

            if type == "header" {
                guard !sawHeader else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "multiple archive headers")
                }
                try builder.setHeader(try archiveHeader(from: object, line: lineNumber))
                guard builder.header?.encoding == .jsonl else {
                    throw ArchiveError.invalidHeader("JSONL record has a non-JSONL format")
                }
                sawHeader = true
                continue
            }

            guard sawHeader else {
                throw ArchiveError.invalidLine(line: lineNumber, message: "archive header must be first")
            }

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

        guard sawHeader else {
            throw ArchiveError.invalidLine(line: 1, message: "missing JSON archive header")
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
        var format: ArchiveHeader?

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            var line = stripANSI(rawLine)
            if line.hasSuffix("\r") { line.removeLast() }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if !sawHeader {
                guard trimmed.first == "{" else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "archive header must be first")
                }
                let object: [String: Any]
                do {
                    object = try jsonObject(from: trimmed)
                } catch {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "invalid JSON archive header")
                }
                guard object["type"] as? String == "header" else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "first record is not an archive header")
                }
                let header = try archiveHeader(from: object, line: lineNumber)
                guard header.encoding == .plain else {
                    throw ArchiveError.invalidHeader("plaintext record has a non-plaintext format")
                }
                try builder.setHeader(header)
                format = header
                sawHeader = true
                continue
            }

            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let format = format else {
                throw ArchiveError.invalidHeader("missing plaintext format")
            }
            if line == "@root" || line.hasPrefix("@root ") || line.hasPrefix("@root\t") {
                let rawValue = String(line.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !rawValue.isEmpty else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "@root lacks a path")
                }
                do {
                    try builder.setRoot(parseArchiveField(rawValue, separator: format.separator))
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
                        path: parseArchiveField(fields[0], separator: format.separator),
                        resolvedPath: parseArchiveField(fields[1], separator: format.separator)
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
                    path: parseArchiveField(fields[0], separator: format.separator),
                    metadata: FileMetadata(size: size, modificationTime: mtime)
                )
                continue
            }

            do {
                let (rawPath, tagStart) = try parseArchiveFieldPrefix(line, separator: format.separator)
                var path = rawPath
                if format.slashDirectories && path != "." && path.hasSuffix("/") {
                    path.removeLast()
                }
                let rawTags = String(line[line.index(line.startIndex, offsetBy: tagStart)...])
                let tags = try parseArchiveTagList(rawTags, separator: format.separator)
                try builder.addEntry(path: path, tags: tags)
            } catch let error as ArchiveError {
                throw error
            } catch {
                throw ArchiveError.invalidLine(line: lineNumber, message: error.localizedDescription)
            }
        }

        guard sawHeader else {
            throw ArchiveError.invalidLine(line: 1, message: "missing JSON archive header")
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

        try writeJSON(archiveHeaderObject(
            encoding: options.jsonLines ? .jsonl : .plain,
            separator: options.archiveSeparator,
            reverse: options.reverse,
            slashDirectories: options.slashDirectories,
            spaceIndent: options.spaceIndent,
            fileInfo: options.fileInfo
        ))

        if options.jsonLines {
            try writeJSON(["type": "root", "path": rootURL!.path])
        } else {
            writeText("@root \(archiveQuote(rootURL!.path, separator: options.archiveSeparator))")
        }
    }

    func emitTarget(_ target: Target, tags: [String]) throws {
        guard let rootURL = rootURL else { throw ArchiveError.missingRoot }
        stats.visited += 1
        let rawPath = try relativePath(target.logicalURL, to: rootURL)
        let path = try archiveDisplayPath(rawPath, target: target)

        if isSymbolicLink(target.logicalURL) && emittedSymlinks.insert(rawPath).inserted {
            if options.jsonLines {
                try writeJSON([
                    "type": "symlink",
                    "path": rawPath,
                    "resolvedPath": target.resolvedPath
                ])
            } else {
                writeText("@symlink \(archiveQuote(rawPath, separator: options.archiveSeparator))\t\(archiveQuote(target.resolvedPath, separator: options.archiveSeparator))")
            }
            stats.emitted += 1
        }

        guard !tags.isEmpty else { return }
        stats.tagged += 1
        var exportedTags = tags
        if options.reverse { exportedTags.reverse() }
        let metadata = options.fileInfo ? try fileMetadata(for: target.url) : nil
        if options.jsonLines {
            var object: [String: Any] = ["path": rawPath, "tags": exportedTags]
            if let metadata = metadata {
                object["size"] = metadata.size
                object["mtime"] = metadata.modificationTime
            }
            try writeJSON(object)
        } else {
            if let metadata = metadata {
                writeText("@metadata \(archiveQuote(rawPath, separator: options.archiveSeparator))\t\(metadata.size)\t\(metadata.modificationTime)")
            }
            let renderedTags = exportedTags
                .map(colors.render)
                .map { archiveQuote($0, separator: options.archiveSeparator) }
                .joined(separator: ",")
            let separator = options.spaceIndent ? "  " : "\t"
            writeText("\(archiveQuote(path, separator: options.archiveSeparator, always: true))\(separator)\(renderedTags)")
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

    private func archiveDisplayPath(_ path: String, target: Target) throws -> String {
        guard options.slashDirectories, path != "." else { return path }
        let values = try target.url.resourceValues(forKeys: [.isDirectoryKey])
        guard values.isDirectory == true else { return path }
        return path.hasSuffix("/") ? path : path + "/"
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

private func archiveHeaderObject(
    encoding: ArchiveEncoding,
    separator: Character,
    reverse: Bool,
    slashDirectories: Bool,
    spaceIndent: Bool,
    fileInfo: Bool
) -> [String: Any] {
    return [
        "type": "header",
        "format": encoding.rawValue,
        "version": archiveFormatVersion,
        "separator": String(separator),
        "reverse": reverse,
        "slash": slashDirectories,
        "spaceIndent": spaceIndent,
        "fileInfo": fileInfo
    ]
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
        let renderedTags = tags.map(archiveQuote).joined(separator: ",")
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
        let header = archiveHeaderObject(
            encoding: .plain,
            separator: "\"",
            reverse: false,
            slashDirectories: false,
            spaceIndent: false,
            fileInfo: false
        )
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        file.write(headerData)
        file.write(Data("\n@root /\n".utf8))
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
