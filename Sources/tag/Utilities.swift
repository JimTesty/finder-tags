import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let programName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
let programVersion = "4.1"
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

func canonicalTag(_ tag: String) -> String {
    tag.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
}

func parseTagList(_ raw: String) -> [String] {
    var seen = Set<String>()
    var result: [String] = []

    for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
        let tag = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        if tag.isEmpty { continue }

        if seen.insert(canonicalTag(tag)).inserted {
            result.append(tag)
        }
    }
    return result
}

func expandedFileURL(_ path: String) -> URL {
    return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
}

func tagsMatch(_ stored: [String], query: [String]) -> Bool {
    if query.contains("*") { return !stored.isEmpty }
    if query.isEmpty { return stored.isEmpty }

    let present = Set(stored.map(canonicalTag))
    for tag in query {
        if !present.contains(canonicalTag(tag)) { return false }
    }
    return true
}
