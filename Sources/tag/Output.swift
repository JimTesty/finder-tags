import Foundation

final class Output {
    private let options: Options
    private let colors: FinderColors
    private var lastJSONRoot: String?

    var colorsForArchive: FinderColors { return colors }

    init(options: Options, colors: FinderColors) {
        self.options = options
        self.colors = colors
    }

    func emitFile(
        _ target: Target,
        tags storedTags: [String],
        metadata: FileMetadata? = nil
    ) throws {
        var tags = options.sortedTags ? sortedTagArray(storedTags) : storedTags
        if options.reverse { tags.reverse() }

        if options.jsonLines {
            emitJSONState(for: target)
            var object = pathObject(target)
            object["tags"] = tags
            if let metadata = metadata {
                object["size"] = metadata.size
                object["mtime"] = metadata.modificationTime
            }
            try jsonRecord(object)
            return
        }

        let name = options.showNames
            ? try formattedPath(
                for: target,
                slash: options.slashDirectories,
                printSymlink: options.printSymlinks,
                colors: colors
            )
            : nil
        try emitText(name: name, tags: tags, metadata: metadata)
    }

    func emitArchiveItem(_ item: ArchiveItem) throws {
        var tags = item.tags ?? []
        if options.reverse { tags.reverse() }

        let name: String?
        if options.showNames {
            name = formattedArchivePath(item)
        } else {
            name = nil
        }
        try emitText(name: name, tags: tags, metadata: item.metadata)
    }

    func emitUsage(_ entries: [UsageEntry]) throws {
        for entry in entries {
            if options.jsonLines {
                try jsonRecord(["tag": entry.tag, "count": entry.count])
            } else {
                record("\(entry.count)\t\(colors.render(entry.tag))")
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
        if options.jsonLines {
            emitJSONState(for: target)
            var object = pathObject(target)
            object["operation"] = operation
            object["before"] = change.before
            object["after"] = change.after
            object["changed"] = change.before != change.after
            object["dryRun"] = dryRun
            if let source = source { object["source"] = source.displayPath }
            try jsonRecord(object)
            return
        }

        // Mutations are quiet by default, matching jdberry/tag. Dry-run is
        // intentionally visible because its purpose is to preview changes.
        if !dryRun { return }

        let before = change.before.map(colors.render).joined(separator: ",")
        let after = change.after.isEmpty
            ? "(no tags)"
            : change.after.map(colors.render).joined(separator: ",")
        let marker = change.before == change.after ? "=" : "->"
        let path = try formattedPath(
            for: target,
            slash: options.slashDirectories,
            printSymlink: options.printSymlinks,
            colors: colors
        )
        let clearNote = change.before != change.after && change.after.isEmpty
            ? " (would clear tags)"
            : ""
        record("[dry-run] \(operation) \(path)\t\(before) \(marker) \(after)\(clearNote)")
    }

    private func emitText(name: String?, tags: [String], metadata: FileMetadata?) throws {
        let renderedTags = options.showTags ? tags.map(colors.render) : []
        let decoratedName: String?
        if let name = name, let metadata = metadata {
            let decoration = "[\(fileInfoDateText(metadata.modificationTime)) \(fileInfoSizeText(metadata.size))]"
            let coloredDecoration = colors.isEnabled
                ? "\u{001B}[32m\(decoration)\u{001B}[m"
                : decoration
            decoratedName = "\(coloredDecoration) \(name)"
        } else {
            decoratedName = name
        }

        if options.oneTagPerLine {
            if let value = decoratedName { record(value) }
            for tag in renderedTags {
                record((decoratedName == nil ? "" : "    ") + tag)
            }
            return
        }

        if let value = decoratedName {
            if renderedTags.isEmpty {
                record(value)
            } else if options.spaceIndent {
                record(value + "  " + renderedTags.joined(separator: ","))
            } else {
                let padding = max(0, 31 - (value as NSString).length)
                record(
                    value
                    + String(repeating: " ", count: padding)
                    + "\t"
                    + renderedTags.joined(separator: ",")
                )
            }
        } else if !renderedTags.isEmpty {
            record(renderedTags.joined(separator: ","))
        }
    }

    private func formattedArchivePath(_ item: ArchiveItem) -> String {
        var path = item.path
        if options.slashDirectories {
            if item.kind == .symlink {
                path += "@"
            } else if item.kind == .directory && path != "." {
                path += "/"
            }
        }

        guard options.printSymlinks, item.kind == .symlink else { return path }
        if let destination = item.symlinkDestination {
            var displayDestination = destination
            if options.slashDirectories,
               item.symlinkTargetExists == true,
               item.symlinkTargetKind == .directory,
               !displayDestination.hasSuffix("/") {
                displayDestination += "/"
            }
            path += " -> " + displayDestination
            if item.symlinkTargetExists == false {
                path += " " + colors.renderMissing("(NOT FOUND)")
            }
        } else {
            path += " -> (target not recorded)"
        }
        return path
    }

    private func pathObject(_ target: Target) -> [String: Any] {
        var object: [String: Any] = [
            "type": "item",
            "path": target.displayPath,
            "kind": itemKind(for: target).rawValue
        ]
        if let link = symbolicLinkInfo(for: target.logicalURL), options.printSymlinks {
            object["destination"] = link.destination
            object["targetExists"] = link.targetExists
            if link.targetExists {
                object["targetKind"] = link.targetIsDirectory
                    ? ArchiveItemKind.directory.rawValue
                    : ArchiveItemKind.file.rawValue
            }
        }
        return object
    }

    private func itemKind(for target: Target) -> ArchiveItemKind {
        if isSymbolicLink(target.logicalURL) { return .symlink }
        return (try? target.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            ? .directory
            : .file
    }

    private func fileInfoSizeText(_ bytes: Int64) -> String {
        let value: String
        if bytes == 0 {
            value = "0MB"
        } else {
            let megabytes = Double(bytes) / 1_048_576.0
            let rounded = Int(megabytes.rounded())
            value = rounded == 0 ? "~0MB" : "\(rounded)MB"
        }
        return String(repeating: " ", count: max(0, 6 - value.count)) + value
    }

    private func fileInfoDateText(_ seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private func emitJSONState(for target: Target) {
        guard let root = target.rootPath, root != lastJSONRoot else { return }
        lastJSONRoot = root
        let object: [String: Any] = ["type": "root", "path": root]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
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
