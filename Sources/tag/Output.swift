import Foundation

final class Output {
    private let options: Options
    private let renderer: TextRenderer
    private var lastJSONRoot: String?

    init(options: Options, colors: FinderColors) {
        self.options = options
        self.renderer = TextRenderer(options: options, colors: colors)
    }

    func emitFile(
        _ target: Target,
        tags storedTags: [StoredTag],
        metadata: FileMetadata? = nil
    ) throws {
        var tags = options.sortedTags ? sortedStoredTags(storedTags) : storedTags
        if options.reverse { tags.reverse() }

        if options.jsonLines {
            try emitJSONState(for: target)
            var object = try pathObject(target)
            object["tags"] = tags.map { $0.name }
            object["colors"] = tagColorNumbers(tags)
            if let metadata = metadata {
                object["size"] = metadata.size
                object["mtime"] = metadata.modificationTime
            }
            try jsonRecord(object)
            return
        }

        let name = options.showNames
            ? try formattedPath(for: target)
            : nil
        emitText(
            name: name,
            tags: tags,
            metadata: metadata,
            isDirectory: metadata?.isDirectory == true
        )
    }

    func emitArchiveItem(_ item: ArchiveItem) throws {
        let storedTags = item.storedTags ?? []
        var tags = options.sortedTags ? sortedStoredTags(storedTags) : storedTags
        if options.reverse { tags.reverse() }

        let name: String?
        if options.showNames {
            name = formattedArchivePath(item)
        } else {
            name = nil
        }
        let isDirectory = item.kind == .directory || (
            item.kind == .symlink &&
                item.symlinkTargetExists == true &&
                item.symlinkTargetKind == .directory
        )
        emitText(name: name, tags: tags, metadata: item.metadata, isDirectory: isDirectory)
    }

    func emitUsage(_ entries: [UsageEntry]) throws {
        for entry in entries {
            if options.jsonLines {
                var object: [String: Any] = ["tag": entry.tag, "count": entry.count]
                object["colors"] = entry.colors.sorted()
                object["hasUnknownColor"] = entry.hasUnknownColor
                try jsonRecord(object)
            } else {
                let color = !entry.hasUnknownColor && entry.colors.count == 1 ? entry.colors.first : nil
                if options.verbose && entry.colors.count > 1 {
                    eprint("\(programName): info: tag '\(entry.tag)' has different stored colors \(entry.colors.sorted()); usage total is uncolored")
                }
                let separator = options.spaceIndent ? "  " : "\t"
                record("\(entry.count)\(separator)\(renderer.tag(StoredTag(name: entry.tag, color: color)))")
            }
        }
    }

    func emitSummary(_ stats: ArchiveStats, operation: String) throws {
        if options.jsonLines {
            var object: [String: Any] = [
                "type": "summary",
                "operation": operation,
                "visited": stats.visited,
                "changed": stats.changed,
                "restored": stats.restored,
                "cleared": stats.cleared,
                "unchanged": stats.unchanged,
                "missing": stats.missing,
                "skipped": stats.skipped,
                "errors": stats.errors,
                "warnings": stats.warnings
            ]
            if operation == "export" {
                object["tagged"] = stats.tagged
                object["emitted"] = stats.emitted
            }
            try jsonRecord(object)
            return
        }

        if options.quiet { return }

        if operation == "export" {
            eprint("\(programName): exported \(stats.tagged) tagged items (\(stats.visited) visited, \(stats.emitted) records, \(stats.errors) errors, \(stats.warnings) warnings)")
        } else {
            let outcomeCount = options.dryRun ? stats.changed : stats.restored
            let outcomeNoun = outcomeCount == 1 ? "item" : "items"
            let outcomeVerb = options.dryRun ? "would change" : "restored"
            let outcome = "\(outcomeCount) \(outcomeNoun) \(outcomeVerb)"
            let clearedNoun = stats.cleared == 1 ? "item" : "items"
            let cleared = options.dryRun
                ? "\(stats.cleared) \(clearedNoun) would have tags cleared"
                : "\(stats.cleared) \(clearedNoun) had tags cleared"
            let counts = summaryCounts([
                (outcomeCount, outcome), (stats.cleared, cleared),
                (stats.unchanged, "\(stats.unchanged) unchanged"),
                (stats.missing, "\(stats.missing) missing"),
                (stats.skipped, "\(stats.skipped) skipped"),
                (stats.errors, "\(stats.errors) errors"),
                (stats.warnings, "\(stats.warnings) warnings")
            ])
            let visited = options.verbose ? " (\(stats.visited) visited)" : ""
            eprint("\(programName): restore: \(counts)\(visited)")
        }
    }

