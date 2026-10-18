import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

func colorIsEnabled(_ mode: ColorMode, descriptor: Int32 = STDOUT_FILENO) -> Bool {
    switch mode {
    case .auto: return isatty(descriptor) == 1
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

    func renderBrokenSymlink(_ text: String) -> String {
        guard isEnabled else { return text }
        return "\u{001B}[41;1m\(text)\u{001B}[m"
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
