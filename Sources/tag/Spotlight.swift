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

    func forEachTarget(query: TagQuery, _ body: (Target) -> Void) throws {
        if options.pathInputExplicit && options.paths.isEmpty { return }
#if os(macOS)
        let metadataQuery = NSMetadataQuery()
        metadataQuery.predicate = predicate(for: query)

        if !options.paths.isEmpty {
            metadataQuery.searchScopes = options.paths.map { expandedFileURL($0) as Any }
        }

        metadataQuery.sortDescriptors = [NSSortDescriptor(key: "kMDItemDisplayName", ascending: true)]

        if !metadataQuery.start() { throw SpotlightError.failedToStart }
        while metadataQuery.isGathering {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        metadataQuery.disableUpdates()
        defer {
            metadataQuery.enableUpdates()
            metadataQuery.stop()
        }

        for index in 0..<metadataQuery.resultCount {
            guard let item = metadataQuery.result(at: index) as? NSMetadataItem,
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
    private func predicate(for query: TagQuery) -> NSPredicate {
        let key = "kMDItemUserTags"
        switch query {
        case .noTags:
            return NSPredicate(format: "NOT %K LIKE '*'", key)
        case .anyTag:
            return NSPredicate(format: "%K LIKE '*'", key)
        case .tag(let tag):
            if options.caseSensitive {
                return NSPredicate(format: "%K == %@", key, tag)
            }
            return NSPredicate(format: "%K ==[c] %@", key, tag)
        case .all(let queries):
            return compound(queries.map { predicate(for: $0) }, all: true)
        case .any(let queries):
            return compound(queries.map { predicate(for: $0) }, all: false)
        case .not(let query):
            return NSCompoundPredicate(notPredicateWithSubpredicate: predicate(for: query))
        }
    }

    private func compound(_ predicates: [NSPredicate], all: Bool) -> NSPredicate {
        if predicates.count == 1 { return predicates[0] }
        if all {
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
    }
#endif
}
