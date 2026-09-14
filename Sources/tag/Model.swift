import Foundation

enum Operation {
    case list
    case add([String])
    case remove([String])
    case set([String])
    case copy
}

struct Options {
    var operation: Operation = .list
    var operationWasSet = false

    var color = false
    var reverse = false
    var showNames = true
    var showTags = true
    var oneTagPerLine = false
    var includeHidden = false
    var enterDirectories = false
    var recursive = false
    var slashDirectories = false
    var nulTerminate = false

    var paths: [String] = []
}

struct Target {
    let url: URL
    let displayPath: String
}

enum ExitCode {
    static let usage: Int32 = 64
    static let noInput: Int32 = 66
    static let ioError: Int32 = 74
}
