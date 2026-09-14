import Foundation

enum ArchiveEncoding: String {
    case plain
    case jsonl
}

struct ArchiveHeader {
    let encoding: ArchiveEncoding
    let separator: Character
    let reverse: Bool
    let slashDirectories: Bool
    let spaceIndent: Bool
}

let archiveFormatVersion = 2

func validatedArchiveSeparator(_ value: String) throws -> Character {
    let scalars = Array(value.unicodeScalars)
    guard scalars.count == 1, let scalar = scalars.first else {
        throw ArchiveError.invalidHeader("separator must be one Unicode scalar")
    }
    guard (!CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar.value == 0x200B),
          scalar.value != 0,
          scalar.value != 0x09,
          scalar.value != 0x0A,
          scalar.value != 0x0D,
          scalar.value != 0x2C,
          scalar.value != 0x5C
    else {
        throw ArchiveError.invalidHeader("separator cannot be whitespace, comma, backslash, or NUL")
    }
    return Character(value)
}

func jsonObject(from line: String) throws -> [String: Any] {
    guard let data = line.data(using: .utf8),
          let value = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
    else {
        throw ArchiveError.invalidHeader("first line is not a JSON object")
    }
    return value
}

func archiveHeader(from object: [String: Any], line: Int) throws -> ArchiveHeader {
    guard let formatValue = object["format"] as? String,
          let encoding = ArchiveEncoding(rawValue: formatValue) else {
        throw ArchiveError.invalidLine(line: line, message: "header has an invalid format")
    }
    guard let version = object["version"] as? NSNumber, version.intValue == archiveFormatVersion else {
        throw ArchiveError.invalidLine(line: line, message: "unsupported or missing archive version")
    }
    guard let separatorValue = object["separator"] as? String else {
        throw ArchiveError.invalidLine(line: line, message: "header lacks a string separator")
    }

    do {
        return ArchiveHeader(
            encoding: encoding,
            separator: try validatedArchiveSeparator(separatorValue),
            reverse: object["reverse"] as? Bool ?? false,
            slashDirectories: object["slash"] as? Bool ?? false,
            spaceIndent: object["spaceIndent"] as? Bool ?? false
        )
    } catch let error as ArchiveError {
        throw error
    } catch {
        throw ArchiveError.invalidLine(line: line, message: error.localizedDescription)
    }
}

func archiveQuote(_ value: String) -> String {
    return archiveQuote(value, separator: "\"")
}

func archiveQuote(_ value: String, separator: Character, always: Bool = false) -> String {
    if !always && !archiveFieldNeedsQuotes(value, separator: separator) { return value }
    var result = String(separator)
    for scalar in value.unicodeScalars {
        let character = Character(scalar)
        switch scalar.value {
        case 0x5c: result += "\\\\"
        case 0x09: result += "\\t"
        case 0x0a: result += "\\n"
        case 0x0d: result += "\\r"
        default:
            if character == separator {
                if separator == "\"" {
                    result += "\\\""
                } else {
                    result += String(format: "\\u{%X}", scalar.value)
                }
            } else {
                result.append(character)
            }
        }
    }
    return result + String(separator)
}

private func archiveFieldNeedsQuotes(_ value: String, separator: Character) -> Bool {
    if value.isEmpty || value.hasPrefix("#") || value.hasPrefix("@") { return true }
    for scalar in value.unicodeScalars {
        let character = Character(scalar)
        if CharacterSet.whitespacesAndNewlines.contains(scalar)
            || scalar.value == 0x2c || scalar.value == 0x5c
            || character == separator
        {
            return true
        }
    }
    return false
}

func validateRelativeArchivePath(_ path: String) throws {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.unicodeScalars.contains("\0") else {
        throw ArchiveError.invalidPath(path)
    }
    if path == "." { return }
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    if components.contains(where: {
        let component = String($0)
        return component.isEmpty || component == "." || component == ".."
    }) {
        throw ArchiveError.invalidPath(path)
    }
}

func parseArchiveField(_ raw: String, separator: Character) throws -> String {
    let value = raw.trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty else { throw ArchiveError.invalidPath(raw) }
    let (result, end) = try parseArchiveFieldPrefix(value, separator: separator)
    let chars = Array(value)
    guard chars[end...].allSatisfy(\.isWhitespace) else {
        throw ArchiveError.invalidPath(raw)
    }
    return result
}

