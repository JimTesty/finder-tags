import Foundation
#if canImport(Darwin)
enum ArchiveTests {
    static func run(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("archive-colors")
        let purple = "\u{001B}[48;5;129m"
        let reset = "\u{001B}[m"
        let root = work.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        let original = colorFixtureTags
        let uncolored = original.map { StoredTag(name: $0.name, color: $0.name == "PurplePlus" ? 0 : $0.color) }
        try taggedFile(source, tags: original)
        try taggedFile(destination, tags: uncolored)
        let store = TagStore()
        let archive = work.appendingPathComponent("export.jsonl")
        let exported = try context.run(["--export", "--no-file-info", root.path]).out
        try Data(exported.utf8).write(to: archive)
        let exportedRecords = try records(exported)
        let sourceRecord = exportedRecords.first { $0["path"] as? String == "source" }!
        expect(sourceRecord["colors"] as? [Int] == [5, 3, 3, 0, 99])
        let converted = try context.run(["--convert", archive.path, "--color=force"]).out
        expect(converted.contains(purple + "PurplePlus" + reset))
        try FileTagMetadata.write(uncolored, to: source)
        _ = try context.run(["--restore", archive.path, "--no-backup"])
        expect(try store.readTags(source) == original)

        // Old records restore names while retaining known destination colors.
        let legacy = work.appendingPathComponent("legacy.jsonl")
        var legacyRecords = exportedRecords
        for index in legacyRecords.indices { legacyRecords[index].removeValue(forKey: "colors") }
        try writeRecords(legacyRecords, to: legacy)
        _ = try context.run(["--restore", legacy.path, "--no-backup"])
        expect(try store.readTags(source) == original)
        let oldConverted = try context.run(["--convert", legacy.path, "--color=force"]).out
        expect(!oldConverted.contains("\u{001B}["))

        try FileTagMetadata.write(original, to: destination)
        for bad: Any in [[3], [5, 3, true, 0, 99], [5, 3, 2.5, 0, 99]] {
            var malformed = exportedRecords
            let index = malformed.firstIndex { $0["path"] as? String == "source" }!
            malformed[index]["colors"] = bad
            let path = work.appendingPathComponent("invalid.jsonl")
            try writeRecords(malformed, to: path)
            _ = try context.run(["--restore", path.path, "--no-backup"], status: 74)
            expect(try store.readTags(source) == original)
            expect(try store.readTags(destination) == original)
        }

        let safety = try context.makeWorkDirectory("archive-validation")
        let safetyRoot = safety.appendingPathComponent("root", isDirectory: true)
        let outside = safety.appendingPathComponent("outside", isDirectory: true)
        try fileManager.createDirectory(at: safetyRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        let baseline = [StoredTag(name: "Keep", color: 0)]
        let good = safetyRoot.appendingPathComponent("good")
        let outsideFile = outside.appendingPathComponent("victim")
        let unicodeFile = safety.appendingPathComponent("\u{0301}victim")
        try taggedFile(good, tags: baseline)
        try taggedFile(outsideFile, tags: baseline)
        try taggedFile(unicodeFile, tags: baseline)
        try fileManager.createSymbolicLink(atPath: safetyRoot.appendingPathComponent("sub").path,
                                           withDestinationPath: "../outside")
        let safetyArchive = safety.appendingPathComponent("archive.jsonl")
        func safetyDocument(_ items: [[String: Any]], headerPatch: [String: Any] = [:]) throws {
            try writeTestArchive(items, root: safetyRoot, to: safetyArchive, headerPatch: headerPatch)
        }

        try safetyDocument([archiveItem("good")])
        var truncated = try records(String(contentsOf: safetyArchive, encoding: .utf8))
        truncated.removeLast()
        try writeRecords(truncated, to: safetyArchive)
        _ = try context.run(["--restore", safetyArchive.path, "--no-backup"], status: 74)
        expect(try store.readTags(good) == baseline)

        // Reject escapes before even an earlier, valid record can change tags.
        for path in ["../\u{0301}victim", "sub/victim"] {
            try safetyDocument([archiveItem("good"), archiveItem(path)])
            _ = try context.run(["--restore", safetyArchive.path, "--no-backup"], status: 74)
            expect(try store.readTags(good) == baseline)
            expect(try store.readTags(outsideFile) == baseline)
            expect(try store.readTags(unicodeFile) == baseline)
        }
        // Explicit following remains supported with a matching archive mode.
        try safetyDocument([archiveItem("sub/victim")], headerPatch: ["followSymlinks": true])
        _ = try context.run(["--restore", safetyArchive.path, "-L", "--no-backup"])
        expect(try store.readTags(outsideFile) == [StoredTag(name: "Changed", color: 3)])

        // A real filename beginning with a combining character is not an escape.
        let validUnicode = safetyRoot.appendingPathComponent("\u{0301}valid")
        try taggedFile(validUnicode, tags: baseline)
        let unicodeExport = try context.run(["--export", safetyRoot.path, "--no-file-info"]).out
        expect(try records(unicodeExport).contains { $0["path"] as? String == "\u{0301}valid" })

        for patch: [String: Any] in [["version": 3.9], ["purpose": 42], ["followSymlinks": "true"],
                                     ["followSymlinks": 1], ["fileInfo": []], ["taggedOnly": NSNull()]] {
            try safetyDocument([archiveItem("good")], headerPatch: patch)
            _ = try context.run(["--restore", safetyArchive.path, "--no-backup"], status: 74)
            expect(try store.readTags(good) == baseline)
        }
        for patch: [String: Any] in [["size": true, "mtime": 0], ["size": 1.9, "mtime": 0],
                                     ["size": 0, "mtime": true], ["destination": 1], ["targetExists": 1],
                                     ["tags": "not an array"]] {
            var bad = archiveItem("good")
            for (key, value) in patch { bad[key] = value }
            try safetyDocument([archiveItem("good"), bad.merging(["path": "\u{0301}valid"]) { _, new in new }])
            _ = try context.run(["--restore", safetyArchive.path, "--no-backup"], status: 74)
            expect(try store.readTags(good) == baseline)
        }

        var imperfect = archiveItem("good")
        imperfect["tags"] = ["", "CR\r\nName", 42, "Tail", "Name\n3"] as [Any]
        imperfect["colors"] = [2, 3, 99, NSNull(), 0] as [Any]
        try safetyDocument([imperfect])
        let recovered = [StoredTag(name: "CR��Name", color: 3), StoredTag(name: "42", color: 99),
                         StoredTag(name: "Tail"), StoredTag(name: "Name�3", color: 0)]
        var warnings: [String] = []
        let document = try ArchiveReader(onWarning: { warnings.append($0) }).read(path: safetyArchive.path)
        expect(document.items.first?.storedTags == recovered)
        expect(warnings.count == 4 && warnings.allSatisfy { $0.contains("archive line 3, item 'good'") })
        let repairedDisplay = try context.run(["--convert", safetyArchive.path, "-N"])
        expect(repairedDisplay.out == "CR��Name,42,Tail,Name�3\n" && repairedDisplay.err.contains("replaced with �"))
        let restored = try records(context.run(["--restore", safetyArchive.path, "--jsonl", "--no-backup"]).out)
        expect(restored.last?["warnings"] as? Int == 4 && restored.last?["restored"] as? Int == 1)
        expect(try store.readTags(good) == recovered)

        // Missing colors keep the older name-only behavior after empty removal.
        imperfect.removeValue(forKey: "colors")
        try safetyDocument([imperfect])
        let nameOnly = try ArchiveReader(onWarning: { _ in }).read(path: safetyArchive.path).items.first!
        expect(nameOnly.colors == nil && nameOnly.tags == recovered.map { $0.name })

        try safetyDocument([archiveItem("good", tags: [StoredTag(name: "", color: 5)])])
        let cleared = try records(context.run(["--restore", safetyArchive.path, "--jsonl", "--no-backup"]).out)
        expect(cleared.last?["cleared"] as? Int == 1 && cleared.last?["warnings"] as? Int == 1)
        expect(try store.readTags(good).isEmpty)

        var duplicates = archiveItem("good")
        duplicates["tags"] = ["", "Yellow", "Yellow", "Yellow�", "Yellow"]
        duplicates["colors"] = [7, 5, 3, 0, 99]
        try safetyDocument([duplicates])
        warnings = []
        let duplicateDocument = try ArchiveReader(onWarning: { warnings.append($0) }).read(path: safetyArchive.path)
        let unique = [StoredTag(name: "Yellow", color: 5), StoredTag(name: "Yellow��", color: 3),
                      StoredTag(name: "Yellow�", color: 0), StoredTag(name: "Yellow���", color: 99)]
        expect(duplicateDocument.items.first?.storedTags == unique && warnings.count == 3)
        expect(try context.run(["--convert", safetyArchive.path, "-N"]).out == "Yellow,Yellow��,Yellow�,Yellow���\n")
        let restoredDuplicates = try records(context.run(["--restore", safetyArchive.path, "--jsonl", "--no-backup"]).out)
        expect(restoredDuplicates.last?["warnings"] as? Int == 3 && restoredDuplicates.last?["restored"] as? Int == 1)
        expect(try store.readTags(good) == unique)

        let unsorted = [StoredTag(name: "B", color: 3), StoredTag(name: "A", color: 6)]
        try safetyDocument([archiveItem("good", tags: unsorted)])
        expect(try context.run(["--convert", safetyArchive.path, "--sorted-tags", "-N"]).out == "A,B\n")
        _ = try context.run(["--restore", safetyArchive.path, "--sorted-tags", "--no-backup"])
        expect(try store.readTags(good) == sortedStoredTags(unsorted))
        _ = try context.run(["--convert", safetyArchive.path, "--jsonl"], status: 64)
    }
}
#endif
