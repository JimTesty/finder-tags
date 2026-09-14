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

func isSymbolicLink(_ url: URL) -> Bool {
    // destinationOfSymbolicLink is an lstat-like question: it succeeds only
    // when the path itself is a symbolic link, without relying on resource
    // values that may describe the referent.
    return (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
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
