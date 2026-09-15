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
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func stdoutIsTerminal() -> Bool {
    return isatty(STDOUT_FILENO) == 1
}

func colorIsEnabled(_ mode: ColorMode) -> Bool {
    switch mode {
    case .auto: return stdoutIsTerminal()
    case .always: return true
    case .never: return false
    }
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
    let size = values.isDirectory == true ? 0 : values.fileSize ?? -1
    guard size >= 0 else {
        throw NSError(domain: "finder-tags", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "file size is unavailable"
        ])
    }
    return FileMetadata(size: Int64(size), modificationTime: date.timeIntervalSince1970)
}

func fileMetadata(for target: Target) throws -> FileMetadata {
    // Foundation's Finder-tag lookup may follow an existing symlink even
    // without -L. Use the same referent for displayed and archived file-info,
    // so a symlink's tags are not paired with the link's own byte length and
    // timestamp. -L still controls traversal and structural symlink metadata.
    let url = isSymbolicLink(target.logicalURL)
        ? resolvedTagURL(target.logicalURL)
        : target.url
    return try fileMetadata(for: url)
}

func fail(_ message: String, code: Int32 = ExitCode.usage) -> Never {
    eprint("\(programName): \(message)")
    exit(code)
}

func expandedFileURL(_ path: String) -> URL {
    return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
}

func resolvedTagURL(_ url: URL) -> URL {
    return url.resolvingSymlinksInPath().standardizedFileURL
}

func tagIOURL(_ logicalURL: URL, followSymlinks: Bool) -> URL {
    return followSymlinks ? resolvedTagURL(logicalURL) : logicalURL.standardizedFileURL
}

struct SymbolicLinkInfo {
    let destination: String
    let targetURL: URL
    let targetExists: Bool
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

    let exists = fileManager.fileExists(atPath: targetURL.path)
    let isDirectory = (try? targetURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    return SymbolicLinkInfo(
        destination: destination,
        targetURL: targetURL,
        targetExists: exists,
        targetIsDirectory: isDirectory
    )
}

func isSymbolicLink(_ url: URL) -> Bool {
    // destinationOfSymbolicLink is an lstat-like question: it succeeds only
    // when the path itself is a symbolic link, without relying on resource
    // values that may describe the referent.
    return (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
}

func formattedPath(
    for target: Target,
    slash: Bool,
    printSymlink: Bool,
    colors: FinderColors
) throws -> String {
    var path = target.displayPath

    if isSymbolicLink(target.logicalURL) {
        if slash { path += "@" }
        if printSymlink, let link = symbolicLinkInfo(for: target.logicalURL) {
            var destination = link.destination
            if slash && link.targetExists && link.targetIsDirectory && !destination.hasSuffix("/") {
                destination += "/"
            }
            path += " -> " + destination
            if !link.targetExists {
                path += " " + colors.renderMissing("(NOT FOUND)")
            }
        }
        return path
    }

    guard slash else { return path }
    let values = try target.url.resourceValues(forKeys: [.isDirectoryKey])
    if values.isDirectory == true && !path.hasSuffix("/") {
        path += "/"
    }
    return path
}

func readPathsFromStdin(_ mode: StdinPathMode) -> [String] {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    if data.isEmpty { return [] }

    switch mode {
    case .lines:
        let text = String(decoding: data, as: UTF8.self)
        return text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).map(String.init)
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
