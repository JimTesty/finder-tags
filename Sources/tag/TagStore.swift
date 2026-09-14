import Foundation

enum TagStoreError: LocalizedError {
    case verificationFailed(path: String, expected: [String], actual: [String])

    var errorDescription: String? {
        switch self {
        case let .verificationFailed(path, expected, actual):
            return "tag write verification failed for \(path): expected \(expected), read back \(actual)"
        }
    }
}

struct TagStore {
    func read(_ url: URL) throws -> [String] {
        // A missing tag value means "no tags". Any actual resource-value read
        // failure throws and is never converted into an empty array.
        try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    }

    func write(_ tags: [String], to url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)

        // setResourceValue is synchronous, but a read-back catches silent
        // normalization/reordering or a failed persistence path cheaply.
        let actual = try read(url)
        guard actual == tags else {
            throw TagStoreError.verificationFailed(
                path: url.path,
                expected: tags,
                actual: actual
            )
        }
    }

    func add(_ requested: [String], to url: URL) throws {
        let existing = try read(url)
        var revised = existing
        var seen = Set(existing.map(canonicalTag))

        for tag in requested where seen.insert(canonicalTag(tag)).inserted {
            revised.append(tag)
        }

        // Avoid unnecessary metadata writes.
        if revised != existing {
            try write(revised, to: url)
        }
    }

    func remove(_ requested: [String], from url: URL) throws {
        let existing = try read(url)
        let revised: [String]

        if requested.contains("*") {
            revised = []
        } else {
            let unwanted = Set(requested.map(canonicalTag))
            revised = existing.filter { !unwanted.contains(canonicalTag($0)) }
        }

        if revised != existing {
            try write(revised, to: url)
        }
    }

    func set(_ requested: [String], on url: URL) throws {
        // Read first even though set is destructive. This proves the metadata is
        // readable before we replace it, preventing "read error == no tags" bugs.
        let existing = try read(url)
        if existing != requested {
            try write(requested, to: url)
        }
    }

    func copy(from source: URL, to destination: URL) throws {
        // Crucially, complete the source read before touching the destination.
        let sourceTags = try read(source)
        _ = try read(destination) // prove destination metadata is readable first
        try write(sourceTags, to: destination)
    }
}
