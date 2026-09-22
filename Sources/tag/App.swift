import Foundation

final class App {
    private let options: Options
    private let store = TagStore()
    private let output: Output
    private var undoWriter: UndoWriter?
    private var hadError = false

    init(options: Options) {
        self.options = options
        self.output = Output(
            options: options,
            colors: FinderColors(
                enabled: !options.jsonLines && colorIsEnabled(options.colorMode)
            )
        )
        if options.isMutating && !options.dryRun && options.backupEnabled {
            self.undoWriter = UndoWriter(
                path: options.backupPath ?? defaultUndoArchivePath(),
                syncEachRecord: options.syncBackup,
                followSymlinks: options.followSymlinks,
                tagColors: output.colorsForArchive.archiveTagColors
            )
        }
    }

    func run() -> Int32 {
        announceOperation()
        switch options.operation {
        case .copy:
            runCopy()
        case .export:
            runExport()
        case .restore:
            runRestore()
        case .convert:
            runConvert()
        case .usage(let query):
            runUsage(query)
        case .find(let query):
            runFind(query)
        case .list, .match, .filter, .add, .remove, .set, .move:
            runTraversal()
        }

        finishUndo()
        return hadError ? ExitCode.ioError : 0
    }

    private func info(_ message: String) {
        if options.verbose {
            eprint("\(programName): info: \(message)")
        }
    }

    private func announceOperation() {
        switch options.operation {
        case .list:
            info("listing traversed files")
        case .export:
            info("exporting a JSONL archive")
        case .restore:
            info("restoring archive tags")
        case .convert:
            info("converting an archive for display")
        case .add:
            info("adding tags to traversed files")
        case .remove:
            info("removing tags from traversed files")
        case .set:
            info("setting tags on traversed files")
        case .copy:
            info("copying tags between files")
        case .match:
            info("matching traversed files by tag query")
        case .filter:
            info("matching traversed files by tag query and showing tags")
        case .usage:
            info("counting tags on directly traversed matching files")
        case .find:
            info("searching Spotlight; indexed results determine membership")
        case .move:
            info("moving tags on traversed files")
        }
        if options.taggedOnly {
            info("tagged-only filtering is enabled")
        }
    }

