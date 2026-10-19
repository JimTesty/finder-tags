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
    case fix
    case copy
    case match(TagQuery)
    case filter(TagQuery)
    case usage(TagQuery)
    case find(TagQuery)
    case move(String, PositionSpec?)

}

indirect enum TagQuery: Equatable {
    case noTags
    case tag(String)
    case anyTag
    case all([TagQuery])
    case any([TagQuery])
    case not(TagQuery)
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
    var isDirectory = false
}

struct Options {
    var operation: Operation = .list
    var operationWasSet = false
    var helpRequests = 0

    var colorMode: ColorMode = .never
    var colorWasSet = false
    // Preserve the full balance so repeated -q and -v cancel one for one.
    var verbosity = 0
    var quiet: Bool { verbosity < 0 }
    var verbose: Bool { verbosity > 0 }
    var reverse = false
    var reverseWasSet = false
    var sortedTags = false
    var caseSensitive = false
    var showNamesOverride: Bool? = nil
    var showTagsOverride: Bool? = nil
    var oneTagPerLine = false
    var spaceIndent = false
    var alignTags: Int? = nil
    var compactTags = false
    var includeHidden = false
    var enterDirectories = false
    var recursive = false
    var sortFiles = true
    var slashDirectories = false
    var nulTerminate = false
    var jsonLines = false
    var dryRun = false
    var taggedOnly = false
    var fileInfo = false
    var fileInfoWasSet = false
    var archivePath: String? = nil
    var restoreRoot: String? = nil
    var backupOverride: Bool? = nil
    var backupPath: String? = nil
    var syncBackup = false
    var position: PositionSpec? = nil
    var absolutePaths = false
    var followSymlinks = false
    var resolveSymlinksForArguments = false
    var printSymlinks = false
    var excludePatterns: [String] = []
    var stdinPathMode: StdinPathMode? = nil
    var pathInputExplicit = false

    var paths: [String] = []

    var showNames: Bool {
        if let value = showNamesOverride { return value }
        switch operation {
        case .list, .match, .filter, .find, .convert: return true
        default: return false
        }
    }

    var showTags: Bool {
        if let value = showTagsOverride { return value }
        switch operation {
        case .list, .filter, .convert: return true
        case .match, .find: return false
        default: return false
        }
    }

    var isMutating: Bool {
        switch operation {
        case .add, .remove, .set, .fix, .copy, .move, .restore: return true
        default: return false
        }
    }

    var backupEnabled: Bool {
        if let enabled = backupOverride { return enabled }
        if case .restore = operation { return true }
        return recursive || enterDirectories || stdinPathMode != nil
    }
}

struct Target {
    // url is the URL used for tag I/O. -L or explicit-operand resolution may
    // resolve it through symlinks.
    // logicalURL preserves the user's filesystem path for output/provenance.
    let url: URL
    let logicalURL: URL
    let displayPath: String
    let rootPath: String?

    var absolutePath: String { return logicalURL.standardizedFileURL.path }
}

// Retained for reading the informational palette in older archive headers.
struct TagColorInfo {
    let name: String
    let color: Int
}

struct StoredTag: Equatable {
    let name: String
    // nil means that no per-tag color number was available. Zero explicitly
    // means no color; unknown numbers are preserved rather than normalized.
    let color: Int?

    init(name: String, color: Int? = nil) {
        self.name = name
        self.color = color
    }
}

struct TagRepairs {
    var fixed = 0
    var deleted = 0

    var total: Int { fixed + deleted }

    mutating func add(_ other: TagRepairs) {
        fixed += other.fixed
        deleted += other.deleted
    }
}

struct TagRead {
    let tags: [StoredTag]
    var repairs = TagRepairs()

    var needsRepair: Bool { repairs.total > 0 }
}

struct TagChange {
    let beforeTags: [StoredTag]
    let afterTags: [StoredTag]
    var initialColorNames: Set<String> = []
    var repairs = TagRepairs()

    var before: [String] { beforeTags.map { $0.name } }
    var after: [String] { afterTags.map { $0.name } }
    var needsRepair: Bool { repairs.total > 0 }
    var hasChanges: Bool { needsRepair || beforeTags != afterTags }
}

struct FixStats {
    var visited = 0
    var filesUpdated = 0
    var unchanged = 0
    var skipped = 0
    var errors = 0
    var repairs = TagRepairs()
}

struct UsageEntry {
    let tag: String
    let count: Int
    let colors: Set<Int>
    let hasUnknownColor: Bool
}

enum ExitCode {
    static let usage: Int32 = 64
    static let noInput: Int32 = 66
    static let unavailable: Int32 = 69
    static let ioError: Int32 = 74
}
