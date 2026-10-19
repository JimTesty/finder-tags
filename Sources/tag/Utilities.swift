import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let programName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
let programVersion = "9.0"
let fileManager = FileManager.default

func eprint(_ message: String) {
    FileHandle.standardError.write(Data((escapedDisplayText(message) + "\n").utf8))
}

func reportWarning(_ message: String) {
    Diagnostics.warning(message)
}

func reportError(_ message: String) {
    Diagnostics.error(message)
}

func fileMetadata(for url: URL) throws -> FileMetadata {
    let values = try url.resourceValues(forKeys: [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
    ])
    guard let date = values.contentModificationDate else {
        throw NSError(domain: "finder-tags", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "file size or modification time is unavailable"
        ])
    }
    guard let isDirectory = values.isDirectory else {
        throw NSError(domain: "finder-tags", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "file type is unavailable"
        ])
    }
    let size = isDirectory ? 0 : values.fileSize ?? -1
    guard size >= 0 else {
        throw NSError(domain: "finder-tags", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "file size is unavailable"
        ])
    }
    return FileMetadata(
        size: Int64(size),
        modificationTime: date.timeIntervalSince1970,
        isDirectory: isDirectory
    )
}

func fileMetadata(for target: Target) throws -> FileMetadata {
    // Foundation may return tags from an existing symlink's target even
    // without -L. Use the same referent for displayed and archived file-info,
    // so a symlink's tags are not paired with the link's own byte length and
    // timestamp. -L still controls traversal and structural symlink metadata.
    // A missing referent falls back to the link itself, just like tag display.
    if let link = try symbolicLinkInfo(for: target.logicalURL) {
        if let error = link.targetInspectionError { throw error }
        if link.targetIsMissing {
            var info = stat()
            guard lstat(target.logicalURL.path, &info) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                    NSFilePathErrorKey: target.logicalURL.path
                ])
            }
            #if canImport(Darwin)
            let time = info.st_mtimespec
            #else
            let time = info.st_mtim
            #endif
            return FileMetadata(
                size: Int64(info.st_size),
                modificationTime: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
            )
        }
        return try fileMetadata(for: resolvedTagURL(link.targetURL))
    }
    return try fileMetadata(for: target.url)
}

func fail(_ message: String, code: Int32 = ExitCode.usage) -> Never {
    reportError(message)
    exit(code)
}

func expandedFileURL(_ path: String) -> URL {
    return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
}

func argumentFileURL(_ path: String, resolveSymlinks: Bool) throws -> URL {
    let url = expandedFileURL(path)
    guard resolveSymlinks, try checkedSymbolicLink(url) else { return url }

    let resolvedURL = resolvedTagURL(url)
    return try checkedPathExists(resolvedURL, followSymlinks: true) ? resolvedURL : url
}

func resolvedTagURL(_ url: URL) -> URL {
    return url.resolvingSymlinksInPath().standardizedFileURL
}

func tagIOURL(_ logicalURL: URL, followSymlinks: Bool) -> URL {
    return followSymlinks ? resolvedTagURL(logicalURL) : logicalURL.standardizedFileURL
}

// Filesystem separators must be compared as bytes, independently of graphemes
// such as a slash followed by a combining character.
func relativeLogicalPath(_ url: URL, to rootURL: URL) -> String? {
    let path = url.standardizedFileURL.path
    let root = rootURL.standardizedFileURL.path
    if path.utf8.elementsEqual(root.utf8) { return "." }
    let prefix = root.hasSuffix("/") ? root : root + "/"
    guard path.utf8.starts(with: prefix.utf8) else { return nil }
    return String(decoding: path.utf8.dropFirst(prefix.utf8.count), as: UTF8.self)
}

struct SymbolicLinkInfo {
    let destination: String
    let targetURL: URL
    let targetExists: Bool?
    let targetIsDirectory: Bool?
    let targetInspectionError: Error?

