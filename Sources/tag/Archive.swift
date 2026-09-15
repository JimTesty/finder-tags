import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum ArchiveItemKind: String {
    case file
    case directory
    case symlink
}

struct ArchiveItem {
    let path: String
    let kind: ArchiveItemKind
    // nil means that tags were unavailable and must not be changed on restore.
    // An empty array means that tags were explicitly observed to be absent.
    let tags: [String]?
    let metadata: FileMetadata?
    let symlinkDestination: String?
    let symlinkTargetExists: Bool?
    let symlinkTargetKind: ArchiveItemKind?
}

struct ArchiveDocument {
    let rootPath: String
    let header: ArchiveHeader
    let items: [ArchiveItem]
}

struct ArchiveStats {
    var visited = 0
    var tagged = 0
    var emitted = 0
    var errors = 0
    var unchanged = 0
    var changed = 0
    var restored = 0
    var cleared = 0
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
    case invalidTags(String)
    case invalidHeader(String)
    case unsupportedRecord(String)
    case invalidSymlink(String)
    case modeMismatch(archive: Bool, requested: Bool)

    var errorDescription: String? {
        switch self {
        case let .invalidLine(line, message):
            return "archive line \(line): \(message)"
        case .missingRoot:
            return "archive has no root record"
        case .multipleRoots:
            return "archive contains multiple roots; only one root is accepted"
        case let .invalidRoot(path):
            return "archive root is not an absolute path: \(path)"
        case let .invalidPath(path):
            return "invalid archive item path: \(path)"
        case let .duplicatePath(path):
            return "duplicate archive item: \(path)"
        case let .invalidTags(value):
            return "invalid archive tag: \(value)"
        case let .invalidHeader(value):
            return "invalid archive header: \(value)"
        case let .unsupportedRecord(type):
            return "unsupported archive record type: \(type)"
        case let .invalidSymlink(path):
            return "invalid archive symlink metadata: \(path)"
        case let .modeMismatch(archive, requested):
            return "archive follow-symlinks mode is \(archive ? "enabled" : "disabled"), "
                + "but restore requested \(requested ? "enabled" : "disabled"); "
                + "use the matching -L setting"
        }
    }
}

private struct ArchiveBuilder {
    var rootPath: String?
    var header: ArchiveHeader?
    var items: [ArchiveItem] = []
    var itemPaths = Set<String>()

    mutating func setHeader(_ newHeader: ArchiveHeader) throws {
        guard header == nil else {
            throw ArchiveError.invalidHeader("multiple header records")
        }
        guard items.isEmpty, rootPath == nil else {
            throw ArchiveError.invalidHeader("header must precede archive records")
        }
        header = newHeader
    }

    mutating func setRoot(_ rawPath: String) throws {
        guard rawPath.hasPrefix("/"), !rawPath.unicodeScalars.contains("\0") else {
            throw ArchiveError.invalidRoot(rawPath)
        }
        guard rootPath == nil else { throw ArchiveError.multipleRoots }
        rootPath = expandedFileURL(rawPath).path
    }

    mutating func addItem(_ item: ArchiveItem) throws {
        try validateRelativeArchivePath(item.path)
        guard itemPaths.insert(item.path).inserted else {
            throw ArchiveError.duplicatePath(item.path)
        }
        if let tags = item.tags {
            for tag in tags { try validateArchiveTag(tag) }
        }
        if item.kind == .symlink {
            if let destination = item.symlinkDestination,
               destination.unicodeScalars.contains("\0") {
                throw ArchiveError.invalidSymlink(item.path)
            }
            if item.symlinkTargetKind != nil && item.symlinkTargetExists != true {
                throw ArchiveError.invalidSymlink(item.path)
            }
            if let targetKind = item.symlinkTargetKind,
               targetKind == .symlink {
                throw ArchiveError.invalidSymlink(item.path)
            }
        } else if item.symlinkDestination != nil
                    || item.symlinkTargetExists != nil
                    || item.symlinkTargetKind != nil {
            throw ArchiveError.invalidSymlink(item.path)
        }
        items.append(item)
    }

