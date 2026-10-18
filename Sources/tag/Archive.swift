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
    let colors: [Int?]?

    var storedTags: [StoredTag]? {
        tags.map { names in
            names.enumerated().map { index, name in
                StoredTag(name: name, color: colors?[index])
            }
        }
    }
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
    var skipped = 0
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
    case symlinkAncestor(String)
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
        case let .symlinkAncestor(path):
            return "restore path traverses a parent symlink in no-follow mode: \(path)"
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
        guard rawPath.utf8.first == 47, !rawPath.utf8.contains(0) else {
            throw ArchiveError.invalidRoot(rawPath)
        }
        guard rootPath == nil else { throw ArchiveError.multipleRoots }
        rootPath = expandedFileURL(rawPath).path
    }

    mutating func addItem(_ item: ArchiveItem) throws {
        try validateRelativeArchivePath(item.path)
        if !itemPaths.insert(item.path).inserted && header?.purpose != "undo" {
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
    var onWarning: (String) -> Void = reportWarning

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
        let document = try builder.document()
        if document.header.purpose == "export" && !sawSummary {
            throw ArchiveError.invalidLine(line: lines.count, message: "incomplete export archive: missing final summary")
        }
        return document
    }

    private func parseItem(_ object: [String: Any], line: Int) throws -> ArchiveItem {
        guard let path = object["path"] as? String else {
            throw ArchiveError.invalidLine(line: line, message: "item lacks string path")
        }
        guard let kindValue = object["kind"] as? String,
              let kind = ArchiveItemKind(rawValue: kindValue) else {
            throw ArchiveError.invalidLine(line: line, message: "item has an invalid kind")
        }

        let rawTags: [Any]?
        if let value = object["tags"] {
            guard let values = value as? [Any] else {
                throw ArchiveError.invalidLine(line: line, message: "tags is not an array")
            }
            rawTags = values
        } else {
            rawTags = nil
        }
        // Validate alignment against the original entries, then filter names
        // and their colors together. An empty name must not shift later colors.
        let rawColors = try archiveItemColors(object["colors"], tagCount: rawTags?.count, line: line)
        let parsedTags = rawTags?.enumerated().compactMap { index, value -> StoredTag? in
            let warn = { (message: String) in
                onWarning("archive line \(line), item '\(path)', tag \(index): \(message)")
            }
            let text = tagNameText(value, onWarning: warn)
            guard let name = repairedTagName(text, onWarning: warn) else { return nil }
            return StoredTag(name: name, color: rawColors?[index])
        }
        let tags = parsedTags?.map { $0.name }
        let colors = rawColors == nil ? nil : parsedTags?.map { $0.color }

        let metadata = try jsonMetadata(object, line: line)
        let destination: String?
        if let value = object["destination"] {
            guard let string = value as? String else {
                throw ArchiveError.invalidLine(line: line, message: "destination must be a string")
            }
            destination = string
        } else {
            destination = nil
        }
        let targetExists: Bool?
        if let value = object["targetExists"] {
            targetExists = try archiveBoolean(value, field: "targetExists", line: line)
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
            symlinkTargetKind: targetKind,
            colors: colors
        )
    }

    private func jsonMetadata(_ object: [String: Any], line: Int) throws -> FileMetadata? {
        guard object["size"] != nil || object["mtime"] != nil else { return nil }
        guard let size = archiveInteger(object["size"]), size >= 0,
              let mtime = archiveFiniteNumber(object["mtime"]) else {
            throw ArchiveError.invalidLine(line: line, message: "size must be a nonnegative integer and mtime a finite number")
        }
        return FileMetadata(size: Int64(size), modificationTime: mtime)
    }
}

final class ArchiveWriter {
    private let options: Options
    private var rootURL: URL?
    private var didEmitRoot = false

    var stats = ArchiveStats()

    init(options: Options) {
        self.options = options
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
            excludePatterns: options.excludePatterns,
            tagColors: []
        ))
        try writeJSON(["type": "root", "path": rootURL!.path])
    }

    func emitTarget(_ target: Target, tags: [StoredTag]?, metadata: FileMetadata?) throws {
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
            object["tags"] = tags.map { $0.name }
            object["colors"] = tagColorNumbers(tags)
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
        guard let path = relativeLogicalPath(logicalURL, to: rootURL) else {
            throw ArchiveError.invalidPath(logicalURL.path)
        }
        return path
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
    private var handle: FileHandle?

    init(path: String, syncEachRecord: Bool, followSymlinks: Bool) {
        self.path = path
        self.syncEachRecord = syncEachRecord
        self.followSymlinks = followSymlinks
    }

    func record(target: Target, tags: [StoredTag]) throws {
        try openIfNeeded()
        // The preimage belongs to the file edited, even when an operand or a
        // parent directory is a symlink. Later retargeting must not redirect undo.
        let ioURL = resolvedTagURL(target.url)
        let absolute = ioURL.path
        let path = absolute == "/" ? "." : String(decoding: absolute.utf8.dropFirst(), as: UTF8.self)
        let object: [String: Any] = [
            "type": "item",
            "path": path,
            "kind": try itemKind(for: ioURL).rawValue,
            "tags": tags.map { $0.name },
            "colors": tagColorNumbers(tags)
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
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(0o600))
        guard descriptor >= 0 else {
            if errno == EEXIST { throw ArchiveIOError.alreadyExists(path: url.path) }
            throw ArchiveIOError.cannotCreate(path: url.path)
        }
        let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        handle = file
        let header = archiveHeaderObject(
            purpose: "undo",
            followSymlinks: followSymlinks,
            fileInfo: false,
            taggedOnly: false,
            excludePatterns: [],
            tagColors: []
        )
        let headerData = try JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])
        file.write(headerData)
        file.write(Data("\n{\"path\":\"/\",\"type\":\"root\"}\n".utf8))
        if syncEachRecord && fsync(file.fileDescriptor) != 0 {
            throw ArchiveIOError.syncFailed(path: path, reason: String(cString: strerror(errno)))
        }
        eprint("\(programName): undo archive: \(url.path)")
    }

    private func itemKind(for url: URL) throws -> ArchiveItemKind {
        return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
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
