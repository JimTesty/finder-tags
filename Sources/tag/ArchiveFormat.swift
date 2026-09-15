import Foundation

// Version 3 is the first JSONL-only archive schema. The previous version had
// two incompatible encodings and is intentionally not read anymore.
let archiveFormatVersion = 3

struct ArchiveHeader {
    let purpose: String
    let followSymlinks: Bool
    let fileInfo: Bool
    let taggedOnly: Bool
    let tagColors: [TagColorInfo]
}

func archiveHeader(from object: [String: Any], line: Int) throws -> ArchiveHeader {
    guard object["type"] as? String == "header" else {
        throw ArchiveError.invalidLine(line: line, message: "first record is not an archive header")
    }
    guard object["format"] as? String == "jsonl" else {
        throw ArchiveError.invalidLine(line: line, message: "header format must be jsonl")
    }
    guard let version = object["version"] as? NSNumber,
          version.intValue == archiveFormatVersion else {
        throw ArchiveError.invalidLine(line: line, message: "unsupported or missing archive version")
    }

    let purpose = object["purpose"] as? String ?? "export"
    guard purpose == "export" || purpose == "undo" else {
        throw ArchiveError.invalidHeader("unknown archive purpose: \(purpose)")
    }

    let tagColors = try archiveTagColors(object["tagColors"], line: line)
    return ArchiveHeader(
        purpose: purpose,
        followSymlinks: object["followSymlinks"] as? Bool ?? false,
        fileInfo: object["fileInfo"] as? Bool ?? false,
        taggedOnly: object["taggedOnly"] as? Bool ?? false,
        tagColors: tagColors
    )
}

private func archiveTagColors(_ value: Any?, line: Int) throws -> [TagColorInfo] {
    guard let value = value else { return [] }
    guard let values = value as? [[String: Any]] else {
        throw ArchiveError.invalidLine(line: line, message: "tagColors must be an array")
    }

    var result: [TagColorInfo] = []
    for entry in values {
        guard let name = entry["name"] as? String,
              let color = entry["color"] as? NSNumber,
              !name.isEmpty,
              color.intValue >= 0
        else {
            throw ArchiveError.invalidLine(line: line, message: "invalid tagColors entry")
        }
        result.append(TagColorInfo(name: name, color: color.intValue))
    }
    return result
}

func archiveHeaderObject(
    purpose: String,
    followSymlinks: Bool,
    fileInfo: Bool,
    taggedOnly: Bool,
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
        "tagColors": tagColors.map { ["name": $0.name, "color": $0.color] }
    ]
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

func validateArchiveTag(_ tag: String) throws {
    if tag.isEmpty || tag.contains("\n") || tag.contains("\r") || tag.unicodeScalars.contains("\0") {
        throw ArchiveError.invalidTags(tag)
    }
}
