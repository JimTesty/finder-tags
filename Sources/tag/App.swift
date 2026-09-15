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
        case .list, .match, .add, .remove, .set, .move:
            runTraversal()
        }

        finishUndo()
        return hadError ? ExitCode.ioError : 0
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

            let change = try store.copyChange(from: source.url, to: destination.url)
            try performMutation(
                "copy", target: destination, change: change, source: source
            )
        } catch {
            report("copying tags from \(sourcePath) to \(destinationPath): \(error.localizedDescription)")
        }
    }

    private func runUsage(_ query: [String]) {
        let traversal = Traversal(options: options, onError: report)
        var counter = UsageCounter()

        traversal.forEachTarget { target in
            do {
                let tags = try store.read(target.url)
                if tagsMatch(tags, query: query, caseSensitive: options.caseSensitive) {
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

    private func runFind(_ query: [String]) {
        do {
            try SpotlightSearch(options: options).forEachTarget(query: query) { target in
                do {
                    // Re-read the live Foundation value rather than trusting
                    // the metadata index for order or a just-changed file.
                    let tags = try store.read(target.url)
                    if tagsMatch(tags, query: query, caseSensitive: options.caseSensitive) {
                        try output.emitFile(target, tags: tags)
                    }
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

                case .match(let query):
                    let tags = try store.read(target.url)
                    if tagsMatch(tags, query: query, caseSensitive: options.caseSensitive) {
                        try output.emitFile(target, tags: tags)
                    }

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
