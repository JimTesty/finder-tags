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
        #if canImport(Darwin)
        while true {
            let size = getxattr(url.path, attribute, nil, 0, 0, 0)
            if size < 0 {
                if errno == ENOATTR || errno == ENOTSUP { return nil }
                throw posixError(url)
            }
            var data = Data(count: size)
            let count = data.withUnsafeMutableBytes {
                getxattr(url.path, attribute, $0.baseAddress, $0.count, 0, 0)
            }
            if count < 0 {
                if errno == ERANGE { continue } // Attribute grew between reads.
                if errno == ENOATTR { return nil }
                throw posixError(url)
            }
            if count > size { continue }
            data.count = count
            return try decode(data) { onWarning("\(url.path): \($0)") }
        }
        #else
        return nil
        #endif
    }

    static func decode(_ data: Data, onWarning: (String) -> Void = reportWarning) throws -> [StoredTag] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let values = object as? [Any] else {
            throw invalid("tag metadata is not an array")
        }
        return values.enumerated().compactMap { index, entry in
            guard let value = entry as? String else {
                let value = tagNameText(entry) { onWarning("stored tag at index \(index): \($0)") }
                return repairedTagName(value, onWarning: {
                    onWarning("stored tag at index \(index): \($0)")
                }).map { StoredTag(name: $0) }
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
                    onWarning("invalid stored color suffix in tag '\(value)'; preserving the whole value with color unavailable")
                    rawName = value
                }
            } else {
                rawName = value
                color = nil
            }
            guard let name = repairedTagName(rawName, onWarning: onWarning) else { return nil }
            // Unknown integer colors are data, not a reason to discard a tag.
            return StoredTag(name: name, color: color)
        }
    }

    static func usableTags(_ tags: [StoredTag], onWarning: (String) -> Void) -> [StoredTag] {
        tags.compactMap { tag in
            guard let name = repairedTagName(tag.name, onWarning: onWarning) else { return nil }
            return StoredTag(name: name, color: tag.color)
        }
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
