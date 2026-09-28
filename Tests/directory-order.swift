import Foundation

// Independent reference for native enumeration order on this filesystem.
// Test fixtures contain ordinary files and directories, without symlinks.
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let recursive = CommandLine.arguments.dropFirst(2).contains("--recursive")

func printDirectory(_ directory: URL, prefix: String = "") throws {
    let entries = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .tagNamesKey],
        options: []
    )
    for entry in entries {
        let path = prefix + entry.lastPathComponent
        print(path)
        if recursive, try entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true {
            try printDirectory(entry, prefix: path + "/")
        }
    }
}

try printDirectory(root)
