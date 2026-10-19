import Foundation

struct RestoreEngine {
    let document: ArchiveDocument
    let destinationRoot: URL
    let options: Options
    let store: TagStore
    let output: Output
    let onError: (String) -> Void
    let onWarning: (String) -> Void
    let beforeMutation: (Target, [StoredTag]) throws -> Void

    func run() -> ArchiveStats {
        var stats = ArchiveStats()

        do {
            guard try checkedPathExists(destinationRoot, followSymlinks: true) else {
                stats.errors += 1
                onError("restore root is not reachable: \(destinationRoot.path)")
                return stats
            }
            guard try checkedItemKind(for: destinationRoot, followSymlinks: true) == .directory else {
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

        for entry in document.items {
            do {
                _ = try destinationURL(for: entry.path)
            } catch {
                stats.errors += 1
                onError(error.localizedDescription)
            }
        }
        if stats.errors > 0 { return stats }

        var store = self.store
        store.onWarning = { message in
            stats.warnings += 1
            onWarning(message)
        }

        // Undo records contain chronological preimages. Reverse them so aliases
        // of the same file return to the state before the first mutation.
        let items = document.header.purpose == "undo"
            ? Array(document.items.reversed()) : document.items
        for entry in items {
            if options.taggedOnly && (entry.tags == nil || entry.tags!.isEmpty) {
                continue
            }
            stats.visited += 1
            do {
                // Repeat path and parent checks immediately before this item.
                let logicalURL = try destinationURL(for: entry.path)
                // Use an uncached lstat, preserving inspection failures as
                // errors. A dangling symlink is still an existing item.
                let currentKind: ArchiveItemKind
                do {
                    currentKind = try checkedItemKind(for: logicalURL)
                } catch {
                    if isMissingPathError(error) {
                        stats.missing += 1
                        onError("restore item is missing: \(entry.path)")
                        continue
                    }
                    throw error
                }

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
                guard entry.tags != nil else {
                    stats.skipped += 1
                    stats.warnings += 1
                    onWarning("restore skipped \(entry.path): archive has no tags for this item")
                    continue
                }

                let ioURL = tagIOURL(logicalURL, followSymlinks: options.followSymlinks)
                let state = try store.readState(ioURL)
                let before = state.tags
                var after = entry.storedTags!
                if entry.colors == nil {
                    // Only a missing array uses the old name-only behavior.
                    // Explicit null entries must restore the missing suffix.
                    after = after.map { tag in before.first { $0.name == tag.name } ?? tag }
                }
                let change = sortedChangeIfRequested(
                    TagChange(beforeTags: before, afterTags: after, repairs: state.repairs), options: options
                )
                let target = Target(
                    url: ioURL,
                    logicalURL: logicalURL,
                    displayPath: entry.path,
                    rootPath: destinationRoot.path
                )

                if !change.hasChanges {
                    stats.unchanged += 1
                    continue
                }

                if options.dryRun {
                    stats.changed += 1
                    if change.after.isEmpty { stats.cleared += 1 }
                } else {
                    try beforeMutation(target, change.beforeTags)
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
        try validateRelativeArchivePath(path)
        let destination = destinationRoot.appendingPathComponent(path).standardizedFileURL
        guard relativeLogicalPath(destination, to: destinationRoot) != nil else {
            throw ArchiveError.invalidPath(path)
        }
        if !options.followSymlinks {
            var ancestor = destinationRoot
            for component in path.utf8.split(separator: 47).dropLast() {
                ancestor.appendPathComponent(String(decoding: component, as: UTF8.self))
                if try checkedSymbolicLink(ancestor) { throw ArchiveError.symlinkAncestor(ancestor.path) }
            }
        }
        return destination
    }

    private func warnAboutChangedSymlinks(_ stats: inout ArchiveStats) {
        guard options.followSymlinks else { return }
        for item in document.items where item.kind == .symlink {
            guard let archivedDestination = item.symlinkDestination else { continue }
            do {
                guard let current = try symbolicLinkInfo(
                    for: destinationRoot.appendingPathComponent(item.path)
                ) else { continue }
                if current.destination != archivedDestination {
                    stats.warnings += 1
                    onWarning(
                        "symlink \(item.path) now points to \(current.destination), "
                        + "but the archive recorded \(archivedDestination); following the current target"
                    )
                }

                if let error = current.targetInspectionError {
                    throw error
                }
                if let archivedExists = item.symlinkTargetExists,
                   let currentExists = current.targetExists,
                   archivedExists != currentExists {
                    stats.warnings += 1
                    onWarning(
                        "symlink \(item.path) target existence changed; "
                        + "following the current target"
                    )
                } else if let archivedKind = item.symlinkTargetKind,
                          let isDirectory = current.targetIsDirectory,
                          (isDirectory ? ArchiveItemKind.directory : .file) != archivedKind {
                    stats.warnings += 1
                    onWarning(
                        "symlink \(item.path) target type changed; "
                        + "following the current target"
                    )
                }
            } catch {
                // The item loop reports confirmed missing paths separately.
                if isMissingPathError(error) { continue }
                stats.warnings += 1
                onWarning("\(item.path): symlink comparison unavailable: \(error.localizedDescription)")
            }
        }
    }
}
