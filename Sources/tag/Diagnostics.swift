import Foundation

enum Diagnostics {
    static var colorMode: ColorMode = .never
    private static var pendingWarnings: [String]?

    static func beginParsing() {
        colorMode = .never
        pendingWarnings = []
    }

    static func finishParsing() {
        let warnings = pendingWarnings ?? []
        pendingWarnings = nil
        for message in warnings { warning(message) }
    }

    static func warning(_ message: String) {
        if pendingWarnings != nil {
            pendingWarnings?.append(message)
        } else {
            write(message, prefix: "\(programName): warning:")
        }
    }

    static func error(_ message: String) {
        finishParsing()
        write(message, prefix: "\(programName):")
    }

    private static func write(_ message: String, prefix: String) {
        var prefix = escapedDisplayText(prefix)
        if colorIsEnabled(colorMode, descriptor: FileHandle.standardError.fileDescriptor) {
            prefix = "\u{1b}[31;1m\(prefix)\u{1b}[m"
        }
        let line = prefix + " " + escapedDisplayText(message) + "\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