    private func runExport() {
        if options.reverseWasSet {
            warn("--reverse is ignored during export; JSONL stores natural tag order")
        }

        let rootURL: URL
        if let path = options.paths.first {
            rootURL = expandedFileURL(path)
        } else {
            rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .standardizedFileURL
        }

        do {
            guard try rootURL.checkResourceIsReachable() else {
                report("export root is not reachable: \(rootURL.path)")
                return
            }
            guard try rootURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                report("export root must be a directory: \(rootURL.path)")
                return
            }

            let writer = ArchiveWriter(options: options, colors: output.colorsForArchive)
            try writer.emitRoot(rootURL)
            let traversal = Traversal(
                options: options,
                onError: { message in
                    writer.stats.errors += 1
                    self.report(message)
                }
            )
            traversal.forEachTarget { target in
                let tags: [String]?
                do {
                    tags = try self.store.read(target.url)
                } catch {
                    // Foundation may not expose a usable tag value for a
                    // symlink itself, or for a dangling target with -L.
                    // Omitting tags is distinct from an observed empty array,
                    // so restore will not clear a live target accidentally.
                    // Keep the item so -L archives retain the link structure.
                    if isSymbolicLink(target.logicalURL) {
                        tags = nil
                        writer.noteWarning()
                        self.warn("\(target.absolutePath): tags unavailable for symlink; recording the item without tags")
                    } else {
                        writer.stats.errors += 1
                        writer.stats.visited += 1
                        self.report("\(target.absolutePath): \(error.localizedDescription)")
                        return
                    }
                }

                let metadata: FileMetadata?
                if options.fileInfo {
                    do {
                        metadata = try fileMetadata(for: target)
                    } catch {
                        metadata = nil
                        writer.noteWarning()
                        self.warn("\(target.absolutePath): file size or modification time is unavailable")
                    }
                } else {
                    metadata = nil
                }
                do {
                    try writer.emitTarget(target, tags: tags, metadata: metadata)
                } catch {
                    writer.stats.errors += 1
                    self.report("\(target.absolutePath): \(error.localizedDescription)")
                }
            }
            try writer.finish()
        } catch {
            report("export failed: \(error.localizedDescription)")
        }
    }

    private func runRestore() {
        guard let archivePath = options.archivePath else {
            report("--restore requires an archive path or '-'")
            return
        }

        do {
            let document = try ArchiveReader().read(path: archivePath)
            guard document.header.followSymlinks == options.followSymlinks else {
                throw ArchiveError.modeMismatch(
                    archive: document.header.followSymlinks,
                    requested: options.followSymlinks
                )
            }
            let destinationRoot = expandedFileURL(options.restoreRoot ?? document.rootPath)
            let engine = RestoreEngine(
                document: document,
                destinationRoot: destinationRoot,
                options: options,
                store: store,
                output: output,
                onError: report,
                onWarning: { message in
                    eprint("\(programName): warning: \(message)")
                },
                beforeMutation: { target, tags in
                    try self.recordUndo(target: target, tags: tags)
                }
            )
            let stats = engine.run()
            try output.emitSummary(stats, operation: "restore")
        } catch {
            report("restore failed: \(error.localizedDescription)")
        }
    }

    private func runConvert() {
        guard let archivePath = options.archivePath else {
            report("--convert requires an archive path or '-'")
            return
        }

        do {
            let document = try ArchiveReader().read(path: archivePath)
            let converter = ArchiveConverter(
                document: document,
                options: options,
                output: output
            )
            try converter.run()
        } catch {
            report("conversion failed: \(error.localizedDescription)")
        }
    }

    private func report(_ message: String) {
        eprint("\(programName): \(message)")
        hadError = true
    }

    private func warn(_ message: String) {
        eprint("\(programName): warning: \(message)")
    }

    private func explicitTarget(_ path: String) -> Target {
        let logical = expandedFileURL(path)
        return Target(
            url: tagIOURL(logical, followSymlinks: options.followSymlinks),
            logicalURL: logical,
            displayPath: options.absolutePaths ? logical.path : path,
            rootPath: logical.path
        )
    }

    private func runCopy() {
        let sourcePath = options.paths[0]
        let destinationPath = options.paths[1]
        let source = explicitTarget(sourcePath)
        let destination = explicitTarget(destinationPath)

        do {
            guard try source.logicalURL.checkResourceIsReachable() else {
                fail("source is not reachable: \(sourcePath)", code: ExitCode.noInput)
            }
            guard try destination.logicalURL.checkResourceIsReachable() else {
                fail("destination is not reachable: \(destinationPath)", code: ExitCode.noInput)
            }
            if options.taggedOnly {
                let sourceTags = try store.read(source.url)
                if sourceTags.isEmpty {
                    info("copy skipped for \(source.displayPath): source has no tags")
                    return
                }
            }
            let change = try store.copyChange(from: source.url, to: destination.url)
            try performMutation(
                "copy", target: destination, change: change, source: source
            )
        } catch {
            report("copying tags from \(sourcePath) to \(destinationPath): \(error.localizedDescription)")
        }
    }

    private func queryMatches(_ tags: [String], query: TagQuery) -> Bool {
        if options.taggedOnly && tags.isEmpty { return false }
        return tagQueryMatches(tags, query: query, caseSensitive: options.caseSensitive)
    }

    private func emitMatchingTarget(_ target: Target, query: TagQuery) throws {
        let tags = try store.read(target.url)
        guard queryMatches(tags, query: query) else { return }
        let metadata = options.fileInfo
            ? try fileMetadata(for: target)
            : nil
        try output.emitFile(target, tags: tags, metadata: metadata)
    }

    private func passesTaggedOnlyForMutation(_ target: Target) throws -> Bool {
        guard options.taggedOnly else { return true }
        let tags = try store.read(target.url)
        if tags.isEmpty {
            info("skipping \(target.displayPath): no tags")
            return false
        }
        return !tags.isEmpty
    }

    private func runUsage(_ query: TagQuery) {
        let traversal = Traversal(options: options, onError: report)
        var counter = UsageCounter()

        traversal.forEachTarget { target in
            do {
                let tags = try store.read(target.url)
                if queryMatches(tags, query: query) {
                    counter.add(tags)
                }
            } catch {
                report("\(target.absolutePath): \(error.localizedDescription)")
            }
        }

        do {
            try output.emitUsage(
                counter.entries(sorted: options.sortedTags, reverse: options.reverse)
            )
        } catch {
            report("writing output: \(error.localizedDescription)")
        }
    }

    private func runFind(_ query: TagQuery) {
        let spotlightQuery = options.taggedOnly
            ? .all([query, .anyTag])
            : query
        do {
            try SpotlightSearch(options: options).forEachTarget(query: spotlightQuery) { target in
                do {
                    // Spotlight's complete predicate determines membership.
                    // Read the current value only for display and metadata
                    // ordering, without applying a second live-tag filter.
                    let tags = try store.read(target.url)
                    let metadata = options.fileInfo
                        ? try fileMetadata(for: target)
                        : nil
                    try output.emitFile(target, tags: tags, metadata: metadata)
                } catch {
                    report("\(target.absolutePath): \(error.localizedDescription)")
                }
            }
        } catch {
            report(error.localizedDescription)
        }
    }

    private func runTraversal() {
        let traversal = Traversal(options: options, onError: report)

        traversal.forEachTarget { target in
            do {
                switch options.operation {
                case .add, .remove, .set, .move:
                    guard try passesTaggedOnlyForMutation(target) else { return }
                default:
                    break
                }

                switch options.operation {
                case .list:
                    let tags: [String]
                    do {
                        tags = try store.read(target.url)
                    } catch {
                        if let link = symbolicLinkInfo(for: target.logicalURL), !link.targetExists {
                            tags = []
                        } else {
                            throw error
                        }
                    }
                    if !options.taggedOnly || !tags.isEmpty {
                        let metadata = options.fileInfo
                            ? try fileMetadata(for: target)
                            : nil
                        try output.emitFile(target, tags: tags, metadata: metadata)
                    }

                case .match(let query), .filter(let query):
                    try emitMatchingTarget(target, query: query)

                case .add(let tags):
                    let change = try store.addChange(
                        tags,
                        to: target.url,
                        caseSensitive: options.caseSensitive,
                        position: options.position
                    )
                    try performMutation("add", target: target, change: change)

                case .remove(let tags):
                    let change = try store.removeChange(
                        tags,
                        from: target.url,
                        caseSensitive: options.caseSensitive
                    )
                    try performMutation("remove", target: target, change: change)

                case .set(let tags):
                    let change = try store.setChange(tags, on: target.url)
                    try performMutation("set", target: target, change: change)

                case .move(let tag, let explicitPosition):
                    guard let position = explicitPosition ?? options.position else {
                        preconditionFailure("move position validated by CLI")
                    }
                    let change = try store.moveChange(
                        tag: tag,
                        to: position,
                        on: target.url,
                        caseSensitive: options.caseSensitive
                    )
                    try performMutation("move", target: target, change: change)

                case .copy, .usage, .find, .export, .restore, .convert:
                    preconditionFailure("operation handled outside traversal")
                }
            } catch {
                report("\(target.absolutePath): \(error.localizedDescription)")
            }
        }
    }

    private func performMutation(
        _ operation: String,
        target: Target,
        change rawChange: TagChange,
        source: Target? = nil
    ) throws {
        let change = sortedChangeIfRequested(rawChange, options: options)
        if !options.dryRun && change.before != change.after {
            try recordUndo(target: target, tags: change.before)
            try store.apply(change, to: target.url)
        }
        try output.emitChange(
            operation: operation,
            target: target,
            change: change,
            source: source,
            dryRun: options.dryRun
        )
    }

    private func finishUndo() {
        do {
            try undoWriter?.finish()
        } catch {
            report("closing undo archive: \(error.localizedDescription)")
        }
    }

    private func recordUndo(target: Target, tags: [String]) throws {
        try undoWriter?.record(target: target, tags: tags)
    }
}
