import Foundation

struct RestoreEngine {
    let document: ArchiveDocument
    let destinationRoot: URL
    let options: Options
    let store: TagStore
    let output: Output
    let onError: (String) -> Void
    let onWarning: (String) -> Void
    let beforeMutation: (Target, [String]) throws -> Void

    func run() -> ArchiveStats {
        var stats = ArchiveStats()

        do {
            guard try destinationRoot.checkResourceIsReachable() else {
                stats.errors += 1
                onError("restore root is not reachable: \(destinationRoot.path)")
                return stats
            }
            guard try destinationRoot.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                stats.errors += 1
                onError("restore root must be a directory: \(destinationRoot.path)")
                return stats
            }
        } catch {
            stats.errors += 1
            onError("cannot inspect restore root \(destinationRoot.path): \(error.localizedDescription)")
            return stats
        }

        warnAboutChangedSymlinks(&stats)

        var destinations: [String: URL] = [:]
        for entry in document.items {
            do {
                let destination = try destinationURL(for: entry.path)
                if destinations[entry.path] != nil {
                    // ArchiveReader already rejects conflicting duplicates. This
                    // guard keeps the preflight invariant local to restore too.
                    stats.errors += 1
                    onError("duplicate restore path: \(entry.path)")
                    continue
                }
                destinations[entry.path] = destination
            } catch {
                stats.errors += 1
                onError(error.localizedDescription)
            }
        }
        if stats.errors > 0 { return stats }

        for entry in document.items {
            guard let logicalURL = destinations[entry.path] else { continue }
            stats.visited += 1
            do {
                // Use a direct existence check here. Foundation can cache a
                // successful resource reachability result after a file has
                // been removed, which would misclassify a missing archive
                // item as a metadata-read error. A symlink itself exists even
                // when its referent does not.
                guard fileManager.fileExists(atPath: logicalURL.path)
                    || isSymbolicLink(logicalURL) else {
                    stats.missing += 1
                    onError("restore item is missing: \(entry.path)")
                    continue
                }

                let currentKind = try itemKind(for: logicalURL)
                guard currentKind == entry.kind else {
                    stats.errors += 1
                    onError(
                        "restore item type changed: \(entry.path) "
                        + "was \(entry.kind.rawValue), now \(currentKind.rawValue)"
                    )
                    continue
                }

                // An omitted tags field means that the exporter could not
                // safely read tags for this item. It must never be treated as
                // an empty array, because that would clear a live target.
                guard let archivedTags = entry.tags else {
                    continue
                }

                let ioURL = tagIOURL(logicalURL, followSymlinks: options.followSymlinks)
                let before = try store.read(ioURL)
                let change = TagChange(before: before, after: archivedTags)
                let target = Target(
                    url: ioURL,
                    logicalURL: logicalURL,
                    displayPath: entry.path,
                    rootPath: destinationRoot.path
                )

                if change.before == change.after {
                    stats.unchanged += 1
                    continue
                }

                if options.dryRun {
                    stats.changed += 1
                    if change.after.isEmpty { stats.cleared += 1 }
                } else {
                    try beforeMutation(target, change.before)
                    try store.apply(change, to: ioURL)
                    stats.changed += 1
                    stats.restored += 1
                    if change.after.isEmpty { stats.cleared += 1 }
                }
                try output.emitChange(
                    operation: "restore",
                    target: target,
                    change: change,
                    dryRun: options.dryRun
                )
            } catch {
                stats.errors += 1
                onError("\(entry.path): \(error.localizedDescription)")
            }
        }

        return stats
    }

    private func destinationURL(for path: String) throws -> URL {
        // ArchiveReader validates this too. Repeating the lexical check here
        // makes it impossible for a future reader change to turn a path into a
        // destination outside the selected root.
        if path.isEmpty || path.hasPrefix("/") || path == ".." {
            throw ArchiveError.invalidPath(path)
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        if components.contains(where: {
            let component = String($0)
            return component.isEmpty || component == "." || component == ".."
        }) && path != "." {
            throw ArchiveError.invalidPath(path)
        }
        return destinationRoot.appendingPathComponent(path).standardizedFileURL
    }

    private func warnAboutChangedSymlinks(_ stats: inout ArchiveStats) {
        guard options.followSymlinks else { return }
        for item in document.items where item.kind == .symlink {
            guard let archivedDestination = item.symlinkDestination,
                  let current = symbolicLinkInfo(
                    for: destinationRoot.appendingPathComponent(item.path)
                  ) else { continue }
            if current.destination != archivedDestination {
                stats.warnings += 1
                onWarning(
                    "symlink \(item.path) now points to \(current.destination), "
                    + "but the archive recorded \(archivedDestination); following the current target"
                )
            }

            if let archivedExists = item.symlinkTargetExists,
               archivedExists != current.targetExists {
                stats.warnings += 1
                onWarning(
                    "symlink \(item.path) target existence changed; "
                    + "following the current target"
                )
            } else if let archivedKind = item.symlinkTargetKind,
                      current.targetExists,
                      (current.targetIsDirectory ? ArchiveItemKind.directory : .file) != archivedKind {
                stats.warnings += 1
                onWarning(
                    "symlink \(item.path) target type changed; "
                    + "following the current target"
                )
            }
        }
    }

    private func itemKind(for logicalURL: URL) throws -> ArchiveItemKind {
        if isSymbolicLink(logicalURL) { return .symlink }
        let values = try tagIOURL(
            logicalURL,
            followSymlinks: options.followSymlinks
        ).resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true ? .directory : .file
    }
}
