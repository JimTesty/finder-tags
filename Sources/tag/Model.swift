import Foundation

enum Operation {
    case list
    case add([String])
    case remove([String])
    case set([String])
    case copy
    case match([String])
    case usage([String])
}

struct Options {
    var operation: Operation = .list
    var operationWasSet = false

    var color = false
    var reverse = false
    var showNamesOverride: Bool? = nil
    var showTagsOverride: Bool? = nil
    var oneTagPerLine = false
    var includeHidden = false
    var enterDirectories = false
    var recursive = false
    var slashDirectories = false
    var nulTerminate = false
    var json = false
    var dryRun = false

    var paths: [String] = []

    var showNames: Bool {
        if let value = showNamesOverride { return value }
        switch operation {
        case .list: return true
        case .match: return true
        default: return false
        }
    }

    var showTags: Bool {
        if let value = showTagsOverride { return value }
        switch operation {
        case .list: return true
        case .match: return false
        default: return false
        }
    }

    var isMutating: Bool {
        switch operation {
        case .add, .remove, .set, .copy: return true
        default: return false
        }
    }
}

struct Target {
    let url: URL
    let displayPath: String
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
    static let ioError: Int32 = 74
}
