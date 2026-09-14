import Foundation

enum PositionSpec: Equatable {
    case first
    case last
    case index(Int)

    func insertionIndex(count: Int) throws -> Int {
        switch self {
        case .first:
            return 0
        case .last:
            return count
        case .index(let value):
            if value < 0 || value > count {
                throw TagStoreError.invalidIndex(value: value, count: count)
            }
            return value
        }
    }
}

enum Operation {
    case list
    case add([String])
    case remove([String])
    case set([String])
    case copy
    case match([String])
    case usage([String])
    case move(String, PositionSpec)
}

struct Options {
    var operation: Operation = .list
    var operationWasSet = false

    var color = false
    var reverse = false
    var caseSensitive = false
    var showNamesOverride: Bool? = nil
    var showTagsOverride: Bool? = nil
    var oneTagPerLine = false
    var includeHidden = false
    var enterDirectories = false
    var recursive = false
    var slashDirectories = false
    var nulTerminate = false
    var jsonLines = false
    var dryRun = false
    var addPosition: PositionSpec? = nil

    var paths: [String] = []

    var showNames: Bool {
        if let value = showNamesOverride { return value }
        switch operation {
        case .list, .match: return true
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
        case .add, .remove, .set, .copy, .move: return true
        default: return false
        }
    }
}

struct Target {
    // url is the resolved target URL. displayPath remains the user's/logical
    // path, so symlink operations affect the target while output names the link.
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
