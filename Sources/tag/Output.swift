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
            eprint("\(programName): restore: \(outcome), \(cleared), \(stats.unchanged) unchanged, \(stats.missing) missing, \(stats.skipped) skipped, \(stats.errors) errors, \(stats.warnings) warnings (\(stats.visited) visited)")
        }
    }

    func emitChange(
        operation: String,
        target: Target,
        change: TagChange,
        source: Target? = nil,
        dryRun: Bool
    ) throws {
        if options.verbose {
            let transition: String
            if !change.hasChanges {
                transition = "unchanged"
            } else {
                transition = "\(verboseTags(change.beforeTags)) -> \(verboseTags(change.afterTags))"
            }
            let sourceText = source.map { " from \($0.displayPath)" } ?? ""
            let action = dryRun ? "would \(operation)" : operation
            let repairNote = change.needsRepair ? " (repair stored metadata)" : ""
            eprint("\(programName): info: \(action) \(target.displayPath)\(sourceText): \(transition)\(repairNote)")
        }

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

        // Mutations are quiet by default, matching jdberry/tag. Dry-run is
        // intentionally visible because its purpose is to preview changes.
        if !dryRun { return }

        let before = change.beforeTags.map { renderer.tag($0) }.joined(separator: ",")
        let after = change.after.isEmpty
            ? "(no tags)"
            : change.afterTags.map { renderer.tag($0) }.joined(separator: ",")
        let marker = change.hasChanges ? "->" : "="
        let path = try formattedPath(for: target)
        let clearNote = change.hasChanges && change.after.isEmpty
            ? " (would clear tags)"
            : ""
        let repairNote = change.needsRepair
            ? " (would fix \(change.repairs.fixed) tags and delete \(change.repairs.deleted))"
            : ""
        record("[dry-run] \(operation) \(path)\t\(before) \(marker) \(after)\(clearNote)\(repairNote)")
    }

    func emitFixSummary(_ stats: FixStats) throws {
        if options.jsonLines {
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
        let action = options.dryRun
            ? "would fix \(stats.repairs.fixed) tags and delete \(stats.repairs.deleted)"
            : "\(stats.repairs.fixed) tags fixed, \(stats.repairs.deleted) deleted"
        let fileAction = options.dryRun ? "would be updated" : "updated"
        let files = stats.filesUpdated == 1 ? "file" : "files"
        eprint("\(programName): fix: \(action); \(stats.filesUpdated) \(files) \(fileAction), \(stats.unchanged) unchanged, \(stats.skipped) skipped, \(stats.errors) errors (\(stats.visited) visited)")
    }

    private func verboseTags(_ tags: [StoredTag]) -> String {
        tags.isEmpty ? "(no tags)" : tags.map {
            "\($0.name) [color \($0.color.map(String.init) ?? "unknown")]"
        }.joined(separator: ",")
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
