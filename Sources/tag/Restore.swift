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

        warnAboutRedirectedSymlinks(&stats)

        var destinations: [String: URL] = [:]
        for entry in document.entries {
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

        for entry in document.entries {
            guard let logicalURL = destinations[entry.path] else { continue }
            stats.visited += 1
            do {
                guard try logicalURL.checkResourceIsReachable() else {
                    stats.missing += 1
                    onError("restore item is missing: \(entry.path)")
                    continue
                }

                let ioURL = tagIOURL(logicalURL, followSymlinks: options.followSymlinks)
                let before = try store.read(ioURL)
                let change = TagChange(before: before, after: entry.tags)
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
                } else {
                    try beforeMutation(target, change.before)
                    try store.apply(change, to: ioURL)
                    stats.changed += 1
                    stats.restored += 1
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

    private func warnAboutRedirectedSymlinks(_ stats: inout ArchiveStats) {
        guard options.followSymlinks else { return }
        for mapping in document.symlinks {
            guard let archivedPath = mapping.resolvedPath else { continue }
            let logicalURL = destinationRoot.appendingPathComponent(mapping.path)
            let current = resolvedTagURL(logicalURL).path
            if current != archivedPath {
                stats.warnings += 1
                onWarning(
                    "symlink \(mapping.path) resolved to \(current), "
                    + "but the archive recorded \(archivedPath); following the current target"
                )
            }
        }
    }
}
