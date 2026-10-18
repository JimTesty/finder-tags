import Foundation

// Escape untrusted text before adding terminal formatting or record separators.
// Keep ordinary Unicode (including combining marks and emoji joiners) intact.
func escapedDisplayText(_ text: String) -> String {
    var result = ""
    for scalar in text.unicodeScalars {
        switch scalar.value {
        case 0: result += "\\0"
        case 9: result += "\\t"
        case 10: result += "\\n"
        case 13: result += "\\r"
        case 92: result += "\\\\"
        case 1...31, 127...159, 0x2028, 0x2029,
             0x061C, 0x200E...0x200F, 0x202A...0x202E, 0x2066...0x206F:
            // Include Unicode line breaks and direction controls, which can
            // rearrange a displayed path without changing the stored name.
            result += "\\u{\(String(scalar.value, radix: 16))}"
        default:
            result.unicodeScalars.append(scalar)
        }
    }
    return result
}

// Formats names and inspected metadata without filesystem access or output I/O.
struct TextRenderer {
    let options: Options
    let colors: FinderColors

    func text(_ value: String) -> String {
        options.nulTerminate ? value : escapedDisplayText(value)
    }

    func tag(_ tag: StoredTag, compact: Bool = false) -> String {
        let name = compact ? String(tag.name.prefix(1)) : tag.name
        return colors.render(text(name), color: tag.color)
    }

    func path(_ path: String, isDirectory: Bool = false, isSymlink: Bool = false) -> String {
        var result = text(path)
        if options.slashDirectories {
            if isSymlink {
                result += "@"
            } else if isDirectory && !path.hasSuffix("/") {
                result += "/"
            }
        }
        return result
    }

    func symlinkDestination(_ destination: String?, targetExists: Bool?, targetIsDirectory: Bool) -> String {
        guard var destination = destination else { return " -> (target not recorded)" }
        if options.slashDirectories && targetExists == true && targetIsDirectory && !destination.hasSuffix("/") {
            destination += "/"
        }
        var result = " -> " + text(destination)
        if targetExists == false {
            result += " " + colors.renderMissing("(NOT FOUND)")
        }
        return result
    }

    func fileRecords(
        formattedName name: String?,
        tags: [StoredTag],
        metadata: FileMetadata?,
        isDirectory: Bool = false
    ) -> [String] {
        var lines: [String] = []
        let renderedTags: [String]
        if options.showTags {
            renderedTags = tags.map { tag($0, compact: options.compactTags) }
        } else {
            renderedTags = []
        }
        let tagText = options.compactTags
            ? renderedTags.joined()
            : renderedTags.joined(separator: ",")
        let compactTagPadding = options.compactTags ? max(0, 3 - tags.count) : 0
        let pathDisplayWidth = name.map { displayWidth($0) }
        let decoratedName: String?
        if let name = name, options.fileInfo || metadata != nil {
            let sizeText = metadata.map { fileInfoSizeText($0.size, isDirectory: isDirectory) } ?? "   ---"
            let dateText = metadata.map { fileInfoDateText($0.modificationTime) } ?? "--------"
            let decoration = "[\(dateText) \(sizeText)]"
            let coloredDecoration = colors.isEnabled
                ? "\u{001B}[32m\(decoration)\u{001B}[m"
                : decoration
            decoratedName = "\(coloredDecoration) \(name)"
        } else {
            decoratedName = name
        }

        if options.oneTagPerLine {
            if let value = decoratedName { lines.append(value) }
            for tag in renderedTags {
                lines.append((decoratedName == nil ? "" : "    ") + tag)
            }
            return lines
        }

        if let value = decoratedName {
            if renderedTags.isEmpty {
                lines.append(value)
            } else if let alignTags = options.alignTags {
                let targetWidth = alignTags + compactTagPadding
                let padding = max(0, targetWidth - (pathDisplayWidth ?? displayWidth(value)))
                lines.append(
                    value
                    + String(repeating: " ", count: padding)
                    + "  "
                    + tagText
                )
            } else if options.spaceIndent {
                lines.append(value + "  " + tagText)
            } else {
                let padding = max(0, 31 - (value as NSString).length)
                lines.append(
                    value
                    + String(repeating: " ", count: padding)
                    + "\t"
                    + String(repeating: " ", count: compactTagPadding)
                    + tagText
                )
            }
        } else if !renderedTags.isEmpty {
            lines.append(tagText)
        }
        return lines
    }

    private func displayWidth(_ value: String) -> Int {
        var width = 0
        var inEscape = false

        for character in value {
            let scalars = character.unicodeScalars
            if inEscape {
                if scalars.contains(where: { $0.value == 0x6D }) { inEscape = false }
                continue
            }
            if scalars.contains(where: { $0.value == 0x1B }) {
                inEscape = true
                continue
            }

            let visibleScalars = scalars.filter { !isZeroWidthScalar($0.value) }
            guard !visibleScalars.isEmpty else { continue }
            width += visibleScalars.contains(where: { isWideScalar($0.value) }) ? 2 : 1
        }
        return width
    }

    private func isZeroWidthScalar(_ value: UInt32) -> Bool {
        value == 0x200D
            || (value >= 0x0300 && value <= 0x036F)
            || (value >= 0x1AB0 && value <= 0x1AFF)
            || (value >= 0x1DC0 && value <= 0x1DFF)
            || (value >= 0x20D0 && value <= 0x20FF)
            || (value >= 0xFE00 && value <= 0xFE0F)
            || (value >= 0xFE20 && value <= 0xFE2F)
            || (value >= 0xE0100 && value <= 0xE01EF)
    }

    private func isWideScalar(_ value: UInt32) -> Bool {
        (value >= 0x1100 && value <= 0x115F)
            || (value >= 0x2329 && value <= 0x232A)
            || (value >= 0x2E80 && value <= 0xA4CF)
            || (value >= 0xAC00 && value <= 0xD7A3)
            || (value >= 0xF900 && value <= 0xFAFF)
            || (value >= 0xFE10 && value <= 0xFE19)
            || (value >= 0xFE30 && value <= 0xFE6F)
            || (value >= 0xFF01 && value <= 0xFF60)
            || (value >= 0xFFE0 && value <= 0xFFE6)
            || (value >= 0x1F000 && value <= 0x1FAFF)
            || (value >= 0x20000 && value <= 0x3FFFD)
    }

    private func fileInfoSizeText(_ bytes: Int64, isDirectory: Bool) -> String {
        let value: String
        if isDirectory {
            value = "---"
        } else {
            let bytesPerMegabyte: Int64 = 1_000_000
            if bytes >= 950_000 { // 0.95 MB
                let wholeMegabytes = bytes / bytesPerMegabyte +
                    (bytes % bytesPerMegabyte >= bytesPerMegabyte / 2 ? 1 : 0)
                value = "\(wholeMegabytes)MB"
            } else if bytes >= 50_000 { // 0.05 MB
                let tenths = (bytes * 10 + bytesPerMegabyte / 2) / bytesPerMegabyte
                value = ".\(tenths)MB"
            } else {
                value = "~0MB"
            }
        }
        return String(repeating: " ", count: max(0, 6 - value.count)) + value
    }

    private func fileInfoDateText(_ seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

}
