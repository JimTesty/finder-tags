import Foundation

enum TagStoreError: LocalizedError {
    case verificationFailed(path: String, expected: [StoredTag], actual: [StoredTag])
    case metadataStillNeedsRepair(path: String)
    case ambiguousCaseMatch(tag: String, matches: [String])
    case tagNotFound(tag: String)
    case anchorNotFound(tag: String)
    case invalidIndex(value: Int, count: Int)

    var errorDescription: String? {
        switch self {
        case let .verificationFailed(path, expected, actual):
            return "tag write verification failed for \(path): expected \(expected), read back \(actual)"
        case let .metadataStillNeedsRepair(path):
            return "tag write verification failed for \(path): read-back metadata still needs repair"
        case let .ambiguousCaseMatch(tag, matches):
            return "case-insensitive tag '\(tag)' is ambiguous among \(matches); use --case-sensitive or exact casing"
        case let .tagNotFound(tag):
            return "tag not found: \(tag)"
        case let .anchorNotFound(tag):
            return "placement anchor tag not found: \(tag)"
        case let .invalidIndex(value, count):
            return "index \(value) is out of range; valid insertion indexes are 0...\(count)"
        }
    }
}

struct TagStore {
    var onWarning: (String) -> Void = reportWarning

    func read(_ url: URL) throws -> [String] {
        try readTags(url).map { $0.name }
    }

    func readTags(_ url: URL) throws -> [StoredTag] {
        try readState(url).tags
    }

    func readState(_ url: URL) throws -> TagRead {
        if let state = try FileTagMetadata.readState(url, onWarning: onWarning) { return state }
        // A successful read with no tag value means "no tags". Any resource
        // value error throws and must never be converted into an empty array.
        let values = try url.resourceValues(forKeys: [.tagNamesKey, .labelNumberKey])
        let names = values.tagNames ?? []
        // A legacy Finder label describes one tag, not every tag on a file.
        let tags = names.map { StoredTag(name: $0, color: names.count == 1 ? values.labelNumber : nil) }
        return FileTagMetadata.repairTags(tags) { onWarning("\(url.path): \($0)") }
    }

    private func write(_ tags: [StoredTag], to url: URL, initialColorNames: Set<String>) throws -> [StoredTag] {
        // Repair before Foundation's initial-color/label writes as well as the
        // xattr write, so all writes and verification use the same usable data.
        let tags = FileTagMetadata.usableTags(tags) { onWarning("\(url.path): \($0)") }
        var finalTags = tags
        if !initialColorNames.isEmpty {
            // Only new/unknown names need macOS to choose an initial color.
            // Never use that name-based assignment for existing stored colors.
            try (url as NSURL).setResourceValue(tags.map { $0.name }, forKey: .tagNamesKey)
            var freshURL = url
            freshURL.removeAllCachedResourceValues()
            let assigned = try readTags(freshURL)
            finalTags = tags.map { tag in
                guard initialColorNames.contains(tag.name) else { return tag }
                return assigned.first { $0.name == tag.name } ?? tag
            }
        }

        #if canImport(Darwin)
        // Keep the legacy FinderInfo label in sync as well. Setting it may
        // rewrite the tag array, so restore the full per-tag values afterward.
        let label = finalTags.reversed().compactMap { $0.color }.first { (1...7).contains($0) } ?? 0
        try (url as NSURL).setResourceValue(label, forKey: .labelNumberKey)
        try FileTagMetadata.write(finalTags, to: url, onWarning: onWarning)
        #else
        try (url as NSURL).setResourceValue(finalTags.map { $0.name }, forKey: .tagNamesKey)
        #endif

        var freshURL = url
        freshURL.removeAllCachedResourceValues()
        let state = try readState(freshURL)
        if state.needsRepair { throw TagStoreError.metadataStillNeedsRepair(path: url.path) }
        let actual = state.tags
        if actual != finalTags {
            throw TagStoreError.verificationFailed(
                path: url.path,
                expected: finalTags,
                actual: actual
            )
        }
        return actual
    }

    func addChange(
        _ requested: [String],
        to url: URL,
        caseSensitive: Bool,
        position: PositionSpec?
    ) throws -> TagChange {
        let state = try readState(url)
        let existing = state.tags
        var revised = existing
        var missing: [StoredTag] = []

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
            if existing.contains(where: { $0.name == tag }) { continue }

            if !caseSensitive && requestedFoldCounts[foldedTag(tag)] == 1 {
                let matches = existing.indices.filter {
                    foldedTag(existing[$0].name) == foldedTag(tag)
                }
                if matches.count == 1 {
                    // Finder's tag matching is normally case-insensitive, but
                    // case is data. Re-case the unique existing match in place.
                    revised[matches[0]] = StoredTag(name: tag, color: existing[matches[0]].color)
                    continue
                }
                if matches.count > 1 {
                    throw TagStoreError.ambiguousCaseMatch(
                        tag: tag,
                        matches: matches.map { existing[$0].name }
                    )
                }
            }

            missing.append(StoredTag(name: tag))
        }

