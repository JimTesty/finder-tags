import Foundation
import CoreFoundation

func archiveInteger(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
    return Int(number.stringValue)
}

func archiveFiniteNumber(_ value: Any?) -> Double? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite else { return nil }
    return number.doubleValue
}

func archiveBoolean(_ value: Any?, field: String, line: Int) throws -> Bool {
    guard let value = value else { return false }
    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
        throw ArchiveError.invalidLine(line: line, message: "\(field) must be boolean")
    }
    return number.boolValue
}

// Colors align with the ordered tag names. JSON null means unavailable, which
// is distinct from an explicit zero (no color). Keep unfamiliar integers intact.
func tagColorNumbers(_ tags: [StoredTag]) -> [Any] {
    tags.map { tag -> Any in tag.color.map { $0 as Any } ?? NSNull() }
}

func archiveItemColors(_ value: Any?, tags: [String]?, line: Int) throws -> [Int?]? {
    guard let value = value else { return nil } // Older version 3 archives.
    guard let tags = tags, let values = value as? [Any], values.count == tags.count else {
        throw ArchiveError.invalidLine(line: line, message: "colors must align with the tags array")
    }
    return try values.map { value in
        if value is NSNull { return nil }
        // Do not truncate fractional values or silently turn booleans into 0/1.
        guard let integer = archiveInteger(value) else {
            throw ArchiveError.invalidLine(line: line, message: "colors must contain integers or null")
        }
        return integer
    }
}

// Version 3 is the first JSONL-only archive schema. The previous version had
// two incompatible encodings and is intentionally not read anymore.
let archiveFormatVersion = 3

struct ArchiveHeader {
    let purpose: String
    let followSymlinks: Bool
    let fileInfo: Bool
    let taggedOnly: Bool
    let excludePatterns: [String]
    let tagColors: [TagColorInfo]
}

func archiveHeader(from object: [String: Any], line: Int) throws -> ArchiveHeader {
    guard object["type"] as? String == "header" else {
        throw ArchiveError.invalidLine(line: line, message: "first record is not an archive header")
    }
    guard object["format"] as? String == "jsonl" else {
        throw ArchiveError.invalidLine(line: line, message: "header format must be jsonl")
    }
    guard archiveInteger(object["version"]) == archiveFormatVersion else {
        throw ArchiveError.invalidLine(line: line, message: "unsupported or missing archive version")
    }

    guard let purpose = (object["purpose"] ?? "export") as? String,
          purpose == "export" || purpose == "undo" else {
        throw ArchiveError.invalidLine(line: line, message: "purpose must be export or undo")
    }

    let tagColors = try archiveTagColors(object["tagColors"], line: line)
    let excludePatterns = try archiveExcludePatterns(object["exclude"], line: line)
    return ArchiveHeader(
        purpose: purpose,
        followSymlinks: try archiveBoolean(object["followSymlinks"], field: "followSymlinks", line: line),
        fileInfo: try archiveBoolean(object["fileInfo"], field: "fileInfo", line: line),
        taggedOnly: try archiveBoolean(object["taggedOnly"], field: "taggedOnly", line: line),
        excludePatterns: excludePatterns,
        tagColors: tagColors
    )
}

private func archiveExcludePatterns(_ value: Any?, line: Int) throws -> [String] {
    guard let value = value else { return [] }
    guard let values = value as? [Any] else {
        throw ArchiveError.invalidLine(line: line, message: "exclude must be an array")
    }
    var result: [String] = []
    for value in values {
        guard let pattern = value as? String, !pattern.isEmpty else {
            throw ArchiveError.invalidLine(line: line, message: "exclude must contain non-empty strings")
        }
        result.append(pattern)
    }
    return result
}

private func archiveTagColors(_ value: Any?, line: Int) throws -> [TagColorInfo] {
    guard let value = value else { return [] }
    guard let values = value as? [[String: Any]] else {
        throw ArchiveError.invalidLine(line: line, message: "tagColors must be an array")
    }

    var result: [TagColorInfo] = []
    for entry in values {
        guard let name = entry["name"] as? String,
              !name.isEmpty,
              let number = archiveInteger(entry["color"]), number >= 0
        else {
            throw ArchiveError.invalidLine(line: line, message: "invalid tagColors entry")
        }
        result.append(TagColorInfo(name: name, color: number))
    }
    return result
}

func archiveHeaderObject(
    purpose: String,
    followSymlinks: Bool,
    fileInfo: Bool,
    taggedOnly: Bool,
    excludePatterns: [String],
    tagColors: [TagColorInfo]
) -> [String: Any] {
    return [
        "type": "header",
        "format": "jsonl",
        "version": archiveFormatVersion,
        "purpose": purpose,
        "followSymlinks": followSymlinks,
        "fileInfo": fileInfo,
        "taggedOnly": taggedOnly,
        "exclude": excludePatterns,
        "tagColors": tagColors.map { ["name": $0.name, "color": $0.color] }
    ]
}

func validateRelativeArchivePath(_ path: String) throws {
    guard !path.isEmpty, path.utf8.first != 47, !path.utf8.contains(0) else {
        throw ArchiveError.invalidPath(path)
    }
    if path == "." { return }

    let components = path.utf8.split(separator: 47, omittingEmptySubsequences: false)
    if components.contains(where: {
        let component = String(decoding: $0, as: UTF8.self)
        return component.isEmpty || component == "." || component == ".."
    }) {
        throw ArchiveError.invalidPath(path)
    }
}

func validateArchiveTag(_ tag: String) throws {
    if tag.isEmpty || containsInvalidTagCharacters(tag) {
        throw ArchiveError.invalidTags(tag)
    }
}