    var targetIsMissing: Bool { targetExists == false }
}

func symbolicLinkInfo(for url: URL) throws -> SymbolicLinkInfo? {
    guard try checkedItemKind(for: url) == .symlink else { return nil }
    let destination = try fileManager.destinationOfSymbolicLink(atPath: url.path)

    let targetURL: URL
    if destination.hasPrefix("/") {
        targetURL = URL(fileURLWithPath: destination).standardizedFileURL
    } else {
        targetURL = url.deletingLastPathComponent()
            .appendingPathComponent(destination)
            .standardizedFileURL
    }

    do {
        let kind = try checkedItemKind(for: targetURL, followSymlinks: true)
        return SymbolicLinkInfo(
            destination: destination, targetURL: targetURL, targetExists: true,
            targetIsDirectory: kind == .directory, targetInspectionError: nil
        )
    } catch {
        let missing = isMissingPathError(error)
        return SymbolicLinkInfo(
            destination: destination, targetURL: targetURL,
            targetExists: missing ? false : nil, targetIsDirectory: nil,
            targetInspectionError: missing ? nil : error
        )
    }
}

func isMissingPathError(_ error: Error) -> Bool {
    let error = error as NSError
    return error.domain == NSPOSIXErrorDomain && (error.code == Int(ENOENT) || error.code == Int(ENOTDIR))
}

func checkedItemKind(for url: URL, followSymlinks: Bool = false) throws -> ArchiveItemKind {
    var info = stat()
    let status = followSymlinks ? stat(url.path, &info) : lstat(url.path, &info)
    guard status == 0 else {
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
    switch info.st_mode & mode_t(S_IFMT) {
    case mode_t(S_IFLNK): return .symlink
    case mode_t(S_IFDIR): return .directory
    default: return .file
    }
}

func checkedPathExists(_ url: URL, followSymlinks: Bool = false) throws -> Bool {
    do {
        _ = try checkedItemKind(for: url, followSymlinks: followSymlinks)
        return true
    } catch {
        if isMissingPathError(error) { return false }
        throw error
    }
}

func checkedSymbolicLink(_ url: URL) throws -> Bool {
    do {
        return try checkedItemKind(for: url) == .symlink
    } catch {
        // Missing parents are handled as missing items by restore. Other
        // inspection failures must not bypass its parent-symlink check.
        if isMissingPathError(error) { return false }
        throw error
    }
}

func readPathsFromStdin(_ mode: StdinPathMode) -> [String] {
    let data: Data
    do {
        data = try FileHandle.standardInput.readToEnd() ?? Data()
    } catch {
        fail("reading stdin paths: \(error.localizedDescription)", code: ExitCode.ioError)
    }
    let separator: UInt8
    switch mode {
    case .lines: separator = 10
    case .nul: separator = 0
    }

    var result: [String] = []
    var start = data.startIndex
    var record = 1
    func appendPath(_ bytes: Data.SubSequence, terminated: Bool) {
        // Only CR immediately before an LF belongs to a CRLF terminator.
        let bytes = separator == 10 && terminated && bytes.last == 13 ? bytes.dropLast() : bytes
        if bytes.isEmpty { return }
        let path = String(decoding: bytes, as: UTF8.self)
        // Replacement decoding is usable only if it preserved every byte.
        // Compare UTF-8 bytes rather than Unicode-equivalent String values.
        guard path.utf8.elementsEqual(bytes) else {
            fail("stdin path record \(record) is not valid UTF-8; no files were processed")
        }
        guard !bytes.contains(0) else {
            fail("stdin path record \(record) contains a NUL byte; use --stdin0 for NUL-delimited paths")
        }
        result.append(path)
    }
    for index in data.indices where data[index] == separator {
        appendPath(data[start..<index], terminated: true)
        start = data.index(after: index)
        record += 1
    }
    appendPath(data[start..<data.endIndex], terminated: false)
    return result
}