    func emitChange(
        operation: String,
        target: Target,
        change: TagChange,
        source: Target? = nil,
        dryRun: Bool
    ) throws {
        if options.jsonLines {
            try emitJSONState(for: target)
            var object = try pathObject(target)
            object["operation"] = operation
            object["before"] = change.before
            object["after"] = change.after
            object["beforeColors"] = tagColorNumbers(change.beforeTags)
            object["afterColors"] = tagColorNumbers(change.afterTags)
            object["changed"] = change.hasChanges
            object["dryRun"] = dryRun
            object["metadataRepairs"] = ["fixed": change.repairs.fixed, "deleted": change.repairs.deleted]
            if let source = source { object["source"] = source.absolutePath }
            try jsonRecord(object)
            return
        }

        if !dryRun {
            guard !options.quiet else { return }
            guard change.hasChanges || options.singleMutationTarget || options.verbose else { return }
            let prefix = options.singleMutationTarget && options.paths.count == 1
                ? "" : renderer.text(target.displayPath) + ": "
            let action = changeAction(operation: operation, change: change, source: source)
            let repairNote = change.needsRepair
                ? " (\(change.repairs.fixed) tags fixed, \(change.repairs.deleted) deleted)" : ""
            let before = options.verbose
                ? " => Before (stored): \(renderedTags(change.beforeTags, detailed: true))" : ""
            let after = renderedTags(change.afterTags, displayOrder: true, detailed: options.verbose)
            record("\(prefix)\(action)\(repairNote)\(before) => Now: \(after)")
            return
        }

        // Previews remain visible even in quiet mode.
        let before = renderedTags(change.beforeTags, detailed: options.verbose)
        let after = renderedTags(change.afterTags, displayOrder: true, detailed: options.verbose)
        let marker = change.hasChanges ? "->" : "="
        let path = try formattedPath(for: target)
        let clearNote = change.hasChanges && change.after.isEmpty
            ? " (would clear tags)"
            : ""
        let repairNote = change.needsRepair
            ? " (would fix \(change.repairs.fixed) tags and delete \(change.repairs.deleted))"
            : ""
        let sourceText = source.map { " from " + renderer.text($0.displayPath) } ?? ""
        record("[dry-run] \(operation) \(path)\(sourceText)\t\(before) \(marker) \(after)\(clearNote)\(repairNote)")
    }

    func emitMutationSummary(_ stats: MutationStats) throws {
        let isFix: Bool
        if case .fix = options.operation { isFix = true } else { isFix = false }
        if options.jsonLines {
            guard isFix else { return }
            try jsonRecord([
                "type": "summary", "operation": "fix", "dryRun": options.dryRun,
                "tagsFixed": stats.repairs.fixed,
                "tagsDeleted": stats.repairs.deleted, "filesUpdated": stats.filesUpdated,
                "unchanged": stats.unchanged, "skipped": stats.skipped,
                "errors": stats.errors, "visited": stats.visited
            ])
            return
        }
        if options.quiet { return }
        guard !options.singleMutationTarget || options.verbose || stats.skipped != 0 || stats.errors != 0 else { return }
        let fileAction = options.dryRun ? "would change" : "changed"
        let files = stats.filesUpdated == 1 ? "file" : "files"
        var counts = [
            (stats.filesUpdated, "\(stats.filesUpdated) \(files) \(fileAction)"),
            (stats.unchanged, "\(stats.unchanged) unchanged"),
            (stats.skipped, "\(stats.skipped) skipped"),
            (stats.errors, "\(stats.errors) errors")
        ]
        if isFix || stats.repairs.total != 0 {
            counts += [
                (stats.repairs.fixed, "\(stats.repairs.fixed) tags \(options.dryRun ? "would be fixed" : "fixed")"),
                (stats.repairs.deleted, "\(stats.repairs.deleted) tags \(options.dryRun ? "would be deleted" : "deleted")")
            ]
        }
        let prefix = isFix ? "fix: " : ""
        let visited = options.verbose ? " (\(stats.visited) visited)" : ""
        eprint("\(programName): \(prefix)\(summaryCounts(counts))\(visited)")
    }

    private func summaryCounts(_ counts: [(Int, String)]) -> String {
        counts.enumerated().filter { index, count in
            index == 0 || count.0 != 0 || options.verbose
        }.map { $0.element.1 }.joined(separator: ", ")
    }

    private func renderedTags(_ stored: [StoredTag], displayOrder: Bool = false, detailed: Bool = false) -> String {
        var tags = displayOrder && options.sortedTags ? sortedStoredTags(stored) : stored
        if displayOrder && options.reverse { tags.reverse() }
        if tags.isEmpty { return "(empty)" }
        return tags.map { tag in
            renderer.tag(tag) + (detailed ? " [color \(tag.color.map(String.init) ?? "unknown")]" : "")
        }.joined(separator: ", ")
    }

