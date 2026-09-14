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
        // A successful read with no tag value means "no tags". Any resource
        // value error throws and must never be converted into an empty array.
        return try url.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    }

    func write(_ tags: [String], to url: URL) throws {
        try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey)

        // Cheap best-effort verification. This catches silent persistence,
        // normalization, or ordering failures without adding transaction logic.
        let actual = try read(url)
        if actual != tags {
            throw TagStoreError.verificationFailed(
                path: url.path,
                expected: tags,
                actual: actual
            )
        }
    }

    func addChange(_ requested: [String], to url: URL) throws -> TagChange {
        let existing = try read(url)
        var revised = existing
        var seen = Set(existing.map(canonicalTag))

        for tag in requested {
            if seen.insert(canonicalTag(tag)).inserted {
                revised.append(tag)
            }
        }
        return TagChange(before: existing, after: revised)
    }

    func removeChange(_ requested: [String], from url: URL) throws -> TagChange {
        let existing = try read(url)
        let revised: [String]

        if requested.contains("*") {
            revised = []
        } else {
            let unwanted = Set(requested.map(canonicalTag))
            revised = existing.filter { !unwanted.contains(canonicalTag($0)) }
        }
        return TagChange(before: existing, after: revised)
    }

    func setChange(_ requested: [String], on url: URL) throws -> TagChange {
        // Even destructive set reads first so a metadata read failure cannot be
        // misinterpreted as "the file has no tags".
        let existing = try read(url)
        return TagChange(before: existing, after: requested)
    }

    func copyChange(from source: URL, to destination: URL) throws -> TagChange {
        // Fully complete both reads before any possible destination write.
        let sourceTags = try read(source)
        let destinationTags = try read(destination)
        return TagChange(before: destinationTags, after: sourceTags)
    }

    func apply(_ change: TagChange, to url: URL) throws {
        if change.before != change.after {
            try write(change.after, to: url)
        }
    }
}
