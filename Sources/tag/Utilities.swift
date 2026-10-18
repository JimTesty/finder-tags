import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let programName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
let programVersion = "8.0"
let fileManager = FileManager.default

func eprint(_ message: String) {
    FileHandle.standardError.write(Data((escapedDisplayText(message) + "\n").utf8))
}

func reportWarning(_ message: String) {
    eprint("\(programName): warning: \(message)")
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
    let isDirectory = values.isDirectory == true
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
    if let link = symbolicLinkInfo(for: target.logicalURL) {
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
    eprint("\(programName): \(message)")
    exit(code)
}

func expandedFileURL(_ path: String) -> URL {
    return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
}

func argumentFileURL(_ path: String, resolveSymlinks: Bool) -> URL {
    let url = expandedFileURL(path)
    guard resolveSymlinks, isSymbolicLink(url) else { return url }

    let resolvedURL = resolvedTagURL(url)
    return fileManager.fileExists(atPath: resolvedURL.path) ? resolvedURL : url
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
    let targetExists: Bool
    let targetIsMissing: Bool
    let targetIsDirectory: Bool
}

func symbolicLinkInfo(for url: URL) -> SymbolicLinkInfo? {
    guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
        return nil
    }

    let targetURL: URL
    if destination.hasPrefix("/") {
        targetURL = URL(fileURLWithPath: destination).standardizedFileURL
    } else {
        targetURL = url.deletingLastPathComponent()
            .appendingPathComponent(destination)
            .standardizedFileURL
    }

    var info = stat()
    let exists = stat(targetURL.path, &info) == 0
    // Permission failures and loops must not masquerade as missing targets.
    let isMissing = !exists && (errno == ENOENT || errno == ENOTDIR)
    let isDirectory = exists && info.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
    return SymbolicLinkInfo(
        destination: destination,
        targetURL: targetURL,
        targetExists: exists,
        targetIsMissing: isMissing,
        targetIsDirectory: isDirectory
    )
}

func isSymbolicLink(_ url: URL) -> Bool {
    // destinationOfSymbolicLink is an lstat-like question: it succeeds only
    // when the path itself is a symbolic link, without relying on resource
    // values that may describe the referent.
    return (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
}

func checkedSymbolicLink(_ url: URL) throws -> Bool {
    var info = stat()
    guard lstat(url.path, &info) == 0 else {
        // Missing parents are handled as missing items by restore. Other
        // inspection failures must not bypass its parent-symlink check.
        if errno == ENOENT || errno == ENOTDIR { return false }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
    return info.st_mode & mode_t(S_IFMT) == mode_t(S_IFLNK)
}

func readPathsFromStdin(_ mode: StdinPathMode) -> [String] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if data.isEmpty { return [] }

    switch mode {
    case .lines:
        let text = String(decoding: data, as: UTF8.self)
        return text.unicodeScalars.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map(String.init)
    case .nul:
        var result: [String] = []
        var start = data.startIndex
        var index = start
        while index < data.endIndex {
            if data[index] == 0 {
                if start < index {
                    result.append(String(decoding: data[start..<index], as: UTF8.self))
                }
                start = data.index(after: index)
            }
            index = data.index(after: index)
        }
        if start < data.endIndex {
            result.append(String(decoding: data[start..<data.endIndex], as: UTF8.self))
        }
        return result
    }
}