    private func changeAction(operation: String, change: TagChange, source: Target?) -> String {
        if !change.hasChanges { return "Unchanged" }
        if change.beforeTags == change.afterTags { return "Repaired stored metadata" }
        if operation == "copy", let source = source {
            return "Copied tags from " + renderer.text(source.displayPath)
        }
        if change.afterTags.isEmpty { return "Cleared tags" }
        if operation == "restore" { return "Restored tags" }

        let beforeNames = Set(change.before), afterNames = Set(change.after)
        let added = change.afterTags.filter { !beforeNames.contains($0.name) }
        let removed = change.beforeTags.filter { !afterNames.contains($0.name) }
        if operation == "add", !added.isEmpty, removed.isEmpty {
            return "Added " + renderedTags(added)
        }
        if operation == "remove", !removed.isEmpty, added.isEmpty {
            return "Removed " + renderedTags(removed)
        }
        if operation == "add", added.count == 1, removed.count == 1,
           foldedTag(added[0].name) == foldedTag(removed[0].name) {
            return "Changed case " + renderedTags(removed) + " to " + renderedTags(added)
        }
        if beforeNames == afterNames {
            return change.before == change.after ? "Updated tag colors" : "Reordered tags"
        }
        return operation == "set" ? "Set tags" : "Updated tags"
    }

    private func emitText(
        name: String?, tags: [StoredTag], metadata: FileMetadata?, isDirectory: Bool = false
    ) {
        if options.verbose {
            for tag in tags {
                if let color = tag.color, !(0...7).contains(color) {
                    eprint("\(programName): info: tag '\(tag.name)' has unrecognized stored color \(color); displayed uncolored")
                }
            }
        }
        for line in renderer.fileRecords(formattedName: name, tags: tags, metadata: metadata, isDirectory: isDirectory) {
            record(line)
        }
    }

    private func formattedPath(for target: Target) throws -> String {
        do {
            if let link = try symbolicLinkInfo(for: target.logicalURL) {
                if let error = link.targetInspectionError {
                    reportWarning("\(target.absolutePath): symlink target info unavailable: \(error.localizedDescription)")
                }
                var path = renderer.path(
                    target.displayPath, isSymlink: true, isBrokenSymlink: link.targetIsMissing
                )
                if options.printSymlinks {
                    path += renderer.symlinkDestination(
                        link.destination, targetExists: link.targetExists, targetIsDirectory: link.targetIsDirectory == true
                    )
                }
                return path
            }
        } catch {
            reportWarning("\(target.absolutePath): symlink info unavailable; showing path without suffix: \(error.localizedDescription)")
            return renderer.path(target.displayPath)
        }

        var isDirectory = false
        if options.slashDirectories {
            do {
                isDirectory = try checkedItemKind(for: target.url, followSymlinks: true) == .directory
            } catch {
                reportWarning("\(target.absolutePath): cannot determine directory suffix; showing path without suffix: \(error.localizedDescription)")
            }
        }
        return renderer.path(target.displayPath, isDirectory: isDirectory)
    }

    private func formattedArchivePath(_ item: ArchiveItem) -> String {
        let path = renderer.path(
            item.path, isDirectory: item.kind == .directory && item.path != ".",
            isSymlink: item.kind == .symlink,
            isBrokenSymlink: item.kind == .symlink && item.symlinkTargetExists == false
        )
        guard options.printSymlinks, item.kind == .symlink else { return path }
        return path + renderer.symlinkDestination(
            item.symlinkDestination,
            targetExists: item.symlinkTargetExists,
            targetIsDirectory: item.symlinkTargetKind == .directory
        )
    }

    private func pathObject(_ target: Target) throws -> [String: Any] {
        let path: String
        if !options.absolutePaths, let root = target.rootPath {
            guard let relative = relativeLogicalPath(target.logicalURL, to: URL(fileURLWithPath: root)) else {
                throw ArchiveError.invalidPath(target.absolutePath)
            }
            path = relative
        } else {
            path = target.absolutePath
        }
        var object: [String: Any] = [
            "type": "item",
            "path": path
        ]
        let kind: ArchiveItemKind?
        do {
            kind = try checkedItemKind(for: target.logicalURL)
            object["kind"] = kind?.rawValue
        } catch {
            kind = nil
            reportWarning("\(target.absolutePath): file type unavailable; omitting kind: \(error.localizedDescription)")
        }
        if options.printSymlinks && kind == .symlink {
            do {
                if let link = try symbolicLinkInfo(for: target.logicalURL) {
                    object["destination"] = link.destination
                    if let exists = link.targetExists { object["targetExists"] = exists }
                    if let isDirectory = link.targetIsDirectory {
                        object["targetKind"] = isDirectory
                            ? ArchiveItemKind.directory.rawValue : ArchiveItemKind.file.rawValue
                    }
                    if let error = link.targetInspectionError {
                        reportWarning("\(target.absolutePath): symlink target info unavailable: \(error.localizedDescription)")
                    }
                }
            } catch {
                reportWarning("\(target.absolutePath): symlink info unavailable: \(error.localizedDescription)")
            }
        }
        return object
    }

    private func emitJSONState(for target: Target) throws {
        guard let root = target.rootPath, root != lastJSONRoot else { return }
        try jsonRecord(["type": "root", "path": root])
        lastJSONRoot = root
    }

    private func jsonRecord(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    private func record(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
        FileHandle.standardOutput.write(Data([options.nulTerminate ? 0 : 10]))
    }
}