    func document() throws -> ArchiveDocument {
        guard let rootPath = rootPath else { throw ArchiveError.missingRoot }
        guard let header = header else {
            throw ArchiveError.invalidHeader("missing header record")
        }
        if !header.followSymlinks {
            for item in items where item.symlinkDestination != nil
                || item.symlinkTargetExists != nil
                || item.symlinkTargetKind != nil {
                throw ArchiveError.invalidSymlink(item.path)
            }
        }
        return ArchiveDocument(rootPath: rootPath, header: header, items: items)
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

        var builder = ArchiveBuilder()
        var sawHeader = false
        var sawSummary = false
        let lines = text.components(separatedBy: "\n")

        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            var line = rawLine
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
            guard let type = object["type"] as? String else {
                throw ArchiveError.invalidLine(line: lineNumber, message: "record lacks type")
            }

            if type == "header" {
                guard !sawHeader else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "multiple archive headers")
                }
                try builder.setHeader(try archiveHeader(from: object, line: lineNumber))
                sawHeader = true
                continue
            }
            guard sawHeader else {
                throw ArchiveError.invalidLine(line: lineNumber, message: "archive header must be first")
            }
            if type == "summary" {
                guard !sawSummary else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "multiple summary records")
                }
                sawSummary = true
                continue
            }
            if sawSummary {
                throw ArchiveError.invalidLine(line: lineNumber, message: "records cannot follow summary")
            }

            switch type {
            case "root":
                guard let path = object["path"] as? String else {
                    throw ArchiveError.invalidLine(line: lineNumber, message: "root record lacks string path")
                }
                try builder.setRoot(path)
            case "item":
                try builder.addItem(parseItem(object, line: lineNumber))
            default:
                throw ArchiveError.unsupportedRecord(type)
            }
        }

        guard sawHeader else {
            throw ArchiveError.invalidLine(line: 1, message: "missing JSON archive header")
        }
        return try builder.document()
    }

    private func parseItem(_ object: [String: Any], line: Int) throws -> ArchiveItem {
        guard let path = object["path"] as? String else {
            throw ArchiveError.invalidLine(line: line, message: "item lacks string path")
        }
        guard let kindValue = object["kind"] as? String,
              let kind = ArchiveItemKind(rawValue: kindValue) else {
            throw ArchiveError.invalidLine(line: line, message: "item has an invalid kind")
        }

        let tags: [String]?
        if let rawTags = object["tags"] {
            guard let values = rawTags as? [Any] else {
                throw ArchiveError.invalidLine(line: line, message: "tags is not an array")
            }
            var parsed: [String] = []
            for value in values {
                guard let tag = value as? String else {
                    throw ArchiveError.invalidLine(line: line, message: "tags must contain only strings")
                }
                parsed.append(tag)
            }
            tags = parsed
        } else {
            tags = nil
        }

        let metadata = try jsonMetadata(object, line: line)
        let destination = object["destination"] as? String
        let targetExists: Bool?
        if let value = object["targetExists"] {
            guard let bool = value as? Bool else {
                throw ArchiveError.invalidLine(line: line, message: "targetExists must be boolean")
            }
            targetExists = bool
        } else {
            targetExists = nil
        }
        let targetKind: ArchiveItemKind?
        if let value = object["targetKind"] {
            guard let string = value as? String,
                  let parsed = ArchiveItemKind(rawValue: string),
                  parsed != .symlink else {
                throw ArchiveError.invalidLine(line: line, message: "targetKind is invalid")
            }
            targetKind = parsed
        } else {
            targetKind = nil
        }

        return ArchiveItem(
            path: path,
            kind: kind,
            tags: tags,
            metadata: metadata,
            symlinkDestination: destination,
            symlinkTargetExists: targetExists,
            symlinkTargetKind: targetKind
        )
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
}