func parseArchiveFieldPrefix(_ raw: String, separator: Character) throws -> (String, Int) {
    let chars = Array(raw)
    var index = 0
    while index < chars.count && chars[index].isWhitespace { index += 1 }
    guard index < chars.count else { throw ArchiveError.invalidPath(raw) }

    if chars[index] == separator {
        index += 1
        var result = ""
        while index < chars.count {
            let ch = chars[index]
            if ch == separator { return (result, index + 1) }
            if ch == "\\" {
                result.append(try parseArchiveEscape(chars, index: &index, separator: separator))
            } else {
                result.append(ch)
                index += 1
            }
        }
        throw ArchiveError.invalidPath(raw)
    }

    let start = index
    var result = ""
    while index < chars.count && !chars[index].isWhitespace {
        let ch = chars[index]
        if ch == separator || ch == "\\" {
            throw ArchiveError.invalidPath(raw)
        }
        result.append(ch)
        index += 1
    }
    guard index > start else { throw ArchiveError.invalidPath(raw) }
    return (result, index)
}

private func parseArchiveEscape(
    _ chars: [Character],
    index: inout Int,
    separator: Character
) throws -> Character {
    index += 1
    guard index < chars.count else { throw ArchiveError.invalidPath("unterminated escape") }
    let escaped = chars[index]
    if escaped == separator {
        index += 1
        return separator
    }
    switch escaped {
    case "\\":
        index += 1
        return "\\"
    case "\"":
        index += 1
        return "\""
    case "n":
        index += 1
        return "\n"
    case "r":
        index += 1
        return "\r"
    case "t":
        index += 1
        return "\t"
    case "u":
        index += 1
        var hex = ""
        if index < chars.count && chars[index] == "{" {
            index += 1
            while index < chars.count && chars[index] != "}" {
                hex.append(chars[index])
                index += 1
            }
            guard index < chars.count, chars[index] == "}", !hex.isEmpty else {
                throw ArchiveError.invalidPath("invalid Unicode escape")
            }
            index += 1
        } else {
            guard index + 4 <= chars.count else {
                throw ArchiveError.invalidPath("invalid Unicode escape")
            }
            hex = String(chars[index..<(index + 4)])
            index += 4
        }
        guard let value = UInt32(hex, radix: 16), let scalar = UnicodeScalar(value) else {
            throw ArchiveError.invalidPath("invalid Unicode escape")
        }
        return Character(scalar)
    default:
        throw ArchiveError.invalidPath("invalid escape")
    }
}

func parseArchiveTagList(_ raw: String, separator: Character) throws -> [String] {
    if raw.trimmingCharacters(in: .whitespaces).isEmpty { return [] }

    let chars = Array(raw)
    var result: [String] = []
    var current = ""
    var quoted = false
    var afterQuote = false

    func appendCurrent() throws {
        let value = quoted ? current : current.trimmingCharacters(in: .whitespaces)
        if value.isEmpty { throw ArchiveError.invalidTags(raw) }
        if value.contains("\n") || value.contains("\r") || value.unicodeScalars.contains("\0") {
            throw ArchiveError.invalidTags(value)
        }
        result.append(value)
        current = ""
        quoted = false
        afterQuote = false
    }

    var index = 0
    while index < chars.count {
        let ch = chars[index]
        if quoted {
            if ch == "\\" {
                do {
                    current.append(try parseArchiveEscape(chars, index: &index, separator: separator))
                } catch {
                    throw ArchiveError.invalidTags(raw)
                }
            } else if ch == separator {
                quoted = false
                afterQuote = true
            } else {
                current.append(ch)
            }
        } else if afterQuote {
            if ch.isWhitespace {
                // Padding between a quoted tag and its comma is harmless.
            } else if ch == "," {
                try appendCurrent()
            } else {
                throw ArchiveError.invalidTags(raw)
            }
        } else if ch == separator {
            if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                throw ArchiveError.invalidTags(raw)
            }
            current = ""
            quoted = true
        } else if ch == "," {
            try appendCurrent()
        } else {
            current.append(ch)
        }
        index += 1
    }

    if quoted || afterQuote || !current.isEmpty {
        try appendCurrent()
    }
    return result
}

func stripANSI(_ value: String) -> String {
    let chars = Array(value)
    var result = ""
    var index = 0
    while index < chars.count {
        if chars[index] == "\u{001B}" && index + 1 < chars.count && chars[index + 1] == "[" {
            index += 2
            while index < chars.count {
                let end = chars[index]
                index += 1
                if end == "m" { break }
            }
        } else {
            result.append(chars[index])
            index += 1
        }
    }
    return result
}
