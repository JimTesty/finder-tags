import Foundation

#if canImport(Darwin)
enum RepairTests {
    static func run(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("repairs")
        let file = work.appendingPathComponent("file")
        try Data().write(to: file)
        let corrupt = try plist(["Yellow\n5", ""])
        let yellow = [StoredTag(name: "Yellow", color: 5)]

        // A metadata-only repair is a real change even when tag arrays match.
        let edits = [["--set", "Yellow"], ["--add", "Yellow"], ["--remove", "Missing"],
                     ["--move", "Yellow", "first"], ["--set", "Yellow", "--sorted-tags"], ["--fix"], ["--repair"]]
        for (index, args) in edits.enumerated() {
            writeRawTagMetadata(corrupt, to: file)
            let undo = work.appendingPathComponent("undo-\(index).jsonl")
            let dry = try records(context.run(args + [file.path, "--jsonl", "--dry-run", "--backup-path", undo.path]).out)
            let preview = dry.first { $0["type"] as? String == "item" }!
            expect(preview["changed"] as? Bool == true)
            expect((preview["metadataRepairs"] as? [String: Int])?["deleted"] == 1)
            expect(readRawTagMetadata(file) == corrupt && !fileManager.fileExists(atPath: undo.path))

            let result = try records(context.run(args + [file.path, "--jsonl", "--backup-path", undo.path]).out)
            let event = result.first { $0["type"] as? String == "item" }!
            expect(event["before"] as? [String] == ["Yellow"] && event["after"] as? [String] == ["Yellow"])
            expect(event["changed"] as? Bool == true)
            let rawNames = try PropertyListSerialization.propertyList(from: readRawTagMetadata(file), format: nil) as? [String]
            expect(rawNames == ["Yellow\n5"], "mutation left the empty tag in the raw xattr")
            expect(try ArchiveReader().read(path: undo.path).items.first?.storedTags == yellow)
            let clean = readRawTagMetadata(file)
            let unusedUndo = work.appendingPathComponent("unused-\(index).jsonl")
            let repeated = try records(context.run(args + [file.path, "--jsonl", "--backup-path", unusedUndo.path]).out)
            expect(repeated.first { $0["type"] as? String == "item" }?["changed"] as? Bool == false)
            expect(readRawTagMetadata(file) == clean && !fileManager.fileExists(atPath: unusedUndo.path))
        }

        let duplicateRaw = try plist(["Yellow\n5", "Yellow\n3", "Yellow\n0"])
        let uniqueNames = ["Yellow", "Yellow�", "Yellow��"]
        writeRawTagMetadata(duplicateRaw, to: file)
        let listedDuplicates = try context.run(["--jsonl", file.path])
        expect(try records(listedDuplicates.out).last?["tags"] as? [String] == uniqueNames)
        expect(listedDuplicates.err.contains("duplicate tag name 'Yellow' renamed to 'Yellow��'"))
        expect(readRawTagMetadata(file) == duplicateRaw)
        let duplicateUndo = work.appendingPathComponent("duplicate-undo.jsonl")
        let duplicatePreview = try records(context.run(["--fix", file.path, "--dry-run", "--jsonl", "--backup-path", duplicateUndo.path]).out)
        expect(duplicatePreview.last?["tagsFixed"] as? Int == 2 && duplicatePreview.last?["tagsDeleted"] as? Int == 0)
        expect(readRawTagMetadata(file) == duplicateRaw && !fileManager.fileExists(atPath: duplicateUndo.path))
        let fixedDuplicates = try records(context.run(["--fix", file.path, "--jsonl", "--backup-path", duplicateUndo.path]).out)
        expect(fixedDuplicates.last?["tagsFixed"] as? Int == 2 && fixedDuplicates.last?["tagsDeleted"] as? Int == 0)
        let rawUnique = try PropertyListSerialization.propertyList(from: readRawTagMetadata(file), format: nil) as? [String]
        expect(rawUnique == ["Yellow\n5", "Yellow�\n3", "Yellow��\n0"])
        expect(try ArchiveReader().read(path: duplicateUndo.path).items.first?.tags == uniqueNames)
        let cleanDuplicates = readRawTagMetadata(file)
        let repeatedFix = try records(context.run(["--fix", file.path, "--jsonl", "--no-backup"]).out)
        expect(repeatedFix.last?["tagsFixed"] as? Int == 0 && readRawTagMetadata(file) == cleanDuplicates)
        let usage = try records(context.run(["--usage", "*", file.path, "--jsonl"]).out)
        expect(usage.compactMap { $0["tag"] as? String } == uniqueNames)
        expect(usage.allSatisfy { $0["count"] as? Int == 1 })
        _ = try context.run(["--move", "Yellow�", "first", file.path, "--no-backup"])
        expect(try FileTagMetadata.read(file)?.first == StoredTag(name: "Yellow�", color: 3))

        let repeatedInput = try context.run(["--set", "Yellow,Yellow,Yellow", file.path, "--dry-run", "--jsonl"])
        expect(try records(repeatedInput.out).last?["after"] as? [String] == ["Yellow"])
        expect(repeatedInput.err.components(separatedBy: "duplicate command-line tag 'Yellow' ignored").count == 3)
        let repairedInput = try context.run(["--set", "Line\rTag,Line\nTag,Line�Tag�", file.path, "--jsonl", "--no-backup"])
        expect(try records(repairedInput.out).last?["after"] as? [String] == ["Line�Tag", "Line�Tag��", "Line�Tag�"])
        expect(repairedInput.err.contains("duplicate repaired command-line tag 'Line�Tag' renamed to 'Line�Tag��'"))
        expect(try FileTagMetadata.readState(file)?.needsRepair == false)

        // Multiple illegal characters and multiple warnings still count once
        // per changed entry. Unknown integer colors remain ordinary data.
        let imperfect = try plist(["Yellow\n5", "", "Bad\0Name\n3", "Wrong\ncolor", 42, "\n5", "CR\r\nName\n99"] as [Any])
        writeRawTagMetadata(imperfect, to: file)
        let dry = try context.run(["--fix", file.path, "--dry-run"])
        expect(dry.out.contains("would fix 4 tags and delete 2"))
        expect(!dry.err.contains("would fix 4 tags and delete 2"))
        expect(readRawTagMetadata(file) == imperfect)
        let fixed = try records(context.run(["--fix", file.path, "--jsonl", "--no-backup"]).out)
        expect(fixed.last?["tagsFixed"] as? Int == 4 && fixed.last?["tagsDeleted"] as? Int == 2)
        expect(fixed.last?["tagsChanged"] == nil)
        expect(fixed.last?["filesUpdated"] as? Int == 1 && fixed.last?["errors"] as? Int == 0)
        var warnings: [String] = []
        let state = try FileTagMetadata.readState(file) { warnings.append($0) }!
        expect(!state.needsRepair && warnings.isEmpty)
        expect(state.tags == [StoredTag(name: "Yellow", color: 5), StoredTag(name: "Bad�Name", color: 3),
                              StoredTag(name: "Wrong�color"), StoredTag(name: "42"), StoredTag(name: "CR��Name", color: 99)])

        // Healthy XML metadata must not be rewritten into the writer's binary
        // encoding, nor gain an undo archive merely because --fix was used.
        let healthyXML = try PropertyListSerialization.data(fromPropertyList: ["Odd\n99", "Bare"], format: .xml, options: 0)
        writeRawTagMetadata(healthyXML, to: file)
        let unusedUndo = work.appendingPathComponent("healthy-undo.jsonl")
        let healthy = try context.run(["--fix", file.path, "--backup-path", unusedUndo.path])
        expect(healthy.out == "Unchanged => Now: Odd, Bare\n" && healthy.err.isEmpty)
        expect(readRawTagMetadata(file) == healthyXML && !fileManager.fileExists(atPath: unusedUndo.path))

        writeRawTagMetadata(try plist(["", "\n3"]), to: file)
        let emptied = try records(context.run(["--fix", file.path, "--jsonl", "--no-backup"]).out)
        expect(emptied.last?["tagsFixed"] as? Int == 0 && emptied.last?["tagsDeleted"] as? Int == 2)
        expect(try FileTagMetadata.read(file)?.isEmpty == true)

        // Copy repairs only its destination; reading a damaged source alone
        // does not authorize changing that source.
        let source = work.appendingPathComponent("source")
        try taggedFile(source, tags: yellow)
        writeRawTagMetadata(corrupt, to: file)
        let copied = try records(context.run(["--copy", source.path, file.path, "--jsonl", "--no-backup"]).out)
        expect(copied.last?["changed"] as? Bool == true)
        expect(try FileTagMetadata.readState(file)?.needsRepair == false)
        writeRawTagMetadata(corrupt, to: source)
        let sourceOnly = try records(context.run(["--copy", source.path, file.path, "--jsonl", "--no-backup"]).out)
        expect(sourceOnly.last?["changed"] as? Bool == false && readRawTagMetadata(source) == corrupt)

        let archive = work.appendingPathComponent("restore.jsonl")
        try writeTestArchive([archiveItem("file", tags: yellow)], root: work, to: archive)
        writeRawTagMetadata(corrupt, to: file)
        let restored = try records(context.run(["--restore", archive.path, "--jsonl", "--no-backup"]).out)
        expect(restored.last?["restored"] as? Int == 1 && restored.last?["unchanged"] as? Int == 0)
        expect(try FileTagMetadata.readState(file)?.needsRepair == false)

        // A failed backup aborts before the repair or a success summary.
        let occupied = work.appendingPathComponent("occupied.jsonl")
        try Data("existing".utf8).write(to: occupied)
        writeRawTagMetadata(corrupt, to: file)
        let failed = try context.run(["--fix", file.path, "--backup-path", occupied.path, "--jsonl"], status: 74)
        expect(failed.out.isEmpty && readRawTagMetadata(file) == corrupt)

        let root = work.appendingPathComponent("tree", isDirectory: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try fileManager.createDirectory(at: nested, withIntermediateDirectories: true)
        let child = nested.appendingPathComponent("child")
        try taggedFile(child, tags: yellow)
        writeRawTagMetadata(corrupt, to: child)
        let broken = root.appendingPathComponent("broken")
        try Data().write(to: broken)
        let unreadable = Data([0xff, 0x00, 0x01])
        writeRawTagMetadata(unreadable, to: broken)
        let recursive = try records(context.run(["--fix", "-R", root.path, "--no-sort-files", "--jsonl", "--no-backup"], status: 74).out)
        expect(recursive.last?["tagsDeleted"] as? Int == 1 && recursive.last?["filesUpdated"] as? Int == 1)
        expect(recursive.last?["errors"] as? Int == 1)
        expect(readRawTagMetadata(broken) == unreadable)
        expect(try FileTagMetadata.readState(child)?.needsRepair == false)

        for operation in ["--fix", "--repair"] {
            _ = try context.run([operation], status: 64)
            _ = try context.run([operation + "=yes", file.path], status: 64)
        }
    }
}
#endif
