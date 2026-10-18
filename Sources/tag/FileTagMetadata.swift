import Foundation
#if canImport(Darwin)
import Darwin
#endif

// NSURLTagNamesKey drops the color suffix of each stored tag. Keep the small
// xattr boundary here; Foundation still supplies legacy labels and chooses
// initial colors for newly requested names.
enum FileTagMetadata {
    private static let attribute = "com.apple.metadata:_kMDItemUserTags"

    static func read(_ url: URL, onWarning: (String) -> Void = reportWarning) throws -> [StoredTag]? {
        try readState(url, onWarning: onWarning)?.tags
    }

    static func readState(
        _ url: URL, followSymlinks: Bool = true, onWarning: (String) -> Void = reportWarning
    ) throws -> TagRead? {
        #if canImport(Darwin)
        let flags: Int32 = followSymlinks ? 0 : XATTR_NOFOLLOW
        while true {
            let size = getxattr(url.path, attribute, nil, 0, 0, flags)
            if size < 0 {
                if errno == ENOATTR || errno == ENOTSUP { return nil }
                throw posixError(url)
            }
            var data = Data(count: size)
            let count = data.withUnsafeMutableBytes {
                getxattr(url.path, attribute, $0.baseAddress, $0.count, 0, flags)
            }
            if count < 0 {
                if errno == ERANGE { continue } // Attribute grew between reads.
                if errno == ENOATTR { return nil }
                throw posixError(url)
            }
            if count > size { continue }
            data.count = count
            return try decodeState(data) { onWarning("\(url.path): \($0)") }
        }
        #else
        return nil
        #endif
    }

    static func decode(_ data: Data, onWarning: (String) -> Void = reportWarning) throws -> [StoredTag] {
        try decodeState(data, onWarning: onWarning).tags
    }

    static func decodeState(_ data: Data, onWarning: (String) -> Void = reportWarning) throws -> TagRead {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let values = object as? [Any] else {
            throw invalid("tag metadata is not an array")
        }
        var initiallyFixed = Set<Int>()
        let tags: [StoredTag] = values.enumerated().map { index, entry in
            guard let value = entry as? String else {
                let value = tagNameText(entry) { onWarning("stored tag at index \(index): \($0)") }
                initiallyFixed.insert(index)
                return StoredTag(name: value)
            }
            let scalars = value.unicodeScalars
            let rawName: String
            let color: Int?
            if let newline = scalars.lastIndex(of: "\n") {
                let suffix = String(scalars[scalars.index(after: newline)...])
                color = Int(suffix)
                if color != nil {
                    rawName = String(scalars[..<newline])
                } else {
                    initiallyFixed.insert(index)
                    onWarning("invalid stored color suffix in tag '\(value)'; preserving the whole value with color unavailable")
                    rawName = value
                }
            } else {
                rawName = value
                color = nil
            }
            // Unknown integer colors are data, not a reason to discard a tag.
            return StoredTag(name: rawName, color: color)
        }
        return repairTags(tags, initiallyFixed: initiallyFixed, onWarning: onWarning)
    }

    static func usableTags(_ tags: [StoredTag], onWarning: (String) -> Void) -> [StoredTag] {
        repairTags(tags, onWarning: onWarning).tags
    }

    static func repairTags(
        _ tags: [StoredTag], initiallyFixed: Set<Int> = [], onWarning: (String) -> Void
    ) -> TagRead {
        var fixed = initiallyFixed
        var deleted = 0
        var sourceIndices: [Int] = []
        let names: [String] = tags.enumerated().compactMap { index, tag in
            guard let name = repairedTagName(tag.name, onWarning: onWarning) else {
                fixed.remove(index)
                deleted += 1
                return nil
            }
            sourceIndices.append(index)
            if name != tag.name { fixed.insert(index) }
            return name
        }
        let uniqueNames = uniqueTagNames(names) { index, name in
            fixed.insert(sourceIndices[index])
            onWarning("duplicate tag name '\(names[index])' renamed to '\(name)'")
        }
        let recovered = uniqueNames.enumerated().map { index, name in
            StoredTag(name: name, color: tags[sourceIndices[index]].color)
        }
        return TagRead(tags: recovered, repairs: TagRepairs(fixed: fixed.count, deleted: deleted))
    }

    static func write(_ tags: [StoredTag], to url: URL, onWarning: (String) -> Void = reportWarning) throws {
        let tags = usableTags(tags) { onWarning("\(url.path): \($0)") }
        #if canImport(Darwin)
        let values = tags.map { tag in
            tag.color.map { tag.name + "\n" + String($0) } ?? tag.name
        }
        let data = try PropertyListSerialization.data(
            fromPropertyList: values, format: .binary, options: 0
        )
        let status = data.withUnsafeBytes {
            setxattr(url.path, attribute, $0.baseAddress, $0.count, 0, 0)
        }
        guard status == 0 else { throw posixError(url) }
        #else
        throw invalid("this platform cannot write Finder tag color metadata")
        #endif
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "finder-tags", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    #if canImport(Darwin)
    private static func posixError(_ url: URL) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
    #endif
}
