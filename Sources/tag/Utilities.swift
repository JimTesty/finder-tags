import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

let programName = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent
let fileManager = FileManager.default

func eprint(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func fail(_ message: String, code: Int32 = ExitCode.usage) -> Never {
    eprint("\(programName): \(message)")
    exit(code)
}

func canonicalTag(_ tag: String) -> String {
    // Finder-style tag comparison is case-insensitive. Locale-independent
    // folding avoids surprising behavior when the user's locale changes.
    tag.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
}

func parseTagList(_ raw: String) -> [String] {
    var seen = Set<String>()
    var result: [String] = []

    for piece in raw.split(separator: ",", omittingEmptySubsequences: false) {
        let tag = piece.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { continue }

        if seen.insert(canonicalTag(tag)).inserted {
            result.append(tag)
        }
    }
    return result
}

func expandedFileURL(_ path: String) -> URL {
    URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
}
