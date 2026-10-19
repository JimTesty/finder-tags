import Foundation

final class App {
    private let options: Options
    private let store = TagStore()
    private let output: Output
    private var undoWriter: UndoWriter?
    private var hadError = false
    private var brokenSymlinks = Set<String>()
    private var mutationStats = MutationStats()

    init(options: Options) {
        self.options = options
        Diagnostics.colorMode = options.colorMode
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
                announcePath: !options.quiet
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
        case .list, .match, .filter, .add, .remove, .set, .move, .fix:
            runTraversal()
        }

        finishUndo()
        reportBrokenSymlinks()
        switch options.operation {
        case .add, .remove, .set, .move, .copy, .fix:
            do {
                try output.emitMutationSummary(mutationStats)
            } catch {
                report("writing mutation summary: \(error.localizedDescription)")
            }
        default:
            break
        }
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
        case .fix:
            info("repairing stored tags on traversed files")
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
        do {
            let rootURL: URL
            if let path = options.paths.first {
                rootURL = try argumentFileURL(
                    path,
                    resolveSymlinks: options.resolveSymlinksForArguments
                )
            } else {
                rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                    .standardizedFileURL
            }
            guard try checkedPathExists(rootURL, followSymlinks: true) else {
                report("export root is not reachable: \(rootURL.path)")
                return
            }
            guard try checkedItemKind(for: rootURL, followSymlinks: true) == .directory else {
                report("export root must be a directory: \(rootURL.path)")
                return
            }

            let writer = ArchiveWriter(options: options)
            let exportStore = TagStore(onWarning: { message in
                writer.noteWarning()
                self.warn(message)
            })
            try writer.emitRoot(rootURL)
            let traversal = Traversal(
                options: options,
                onError: { message in
                    writer.stats.errors += 1
                    self.report(message)
                }
            )
            traversal.forEachTarget { target in
                writer.stats.visited += 1
                do {
                    let link = try symbolicLinkInfo(for: target.logicalURL)
                    let isBroken = link?.targetIsMissing == true
                    if isBroken && self.noteBrokenSymlink(target) {
                        writer.noteWarning()
                    }
                    let tags: [StoredTag]?
                    do {
                        tags = try exportStore.readTags(target.url)
                    } catch {
                        // Omitted tags must never become a clear instruction
                        // when an unavailable symlink target is restored.
                        if link != nil {
                            tags = nil
                            if !isBroken {
                                writer.noteWarning()
                                self.warn("\(target.absolutePath): tags unavailable for symlink; recording the item without tags")
                            }
                        } else {
                            throw error
                        }
                    }

                    let metadata = self.optionalMetadata(for: target) { message in
                        writer.noteWarning()
                        self.warn(message)
                    }
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
            var archiveWarnings = 0
            let document = try ArchiveReader(onWarning: { message in
                archiveWarnings += 1
                self.warn(message)
            }).read(path: archivePath)
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
                onWarning: reportWarning,
                beforeMutation: { target, tags in
                    self.recordUndo(target: target, tags: tags)
                }
            )
            var stats = engine.run()
            stats.warnings += archiveWarnings
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
        reportError(message)
        hadError = true
        if options.isMutating { mutationStats.errors += 1 }
    }

    private func warn(_ message: String) {
        reportWarning(message)
    }

    @discardableResult
    private func noteBrokenSymlink(_ target: Target) -> Bool {
        brokenSymlinks.insert(target.logicalURL.path).inserted
    }

    private func reportBrokenSymlinks() {
        let count = brokenSymlinks.count
        guard count > 0 else { return }
        let links = count == 1 ? "symlink" : "symlinks"
        let targets = count == 1 ? "target" : "targets"
        var message = "\(count) \(links) with non-existent \(targets)"
        if case .export = options.operation, !options.fileInfo {
            message += "; target tags omitted"
        } else {
            let owner = count == 1 ? "its" : "their"
            message += "; using \(owner) own file info"
        }
        warn(message)
    }

    private func readTagsForDisplay(_ target: Target) throws -> [StoredTag] {
        let link: SymbolicLinkInfo?
        do {
            link = try symbolicLinkInfo(for: target.logicalURL)
        } catch {
            warn("\(target.absolutePath): symlink info unavailable: \(error.localizedDescription)")
            return try store.readTags(target.url)
        }
        if link?.targetIsMissing == true {
            noteBrokenSymlink(target)
            // Display can read the link itself; edits still require a readable
            // referent because their writes follow the symlink.
            return try store.readState(target.logicalURL, followSymlinks: false).tags
        }
        return try store.readTags(target.url)
    }

    private func optionalMetadata(
        for target: Target, onWarning: (String) -> Void = reportWarning
    ) -> FileMetadata? {
        guard options.fileInfo else { return nil }
        do {
            let metadata = try fileMetadata(for: target)
            if try symbolicLinkInfo(for: target.logicalURL)?.targetIsMissing == true {
                noteBrokenSymlink(target)
            }
            return metadata
        } catch {
            onWarning("\(target.absolutePath): file info unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    private func explicitTarget(_ path: String) throws -> Target {
        let logical = try argumentFileURL(
            path,
            resolveSymlinks: options.resolveSymlinksForArguments
        )
        return Target(
            url: tagIOURL(logical, followSymlinks: options.followSymlinks),
            logicalURL: logical,
            displayPath: options.absolutePaths ? logical.path : path,
            rootPath: logical.path
        )
    }

    private func runCopy() {
        mutationStats.visited += 1
        let sourcePath = options.paths[0]
        let destinationPath = options.paths[1]
        do {
            let source = try explicitTarget(sourcePath)
            let destination = try explicitTarget(destinationPath)
            guard try checkedPathExists(source.logicalURL, followSymlinks: true) else {
                fail("source is not reachable: \(sourcePath)", code: ExitCode.noInput)
            }
            guard try checkedPathExists(destination.logicalURL, followSymlinks: true) else {
                fail("destination is not reachable: \(destinationPath)", code: ExitCode.noInput)
            }
            if options.taggedOnly {
                let sourceTags = try store.read(source.url)
                if sourceTags.isEmpty {
                    mutationStats.skipped += 1
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

    private func queryMatches(_ tags: [StoredTag], query: TagQuery) -> Bool {
        if options.taggedOnly && tags.isEmpty { return false }
        return tagQueryMatches(tags.map { $0.name }, query: query, caseSensitive: options.caseSensitive)
    }

    private func emitMatchingTarget(_ target: Target, query: TagQuery) throws {
        let tags = try readTagsForDisplay(target)
        guard queryMatches(tags, query: query) else { return }
        let metadata = optionalMetadata(for: target)
        try output.emitFile(target, tags: tags, metadata: metadata)
    }

    private func passesTaggedOnlyForMutation(_ target: Target) throws -> Bool {
        guard options.taggedOnly else { return true }
        let tags = try store.read(target.url)
        if tags.isEmpty {
            mutationStats.skipped += 1
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
                let tags = try readTagsForDisplay(target)
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
                    let tags = try readTagsForDisplay(target)
                    let metadata = optionalMetadata(for: target)
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
            if options.isMutating { mutationStats.visited += 1 }
            do {
                switch options.operation {
                case .add, .remove, .set, .move:
                    guard try passesTaggedOnlyForMutation(target) else { return }
                default:
                    break
                }

                switch options.operation {
                case .list:
                    let tags = try readTagsForDisplay(target)
                    if !options.taggedOnly || !tags.isEmpty {
                        let metadata = optionalMetadata(for: target)
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

                case .fix:
                    let change = try store.fixChange(on: target.url)
                    if options.taggedOnly && change.beforeTags.isEmpty {
                        mutationStats.skipped += 1
                        info("skipping \(target.displayPath): no tags")
                        return
                    }
                    try performMutation("fix", target: target, change: change)

                case .copy, .usage, .find, .export, .restore, .convert:
                    preconditionFailure("operation handled outside traversal")
                }
            } catch {
                report("\(target.absolutePath): \(error.localizedDescription)")
            }
        }
    }

    @discardableResult
    private func performMutation(
        _ operation: String,
        target: Target,
        change rawChange: TagChange,
        source: Target? = nil
    ) throws -> TagChange {
        var change = sortedChangeIfRequested(rawChange, options: options)
        if !options.dryRun && change.hasChanges {
            recordUndo(target: target, tags: change.beforeTags)
            let after = try store.apply(change, to: target.url)
            change = TagChange(beforeTags: change.beforeTags, afterTags: after, repairs: change.repairs)
        }
        if change.hasChanges {
            mutationStats.filesUpdated += 1
            mutationStats.repairs.add(change.repairs)
        } else {
            mutationStats.unchanged += 1
        }
        try output.emitChange(
            operation: operation,
            target: target,
            change: change,
            source: source,
            dryRun: options.dryRun
        )
        return change
    }

    private func finishUndo() {
        do {
            try undoWriter?.finish()
        } catch {
            report("closing undo archive: \(error.localizedDescription); use --no-backup to run without backup")
        }
    }

    private func recordUndo(target: Target, tags: [StoredTag]) {
        do {
            try undoWriter?.record(target: target, tags: tags)
        } catch {
            // A backup failure stops the whole operation, rather than entering
            // the per-file recovery path and attempting later mutations.
            fail("backup failed before changing \(target.displayPath): \(error.localizedDescription); use --no-backup to run without backup",
                 code: ExitCode.ioError)
        }
    }
}
