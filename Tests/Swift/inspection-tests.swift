import Foundation

#if canImport(Darwin)
enum InspectionTests {
    static func run(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("inspection")
        let root = work.appendingPathComponent("root", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let regular = root.appendingPathComponent("regular")
        let tags = [StoredTag(name: "Keep", color: 0)]
        try taggedFile(regular, tags: tags)
        let loop = root.appendingPathComponent("loop")
        let dangling = root.appendingPathComponent("dangling")
        try fileManager.createSymbolicLink(atPath: loop.path, withDestinationPath: "loop")
        try fileManager.createSymbolicLink(atPath: dangling.path, withDestinationPath: "missing")
        let info = try symbolicLinkInfo(for: loop)!
        expect(info.targetExists == nil && info.targetIsDirectory == nil)
        expect(info.targetInspectionError != nil && !info.targetIsMissing)
        expect(try symbolicLinkInfo(for: dangling)?.targetIsMissing == true)

        // ELOOP gives a deterministic inspection failure, without permissions
        // changes that could prevent fixture cleanup after a failed assertion.
        let unavailable = loop.appendingPathComponent("file")
        let inspections: [() throws -> Void] = [
            { _ = try checkedPathExists(unavailable) },
            { _ = try argumentFileURL(unavailable.path, resolveSymlinks: true) }
        ]
        for inspect in inspections {
            do {
                try inspect()
                expect(false, "inspection failure was hidden")
            } catch {
                expect(!isMissingPathError(error))
            }
        }
        let target = Target(url: regular, logicalURL: unavailable, displayPath: unavailable.path, rootPath: nil)
        var options = Options()
        options.jsonLines = true
        options.verbosity = -1
        let json = try captureOutput {
            try Output(options: options, colors: FinderColors(enabled: false)).emitFile(target, tags: tags)
        }
        let item = try records(json.out).last!
        expect(item["tags"] as? [String] == ["Keep"] && item["kind"] == nil)
        expect(json.err.contains("file type unavailable; omitting kind"))
        options.jsonLines = false
        options.slashDirectories = true
        let text = try captureOutput {
            try Output(options: options, colors: FinderColors(enabled: false)).emitFile(target, tags: tags)
        }
        expect(text.out.contains(unavailable.path) && text.out.contains("Keep"))
        expect(text.err.contains("symlink info unavailable"))

        let exported = try context.run(["--export", "-L", "--no-file-info", root.path], status: 74)
        let items = try records(exported.out)
        let loopItem = items.first { $0["path"] as? String == "loop" }!
        expect(loopItem["kind"] as? String == "symlink" && loopItem["destination"] as? String == "loop")
        expect(loopItem["targetExists"] == nil && loopItem["targetKind"] == nil)
        expect(items.first { $0["path"] as? String == "dangling" }?["targetExists"] as? Bool == false)
        expect(exported.err.contains("symlink target info unavailable"))
        let archive = work.appendingPathComponent("export.jsonl")
        try Data(exported.out.utf8).write(to: archive)
        let converted = try context.run(["--convert", archive.path, "--no-tags"])
        expect(converted.out.split(separator: "\n").first { $0.hasPrefix("loop") } == "loop")

        let restore = work.appendingPathComponent("restore.jsonl")
        try writeTestArchive([archiveItem("loop/file")], root: root, to: restore,
                             headerPatch: ["followSymlinks": true])
        let failed = try context.run(["--restore", restore.path, "-L", "--no-backup", "--jsonl"], status: 74)
        let summary = try records(failed.out).last!
        expect(summary["errors"] as? Int == 1 && summary["missing"] as? Int == 0)
        expect(summary["changed"] as? Int == 0)
        expect(try TagStore().readTags(regular) == tags)
    }
}
#endif
