import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func stdoutIsTerminal() -> Bool {
    return isatty(STDOUT_FILENO) == 1
}

func colorIsEnabled(_ mode: ColorMode) -> Bool {
    switch mode {
    case .auto: return stdoutIsTerminal()
    case .always: return true
    case .never: return false
    }
}

// Rendering never infers a color from a name or the current Mac's preferences.
struct FinderColors {
    let isEnabled: Bool

    init(enabled: Bool) {
        isEnabled = enabled
    }

    func render(_ text: String, color: Int?) -> String {
        guard isEnabled, let code = color, let escape = FinderColors.ansiByCode[code] else {
            return text
        }
        return escape + text + "\u{001B}[m"
    }

    func renderMissing(_ text: String) -> String {
        guard isEnabled else { return text }
        return "\u{001B}[31m\(text)\u{001B}[m"
    }

    private static let ansiByCode: [Int: String] = [
        1: "\u{001B}[48;5;241m", // gray
        2: "\u{001B}[42m",       // green
        3: "\u{001B}[48;5;129m", // purple
        4: "\u{001B}[44m",       // blue
        5: "\u{001B}[43m",       // yellow
        6: "\u{001B}[41m",       // red
        7: "\u{001B}[48;5;208m"  // orange
    ]
}
