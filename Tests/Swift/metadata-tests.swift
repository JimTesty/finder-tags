import Foundation

enum MetadataTests {
    static func run(_ context: TestContext) throws {
        let decoded = try FileTagMetadata.decode(plist(["Custom\n3", "None\n0", "Odd\n99", "Negative\n-3", "Bare"]))
        expect(decoded.map { $0.color } == [3, 0, 99, -3, nil])
        let repairs: [(String, String, Int?)] = [
            ("Bad\nwrong", "Bad�wrong", nil), ("Bad\nname\n3", "Bad�name", 3),
            ("Bad\r\nName\n3", "Bad��Name", 3), ("Bad\0Name\n3", "Bad�Name", 3),
            ("Bad\rName", "Bad�Name", nil), ("Bad\r\n3", "Bad�", 3),
            ("Tail\n", "Tail�", nil), ("Overflow\n999999999999999999999999", "Overflow�999999999999999999999999", nil)
        ]
        for (raw, name, color) in repairs {
            var warnings: [String] = []
            let tags = try FileTagMetadata.decode(plist(["Yellow\n5", raw, "", "Keep\n0"])) { warnings.append($0) }
            expect(tags == [StoredTag(name: "Yellow", color: 5), StoredTag(name: name, color: color), StoredTag(name: "Keep", color: 0)])
            expect(warnings.contains { $0.contains("replaced with �") && $0.contains(name) })
            expect(warnings.contains { $0.contains("ignoring empty tag") })
        }
        var warnings: [String] = []
        let empty = try FileTagMetadata.decode(plist(["", "\n5"])) { warnings.append($0) }
        expect(empty.isEmpty && warnings.count == 2)
        warnings = []
        let mixed = try FileTagMetadata.decode(plist(["Yellow\n5", 42, ["Bad\n3"], "Tail\n0"] as [Any])) { warnings.append($0) }
        expect(mixed.first == StoredTag(name: "Yellow", color: 5) && mixed.last == StoredTag(name: "Tail", color: 0))
        expect(mixed.count == 4 && mixed[1] == StoredTag(name: "42"))
        expect(!containsInvalidTagCharacters(mixed[2].name) && mixed[2].name.contains("3"))
        expect(mixed[2].color == nil) // A converted description has no encoded color suffix.
        expect(warnings.filter { $0.contains("converted to text") }.count == 2)
        let extremes = try FileTagMetadata.decode(plist(["Min\n\(Int.min)", "Max\n\(Int.max)", "Min\n\(Int.min)"]))
        expect(extremes.map { $0.color } == [Int.min, Int.max, Int.min])
        let collision = try FileTagMetadata.decode(plist(["Same\rName\n3", "Same\0Name\n6"])) { _ in }
        expect(collision == [StoredTag(name: "Same�Name", color: 3), StoredTag(name: "Same�Name", color: 6)])

        for invalid in [try plist(["Not": "an array"]), Data([0xff, 0x00, 0x01])] {
            do {
                _ = try FileTagMetadata.decode(invalid)
                preconditionFailure("accepted unreadable tag metadata")
            } catch {}
        }
        for args in [["--move", "", "first"], ["--add", "New", "--before", ""], ["--add", "New", "--after", ""]] {
            let result = try context.run(args + ["--dry-run", "."], status: 64)
            expect(result.err.contains("tag name must not be empty"))
        }

        #if canImport(Darwin)
        let work = try context.makeWorkDirectory("metadata")
        let root = work.appendingPathComponent("root", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("imperfect")
        try Data().write(to: file)
        let raw = try plist(["Yellow\n5", "", "Bad\0Name\n3", "Wrong\ncolor", 42, "Odd\n99"] as [Any])
        let recovered = [StoredTag(name: "Yellow", color: 5), StoredTag(name: "Bad�Name", color: 3),
                         StoredTag(name: "Wrong�color"), StoredTag(name: "42"), StoredTag(name: "Odd", color: 99)]
        writeRawTagMetadata(raw, to: file)
        let listed = try context.run(["--jsonl", file.path])
        expect(try records(listed.out).last?["tags"] as? [String] == recovered.map { $0.name })
        expect(listed.err.contains(file.path) && listed.err.contains("warning:") && listed.err.contains("replaced with �"))
        for operation in ["--match", "--filter"] {
            let matched = try context.run([operation, "Yellow", "--jsonl", file.path])
            expect(try records(matched.out).last?["tags"] as? [String] == recovered.map { $0.name })
        }
        let repairedQuery = try context.run(["--filter", "Bad\rName", "--jsonl", file.path])
        expect(try records(repairedQuery.out).last?["tags"] as? [String] == recovered.map { $0.name })
        expect(repairedQuery.err.contains("replaced with �"))
        let usage = try records(context.run(["--usage", "*", "--jsonl", file.path]).out)
        expect(usage.compactMap { $0["tag"] as? String } == recovered.map { $0.name })
        expect(usage.allSatisfy { $0["count"] as? Int == 1 })

        let exported = try context.run(["--export", root.path, "--no-file-info"])
        let exportRecords = try records(exported.out)
        expect(exportRecords.first { $0["path"] as? String == "imperfect" }?["tags"] as? [String] == recovered.map { $0.name })
        expect(exportRecords.last?["warnings"] as? Int == 5 && exportRecords.last?["errors"] as? Int == 0)
        let archive = work.appendingPathComponent("export.jsonl")
        try Data(exported.out.utf8).write(to: archive)

        let dry = try context.run(["--add", "New", "--dry-run", "--jsonl", file.path])
        expect(try records(dry.out).last?["before"] as? [String] == recovered.map { $0.name })
        warnings = []
        _ = try FileTagMetadata.read(file) { warnings.append($0) }
        expect(warnings.count == 5) // Reads and dry runs leave the raw metadata alone.

        let edits = [["--add", "New"], ["--remove", "Yellow"], ["--set", "Yellow,Fresh"],
                     ["--move", "Bad\rName", "first"], ["--add", "New", "--before", "Bad\rName"],
                     ["--set", "New\r\nTag,Yellow"]]
        for (index, args) in edits.enumerated() {
            writeRawTagMetadata(raw, to: file)
            let undo = work.appendingPathComponent("undo-\(index).jsonl")
            let changed = try context.run(args + ["--jsonl", file.path, "--backup", undo.path])
            let record = try records(changed.out).last!
            expect(record["before"] as? [String] == recovered.map { $0.name })
            expect(try ArchiveReader().read(path: undo.path).items.first?.storedTags == recovered)
            warnings = []
            let after = try FileTagMetadata.read(file) { warnings.append($0) }!
            expect(warnings.isEmpty && record["after"] as? [String] == after.map { $0.name })
            for tag in after where recovered.contains(where: { $0.name == tag.name }) {
                expect(recovered.contains(tag), "editing lost a recovered tag's stored color")
            }
        }

        let destination = work.appendingPathComponent("destination")
        try Data().write(to: destination)
        writeRawTagMetadata(raw, to: file)
        writeRawTagMetadata(try plist(["Before\n4", ""]), to: destination)
        let copied = try context.run(["--copy", file.path, destination.path, "--no-backup"])
        expect(copied.err.contains(file.path) && copied.err.contains(destination.path))
        expect(try FileTagMetadata.read(destination) == recovered)

        writeRawTagMetadata(try plist(["Changed\n6", ""]), to: file)
        let restored = try records(context.run(["--restore", archive.path, "--jsonl", "--no-backup"]).out)
        expect(restored.last?["warnings"] as? Int == 1 && restored.last?["restored"] as? Int == 1)
        expect(try FileTagMetadata.read(file) == recovered)

        // The raw writer also repairs names, including both scalars in CRLF.
        warnings = []
        try FileTagMetadata.write([StoredTag(name: ""), StoredTag(name: "CR\r\nNUL\0", color: 3)], to: destination) { warnings.append($0) }
        expect(try FileTagMetadata.read(destination) == [StoredTag(name: "CR��NUL�", color: 3)])
        expect(warnings.count == 2 && warnings.allSatisfy { $0.contains(destination.path) })

        // An unreadable payload still fails before a mutation or undo write;
        // other files in a traversal must continue to be processed.
        let broken = root.appendingPathComponent("broken")
        try Data().write(to: broken)
        writeRawTagMetadata(Data([0xff, 0x00, 0x01]), to: broken)
        let invalidUndo = work.appendingPathComponent("invalid-undo.jsonl")
        _ = try context.run(["--set", "Healthy", broken.path, "--backup", invalidUndo.path], status: 74)
        expect(!fileManager.fileExists(atPath: invalidUndo.path))
        let partial = try records(context.run(["--export", root.path, "--no-file-info"], status: 74).out)
        expect(partial.contains { $0["path"] as? String == "imperfect" })
        expect(partial.last?["errors"] as? Int == 1)

        let dangling = work.appendingPathComponent("dangling")
        try fileManager.createSymbolicLink(atPath: dangling.path, withDestinationPath: "missing")
        let missingInfo = try context.run(["--file-info", "--jsonl", dangling.path])
        expect(try records(missingInfo.out).last?["kind"] as? String == "symlink")
        expect(try records(missingInfo.out).last?["size"] == nil)
        expect(missingInfo.err.contains("warning:") && missingInfo.err.contains("file info unavailable"))
        #endif
    }
}
