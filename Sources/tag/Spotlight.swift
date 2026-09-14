import Foundation

enum SpotlightError: LocalizedError {
    case unavailable
    case failedToStart

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Spotlight --find is available only on macOS"
        case .failedToStart:
            return "Spotlight metadata query failed to start"
        }
    }
}

struct SpotlightSearch {
    let options: Options

    func forEachTarget(query tags: [String], _ body: (Target) -> Void) throws {
        if options.pathInputExplicit && options.paths.isEmpty { return }
#if os(macOS)
        let query = NSMetadataQuery()
        query.predicate = predicate(for: tags)

        if !options.paths.isEmpty {
            query.searchScopes = options.paths.map { expandedFileURL($0) as Any }
        }

        query.sortDescriptors = [NSSortDescriptor(key: "kMDItemDisplayName", ascending: true)]

        if !query.start() { throw SpotlightError.failedToStart }
        while query.isGathering {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        query.disableUpdates()
        defer {
            query.enableUpdates()
            query.stop()
        }

        for index in 0..<query.resultCount {
            guard let item = query.result(at: index) as? NSMetadataItem,
                  let path = item.value(forAttribute: "kMDItemPath") as? String
            else { continue }

            let logicalURL = URL(fileURLWithPath: path).standardizedFileURL
            let ioURL = tagIOURL(logicalURL, followSymlinks: options.followSymlinks)
            let displayPath = logicalURL.path // jdberry/tag --find emits paths.
            body(Target(
                url: ioURL,
                logicalURL: logicalURL,
                displayPath: displayPath,
                rootPath: nil
            ))
        }
#else
        throw SpotlightError.unavailable
#endif
    }

#if os(macOS)
    private func predicate(for tags: [String]) -> NSPredicate {
        let key = "kMDItemUserTags"
        if tags.contains("*") {
            return NSPredicate(format: "%K LIKE '*'", key)
        }
        if tags.isEmpty {
            return NSPredicate(format: "NOT %K LIKE '*'", key)
        }

        let comparisons = tags.map { tag -> NSPredicate in
            if options.caseSensitive {
                return NSPredicate(format: "%K == %@", key, tag)
            }
            return NSPredicate(format: "%K ==[c] %@", key, tag)
        }
        if comparisons.count == 1 { return comparisons[0] }
        return NSCompoundPredicate(andPredicateWithSubpredicates: comparisons)
    }
#endif
}