final class ArchiveWriter {
    private let options: Options
    private let colors: FinderColors
    private var rootURL: URL?
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
            purpose: "export",
            followSymlinks: options.followSymlinks,
            fileInfo: options.fileInfo,
            taggedOnly: options.taggedOnly,
            tagColors: colors.archiveTagColors
        ))
        try writeJSON(["type": "root", "path": rootURL!.path])
    }

    func emitTarget(_ target: Target, tags: [String]?, metadata: FileMetadata?) throws {
        guard let rootURL = rootURL else { throw ArchiveError.missingRoot }
        stats.visited += 1
        let path = try relativePath(target.logicalURL, to: rootURL)

        if options.taggedOnly && (tags == nil || tags!.isEmpty) { return }

        let isSymlink = isSymbolicLink(target.logicalURL)
        let kind: ArchiveItemKind
        if isSymlink {
            kind = .symlink
        } else {
            let values = try target.url.resourceValues(forKeys: [.isDirectoryKey])
            kind = values.isDirectory == true ? .directory : .file
        }

        var object: [String: Any] = [
            "type": "item",
            "path": path,
            "kind": kind.rawValue
        ]
        if let tags = tags {
            object["tags"] = tags
            if !tags.isEmpty { stats.tagged += 1 }
        }
        if let metadata = metadata {
            object["size"] = metadata.size
            object["mtime"] = metadata.modificationTime
        }

        if kind == .symlink && options.followSymlinks,
           let link = symbolicLinkInfo(for: target.logicalURL) {
            object["destination"] = link.destination
            object["targetExists"] = link.targetExists
            if link.targetExists {
                object["targetKind"] = link.targetIsDirectory ? ArchiveItemKind.directory.rawValue : ArchiveItemKind.file.rawValue
            }
        }

        try writeJSON(object)
        stats.emitted += 1
    }

    func noteWarning() {
        stats.warnings += 1
    }

    func finish() throws {
        try writeJSON([
            "type": "summary",
            "operation": "export",
            "visited": stats.visited,
            "tagged": stats.tagged,
            "emitted": stats.emitted,
            "errors": stats.errors,
            "warnings": stats.warnings
        ])
        eprint("\(programName): exported \(stats.tagged) tagged items (\(stats.visited) visited, \(stats.emitted) records, \(stats.errors) errors, \(stats.warnings) warnings)")
    }

    private func relativePath(_ logicalURL: URL, to rootURL: URL) throws -> String {
        let root = rootURL.standardizedFileURL.path
        let logical = logicalURL.standardizedFileURL.path
        if logical == root { return "." }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        guard logical.hasPrefix(prefix) else { throw ArchiveError.invalidPath(logical) }
        return String(logical.dropFirst(prefix.count))
    }

    private func writeJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

final class UndoWriter {
    let path: String
    private let syncEachRecord: Bool
    private let followSymlinks: Bool
    private let tagColors: [TagColorInfo]
    private var handle: FileHandle?

    init(path: String, syncEachRecord: Bool, followSymlinks: Bool, tagColors: [TagColorInfo]) {
        self.path = path
        self.syncEachRecord = syncEachRecord
        self.followSymlinks = followSymlinks
        self.tagColors = tagColors
    }

    func record(target: Target, tags: [String]) throws {
        try openIfNeeded()
        let absolute = target.logicalURL.standardizedFileURL.path
        let path = absolute == "/" ? "." : String(absolute.dropFirst())
        let object: [String: Any] = [
            "type": "item",
            "path": path,
            "kind": itemKind(for: target).rawValue,
            "tags": tags
        ]
        if let handle = handle {
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            handle.write(data)
            handle.write(Data([10]))
            if syncEachRecord && fsync(handle.fileDescriptor) != 0 {
                throw ArchiveIOError.syncFailed(path: path, reason: String(cString: strerror(errno)))
            }
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
        guard fileManager.createFile(atPath: url.path, contents: nil, attributes: nil),
              let file = FileHandle(forWritingAtPath: url.path) else {
            throw ArchiveIOError.cannotCreate(path: url.path)
        }
        handle = file
        let header = archiveHeaderObject(
            purpose: "undo",
            followSymlinks: followSymlinks,
            fileInfo: false,
            taggedOnly: false,
            tagColors: tagColors
        )
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        file.write(headerData)
        file.write(Data("\n{\"path\":\"/\",\"type\":\"root\"}\n".utf8))
        if syncEachRecord && fsync(file.fileDescriptor) != 0 {
            throw ArchiveIOError.syncFailed(path: path, reason: String(cString: strerror(errno)))
        }
        eprint("\(programName): undo archive: \(url.path)")
    }

    private func itemKind(for target: Target) -> ArchiveItemKind {
        if isSymbolicLink(target.logicalURL) { return .symlink }
        return (try? target.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            ? .directory
            : .file
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
        "finder-tags-undo-\(identifier).jsonl"
    ).path
}
