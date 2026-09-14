import Foundation

final class Output {
    private let options: Options
    private let colors: FinderColors
    private var jsonRecords: [[String: Any]] = []

    init(options: Options, colors: FinderColors) {
        self.options = options
        self.colors = colors
    }

    func emitFile(_ target: Target, tags storedTags: [String]) throws {
        var tags = storedTags
        if options.reverse { tags.reverse() }

        if options.json {
            jsonRecords.append([
                "path": target.displayPath,
                "tags": tags
            ])
            return
        }

        let renderedTags = options.showTags ? tags.map(colors.render) : []
        let name = options.showNames ? try displayPath(target) : nil

        if options.oneTagPerLine {
            if let value = name { record(value) }
            for tag in renderedTags {
                record((name == nil ? "" : "    ") + tag)
            }
            return
        }

        if let value = name {
            if renderedTags.isEmpty {
                record(value)
            } else {
                let padding = max(1, 31 - value.count)
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

    func emitUsage(_ entries: [UsageEntry]) {
        if options.json {
            for entry in entries {
                jsonRecords.append(["tag": entry.tag, "count": entry.count])
            }
            return
        }

        for entry in entries {
            record("\(entry.count)\t\(colors.render(entry.tag))")
        }
    }

    func emitDryRun(
        operation: String,
        target: Target,
        change: TagChange,
        sourcePath: String? = nil
    ) {
        if options.json {
            var object: [String: Any] = [
                "operation": operation,
                "path": target.displayPath,
                "before": change.before,
                "after": change.after,
                "changed": change.before != change.after
            ]
            if let source = sourcePath { object["source"] = source }
            jsonRecords.append(object)
            return
        }

        let before = change.before.map(colors.render).joined(separator: ",")
        let after = change.after.map(colors.render).joined(separator: ",")
        let marker = change.before == change.after ? "=" : "->"
        record("[dry-run] \(operation) \(target.displayPath)\t\(before) \(marker) \(after)")
    }

    func finish() throws {
        if !options.json { return }
        let data = try JSONSerialization.data(
            withJSONObject: jsonRecords,
            options: [.prettyPrinted, .sortedKeys]
        )
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }

    private func displayPath(_ target: Target) throws -> String {
        if !options.slashDirectories { return target.displayPath }
        let values = try target.url.resourceValues(forKeys: [.isDirectoryKey])
        if values.isDirectory != true { return target.displayPath }
        return target.displayPath.hasSuffix("/") ? target.displayPath : target.displayPath + "/"
    }

    private func record(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
        FileHandle.standardOutput.write(Data([options.nulTerminate ? 0 : 10]))
    }
}
