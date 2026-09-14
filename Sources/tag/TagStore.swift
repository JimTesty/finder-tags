import Foundation

enum TagStoreError: LocalizedError {
    case verificationFailed(path: String, expected: [String], actual: [String])
    case ambiguousCaseMatch(tag: String, matches: [String])
    case tagNotFound(tag: String)
    case invalidIndex(value: Int, count: Int)

    var errorDescription: String? {
        switch self {
        case let .verificationFailed(path, expected, actual):
            return "tag write verification failed for \(path): expected \(expected), read back \(actual)"
        case let .ambiguousCaseMatch(tag, matches):
            return "case-insensitive tag '\(tag)' is ambiguous among \(matches); use --case-sensitive or exact casing"
        case let .tagNotFound(tag):
            return "tag not found: \(tag)"
        case let .invalidIndex(value, count):
            return "index \(value) is out of range; valid insertion indexes are 0...\(count)"
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

    func addChange(
        _ requested: [String],
        to url: URL,
        caseSensitive: Bool,
        position: PositionSpec?
    ) throws -> TagChange {
        let existing = try read(url)
        var revised = existing
        var missing: [String] = []

        // Match only against the original array. A request that explicitly
        // contains case-distinct variants (for example "orange,Orange") means
        // the caller wants both spellings, so those variants are never folded
        // into one another during add.
        var requestedFoldCounts: [String: Int] = [:]
        if !caseSensitive {
            for tag in requested {
                let key = foldedTag(tag)
                requestedFoldCounts[key] = (requestedFoldCounts[key] ?? 0) + 1
            }
        }

        for tag in requested {
            if existing.contains(tag) { continue }

            if !caseSensitive && requestedFoldCounts[foldedTag(tag)] == 1 {
                let matches = existing.indices.filter {
                    foldedTag(existing[$0]) == foldedTag(tag)
                }
                if matches.count == 1 {
                    // Finder matching is normally case-insensitive, but case is
                    // data. Re-case the unique existing match in place.
                    revised[matches[0]] = tag
                    continue
                }
                if matches.count > 1 {
                    throw TagStoreError.ambiguousCaseMatch(
                        tag: tag,
                        matches: matches.map { existing[$0] }
                    )
                }
            }

            missing.append(tag)
        }

        if !missing.isEmpty {
            let insertion = try (position ?? .last).insertionIndex(count: revised.count)
            revised.insert(contentsOf: missing, at: insertion)
        }
        return TagChange(before: existing, after: revised)
    }

    func removeChange(
        _ requested: [String],
        from url: URL,
        caseSensitive: Bool
    ) throws -> TagChange {
        let existing = try read(url)
        let revised: [String]

        if requested.contains("*") {
            revised = []
        } else {
            revised = existing.filter { stored in
                !requested.contains(where: {
                    tagsEqual(stored, $0, caseSensitive: caseSensitive)
                })
            }
        }
        return TagChange(before: existing, after: revised)
    }

    func setChange(_ requested: [String], on url: URL) throws -> TagChange {
        // Even destructive set reads first so a metadata read failure cannot be
        // misinterpreted as "the file has no tags".
        let existing = try read(url)
        return TagChange(before: existing, after: requested)
    }

    func moveChange(
        tag: String,
        to position: PositionSpec,
        on url: URL,
        caseSensitive: Bool
    ) throws -> TagChange {
        let existing = try read(url)
        let matches: [Int]

        if caseSensitive {
            matches = existing.indices.filter { existing[$0] == tag }
        } else {
            let exact = existing.indices.filter { existing[$0] == tag }
            if exact.count == 1 {
                matches = exact
            } else if exact.count > 1 {
                throw TagStoreError.ambiguousCaseMatch(tag: tag, matches: exact.map { existing[$0] })
            } else {
                matches = existing.indices.filter { foldedTag(existing[$0]) == foldedTag(tag) }
            }
        }

        if matches.isEmpty { throw TagStoreError.tagNotFound(tag: tag) }
        if matches.count > 1 {
            throw TagStoreError.ambiguousCaseMatch(tag: tag, matches: matches.map { existing[$0] })
        }

        var revised = existing
        let moved = revised.remove(at: matches[0])
        let insertion = try position.insertionIndex(count: revised.count)
        revised.insert(moved, at: insertion)
        return TagChange(before: existing, after: revised)
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
