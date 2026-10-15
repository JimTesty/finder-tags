import Foundation
#if canImport(Darwin)
import Darwin
#endif

// NSURLTagNamesKey drops the color suffix of each stored tag. Keep the small
// xattr boundary here; Foundation still supplies legacy labels and chooses
// initial colors for newly requested names.
enum FileTagMetadata {
    private static let attribute = "com.apple.metadata:_kMDItemUserTags"

    static func read(_ url: URL) throws -> [StoredTag]? {
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
            return try decode(data)
        }
        #else
        return nil
        #endif
    }

    static func decode(_ data: Data) throws -> [StoredTag] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let values = object as? [String] else {
            throw invalid("tag metadata is not an array of strings")
        }
        return try values.map { value in
            let scalars = value.unicodeScalars
            guard let newline = scalars.lastIndex(of: "\n") else {
                guard !value.isEmpty, !containsInvalidTagCharacters(value) else {
                    throw invalid("invalid stored tag: \(String(reflecting: value))")
                }
                return StoredTag(name: value)
            }
            let name = String(scalars[..<newline])
            let suffix = String(scalars[scalars.index(after: newline)...])
            guard !name.isEmpty, !containsInvalidTagCharacters(name), let color = Int(suffix) else {
                throw invalid("invalid stored tag: \(String(reflecting: value))")
            }
            return StoredTag(name: name, color: color)
        }
    }

    static func write(_ tags: [StoredTag], to url: URL) throws {
        for tag in tags where tag.name.isEmpty || containsInvalidTagCharacters(tag.name) {
            throw invalid("invalid stored tag name: \(String(reflecting: tag.name))")
        }
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
