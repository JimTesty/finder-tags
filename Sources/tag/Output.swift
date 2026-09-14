import Foundation

final class Output {
    private let options: Options
    private let colors: FinderColors
    private var lastJSONRoot: String?
    private var emittedJSONSymlinks = Set<String>()

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
            try emitJSONState(for: target)
            var object = pathObject(target)
            object["tags"] = tags
            if let metadata = metadata {
                object["size"] = metadata.size
                object["mtime"] = metadata.modificationTime
            }
            try jsonRecord(object)
            return
        }

        let renderedTags = options.showTags ? tags.map(colors.render) : []
        let name = options.showNames ? try displayPath(target) : nil
        let decoratedName: String?
       if let name = name, let metadata = metadata {
            decoratedName = "[\(fileInfoDateText(metadata.modificationTime)) \(fileInfoSizeText(metadata.size))] \(name)"
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
                "unchanged": stats.unchanged,
                "missing": stats.missing,
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
            eprint("\(programName): exported \(stats.tagged) tagged items (\(stats.visited) visited, \(stats.emitted) records, \(stats.errors) errors)")
        } else {
            let changed = options.dryRun ? "\(stats.changed) would change" : "\(stats.changed) changed"
            eprint("\(programName): restored \(stats.restored) files (\(changed), \(stats.visited) visited, \(stats.unchanged) unchanged, \(stats.missing) missing, \(stats.errors) errors, \(stats.warnings) warnings)")
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
            var object = pathObject(target)
            object["operation"] = operation
            object["before"] = change.before
            object["after"] = change.after
            object["changed"] = change.before != change.after
            object["dryRun"] = dryRun
            if let source = source {
                object["source"] = source.displayPath
            }
            try jsonRecord(object)
            return
        }

        // Mutations are quiet by default, matching jdberry/tag. Dry-run is
        // intentionally visible because its purpose is to preview changes.
        if !dryRun { return }

        let before = change.before.map(colors.render).joined(separator: ",")
        let after = change.after.map(colors.render).joined(separator: ",")
        let marker = change.before == change.after ? "=" : "->"
        record("[dry-run] \(operation) \(target.displayPath)\t\(before) \(marker) \(after)")
    }

   private func pathObject(_ target: Target) -> [String: Any] {
       return ["path": target.displayPath]
   }

    private func fileInfoSizeText(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0MB" }
        let megabytes = Double(bytes) / 1_048_576.0
        let rounded = Int(megabytes.rounded())
        return rounded == 0 ? "~0MB" : "\(rounded)MB"
    }

    private func fileInfoDateText(_ seconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private func emitJSONState(for target: Target) throws {
        if let root = target.rootPath, root != lastJSONRoot {
            try jsonRecord(["type": "root", "path": root])
            lastJSONRoot = root
            emittedJSONSymlinks.removeAll()
        }

        guard isSymbolicLink(target.logicalURL) else { return }
        let key = (target.rootPath ?? "") + "\n" + target.logicalURL.path
        guard emittedJSONSymlinks.insert(key).inserted else { return }
        try jsonRecord([
            "type": "symlink",
            "path": target.displayPath,
            "resolvedPath": target.resolvedPath
        ])
    }

    private func displayPath(_ target: Target) throws -> String {
        if !options.slashDirectories { return target.displayPath }
        let values = try target.url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory != true { return target.displayPath }
        return target.displayPath.hasSuffix("/") ? target.displayPath : target.displayPath + "/"
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