        if !missing.isEmpty {
            let insertion = try insertionIndex(
                for: position ?? .last,
                in: revised.map { $0.name },
                caseSensitive: caseSensitive
            )
            revised.insert(contentsOf: missing, at: insertion)
        }
        return TagChange(
            beforeTags: existing, afterTags: revised,
            initialColorNames: Set(missing.map { $0.name }), repairs: state.repairs
        )
    }

    func removeChange(
        _ requested: [String],
        from url: URL,
        caseSensitive: Bool
    ) throws -> TagChange {
        let state = try readState(url)
        let existing = state.tags
        let revised: [StoredTag]

        if requested.contains("*") {
            revised = []
        } else {
            revised = existing.filter { stored in
                !requested.contains(where: {
                    tagsEqual(stored.name, $0, caseSensitive: caseSensitive)
                })
            }
        }
        return TagChange(beforeTags: existing, afterTags: revised, repairs: state.repairs)
    }

    func setChange(_ requested: [String], on url: URL) throws -> TagChange {
        // Even destructive set reads first so a metadata read failure cannot be
        // misinterpreted as "the file has no tags".
        let state = try readState(url)
        let existing = state.tags
        let revised = requested.map { name in
            existing.first { $0.name == name } ?? StoredTag(name: name)
        }
        return TagChange(
            beforeTags: existing, afterTags: revised,
            initialColorNames: Set(requested.filter { name in !existing.contains { $0.name == name } }),
            repairs: state.repairs
        )
    }

    func fixChange(on url: URL) throws -> TagChange {
        let state = try readState(url)
        return TagChange(beforeTags: state.tags, afterTags: state.tags, repairs: state.repairs)
    }

    func moveChange(
        tag: String,
        to position: PositionSpec,
        on url: URL,
        caseSensitive: Bool
    ) throws -> TagChange {
        let state = try readState(url)
        let existing = state.tags
        let index = try uniqueMatchingIndex(
            tag: tag,
            in: existing.map { $0.name },
            caseSensitive: caseSensitive,
            missingAsAnchor: false
        )

        var revised = existing
        let moved = revised.remove(at: index)
        let insertion = try insertionIndex(
            for: position,
            in: revised.map { $0.name },
            caseSensitive: caseSensitive
        )
        revised.insert(moved, at: insertion)
        return TagChange(beforeTags: existing, afterTags: revised, repairs: state.repairs)
    }

    func copyChange(from source: URL, to destination: URL) throws -> TagChange {
        // Fully complete both reads before any possible destination write.
        let sourceTags = try readTags(source)
        let destinationState = try readState(destination)
        return TagChange(beforeTags: destinationState.tags, afterTags: sourceTags, repairs: destinationState.repairs)
    }

    @discardableResult
    func apply(_ change: TagChange, to url: URL) throws -> [StoredTag] {
        if change.hasChanges {
            return try write(change.afterTags, to: url, initialColorNames: change.initialColorNames)
        }
        return change.beforeTags
    }

    private func insertionIndex(
        for position: PositionSpec,
        in tags: [String],
        caseSensitive: Bool
    ) throws -> Int {
        switch position {
        case .first:
            return 0
        case .last:
            return tags.count
        case .index(let value):
            if value < 0 || value > tags.count {
                throw TagStoreError.invalidIndex(value: value, count: tags.count)
            }
            return value
        case .before(let anchor):
            return try uniqueMatchingIndex(
                tag: anchor,
                in: tags,
                caseSensitive: caseSensitive,
                missingAsAnchor: true
            )
        case .after(let anchor):
            return try uniqueMatchingIndex(
                tag: anchor,
                in: tags,
                caseSensitive: caseSensitive,
                missingAsAnchor: true
            ) + 1
        }
    }

    private func uniqueMatchingIndex(
        tag: String,
        in tags: [String],
        caseSensitive: Bool,
        missingAsAnchor: Bool
    ) throws -> Int {
        let matches: [Int]

        if caseSensitive {
            matches = tags.indices.filter { tags[$0] == tag }
        } else {
            let exact = tags.indices.filter { tags[$0] == tag }
            if exact.count == 1 {
                matches = exact
            } else if exact.count > 1 {
                throw TagStoreError.ambiguousCaseMatch(tag: tag, matches: exact.map { tags[$0] })
            } else {
                matches = tags.indices.filter { foldedTag(tags[$0]) == foldedTag(tag) }
            }
        }

        if matches.isEmpty {
            if missingAsAnchor { throw TagStoreError.anchorNotFound(tag: tag) }
            throw TagStoreError.tagNotFound(tag: tag)
        }
        if matches.count > 1 {
            throw TagStoreError.ambiguousCaseMatch(tag: tag, matches: matches.map { tags[$0] })
        }
        return matches[0]
    }
}
