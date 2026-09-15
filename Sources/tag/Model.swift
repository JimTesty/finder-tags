import Foundation

enum PositionSpec: Equatable {
    case first
    case last
    case index(Int)
    case before(String)
    case after(String)
}

enum Operation {
    case list
    case export
    case restore
    case convert
    case add([String])
    case remove([String])
    case set([String])
    case copy
    case match([String])
    case usage([String])
    case find([String])
    case move(String, PositionSpec?)

}

enum StdinPathMode {
    case lines
    case nul
}

enum ColorMode {
    case auto
    case always
    case never
}

struct FileMetadata {
    let size: Int64
    let modificationTime: Double
}

struct Options {
    var operation: Operation = .list
    var operationWasSet = false

    var colorMode: ColorMode = .never
    var reverse = false
    var reverseWasSet = false
    var sortedTags = false
    var caseSensitive = false
    var showNamesOverride: Bool? = nil
    var showTagsOverride: Bool? = nil
    var oneTagPerLine = false
    var spaceIndent = false
    var includeHidden = false
    var enterDirectories = false
    var recursive = false
    var slashDirectories = false
    var nulTerminate = false
    var jsonLines = false
    var dryRun = false
    var taggedOnly = false
    var fileInfo = false
    var fileInfoWasSet = false
    var archivePath: String? = nil
    var restoreRoot: String? = nil
    var backupEnabled = true
    var backupPath: String? = nil
    var syncBackup = false
    var position: PositionSpec? = nil
    var absolutePaths = false
    var followSymlinks = false
    var printSymlinks = false
    var stdinPathMode: StdinPathMode? = nil
    var pathInputExplicit = false

    var paths: [String] = []

    var showNames: Bool {
        if let value = showNamesOverride { return value }
        switch operation {
        case .list, .match, .find, .convert: return true
        default: return false
        }
    }

    var showTags: Bool {
        if let value = showTagsOverride { return value }
        switch operation {
        case .list, .convert: return true
        case .match, .find: return false
        default: return false
        }
    }

    var isMutating: Bool {
        switch operation {
        case .add, .remove, .set, .copy, .move, .restore: return true
        default: return false
        }
    }
}

struct Target {
    // url is the URL used for tag I/O. It is symlink-resolved only with -L.
    // logicalURL preserves the user's filesystem path for output/provenance.
    let url: URL
    let logicalURL: URL
    let displayPath: String
    let rootPath: String?

    var absolutePath: String { return logicalURL.standardizedFileURL.path }
}

struct TagChange {
    let before: [String]
    let after: [String]
}

struct UsageEntry {
    let tag: String
    let count: Int
}

enum ExitCode {
    static let usage: Int32 = 64
    static let noInput: Int32 = 66
    static let unavailable: Int32 = 69
    static let ioError: Int32 = 74
}
