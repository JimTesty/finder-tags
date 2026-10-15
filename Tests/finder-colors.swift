import Foundation
#if canImport(Darwin)
import Darwin
#endif

@main
enum FinderColorTests {
    static func expect(_ condition: Bool, _ message: String = "assertion failed", file: StaticString = #file, line: UInt = #line) {
        precondition(condition, message, file: file, line: line)
    }

    static func main() throws {
        let renderer = FinderColors(enabled: true)
        let purple = "\u{001B}[48;5;129m"
        let reset = "\u{001B}[m"
        expect(renderer.render(StoredTag(name: "PurplePlus", color: 3)) == purple + "PurplePlus" + reset)
        expect(renderer.render(StoredTag(name: "Purple", color: 0)) == "Purple")
        expect(renderer.render(StoredTag(name: "Purple")) == "Purple")
        expect(renderer.render(StoredTag(name: "Odd", color: 99)) == "Odd")
        expect(renderer.render(StoredTag(name: "Odd", color: -3)) == "Odd")
        expect(renderer.renderFirstCharacter(of: StoredTag(name: "💜Plus", color: 3)) == purple + "💜" + reset)
        expect(FinderColors(enabled: false).render(StoredTag(name: "Purple", color: 3)) == "Purple")

        func plist(_ values: Any) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
        }
        let decoded = try FileTagMetadata.decode(plist(["Custom\n3", "None\n0", "Odd\n99", "Negative\n-3", "Bare"]))
        expect(decoded.map { $0.color } == [3, 0, 99, -3, nil])
        for invalid: Any in [["Bad\nwrong"], [""], ["Bad\nname\n3"], ["Not": "an array"],
                             ["Bad\r\nName\n3"], ["Bad\0Name\n3"], ["Bad\rName"], ["Bad\r\n3"]] {
            do {
                _ = try FileTagMetadata.decode(plist(invalid))
                preconditionFailure("accepted malformed tag metadata")
            } catch {}
        }

        var counter = UsageCounter()
        counter.add([StoredTag(name: "Custom", color: 3), StoredTag(name: "custom", color: 4)])
        counter.add([StoredTag(name: "Custom", color: 0)])
        let entries = counter.entries(sorted: false, reverse: false)
        expect(entries[0].count == 2 && entries[0].colors == [0, 3])
        expect(entries[1].count == 1 && entries[1].colors == [4])

        #if canImport(Darwin)
        let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
            .appendingPathComponent("color-tests", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let root = work.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try Data().write(to: source)
        try Data().write(to: destination)
        let original = [
            StoredTag(name: "Yellow", color: 5), StoredTag(name: "Purple", color: 3),
            StoredTag(name: "PurplePlus", color: 3), StoredTag(name: "Uncolored", color: 0),
            StoredTag(name: "Unexpected", color: 99)
        ]
        let uncolored = original.map { StoredTag(name: $0.name, color: $0.name == "PurplePlus" ? 0 : $0.color) }
        try FileTagMetadata.write(original, to: source)
        try FileTagMetadata.write(uncolored, to: destination)
        let store = TagStore()
        let change = try store.copyChange(from: source, to: destination)
        expect(change.before == change.after && change.hasChanges)

        let binary = URL(fileURLWithPath: CommandLine.arguments[2])
        func run(_ args: [String], status: Int32 = 0) throws -> (out: String, err: String) {
            let process = Process()
            process.executableURL = binary
            process.arguments = args
            let stdout = Pipe(), stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let output = String(decoding: out, as: UTF8.self)
            let error = String(decoding: err, as: UTF8.self)
            expect(process.terminationStatus == status, "\(args): \(error)")
            return (output, error)
        }
        func records(_ text: String) throws -> [[String: Any]] {
            try text.split(separator: "\n").map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
            }
        }
        let dry = try records(run(["--copy", source.path, destination.path, "--dry-run", "--jsonl"]).out)
        expect(dry.last?["changed"] as? Bool == true)
        expect(try store.readTags(destination) == uncolored)
        let undo = work.appendingPathComponent("undo.jsonl")
        _ = try run(["--copy", source.path, destination.path, "--backup", undo.path])
        expect(try store.readTags(destination) == original)
        _ = try run(["--restore", undo.path, "--no-backup"])
        expect(try store.readTags(destination) == uncolored)
        _ = try run(["--copy", source.path, destination.path, "--sorted-tags", "--no-backup"])
        expect(try store.readTags(destination) == sortedStoredTags(original))

        // An existing tag without a suffix is not a request for a new color.
        let bare = work.appendingPathComponent("bare")
        let bareCopy = work.appendingPathComponent("bare-copy")
        try Data().write(to: bare)
        try Data().write(to: bareCopy)
        let bareTags = [StoredTag(name: "Purple")]
        try FileTagMetadata.write(bareTags, to: bare)
        _ = try run(["--copy", bare.path, bareCopy.path, "--no-backup"])
        expect(try store.readTags(bareCopy) == bareTags)
        _ = try run(["--add", "New", bareCopy.path, "--no-backup"])
        expect(try store.readTags(bareCopy).first == bareTags.first)

        // Exact spelling, rather than a folded-name palette, controls color.
        let caseTags = [StoredTag(name: "Custom", color: 3), StoredTag(name: "custom", color: 4)]
        try FileTagMetadata.write(caseTags, to: bare)
        let caseOutput = try run(["--color=force", "--no-name", bare.path]).out
        expect(caseOutput == purple + "Custom" + reset + ",\u{001B}[44mcustom" + reset + "\n")
        _ = try run(["--copy", bare.path, bareCopy.path, "--no-backup"])
        expect(try store.readTags(bareCopy) == caseTags)

        // Every name-only edit must retain the colors of the surviving tags.
        try store.apply(store.addChange(["New"], to: source, caseSensitive: false, position: nil), to: source)
        expect(try store.readTags(source).prefix(original.count).elementsEqual(original))
        try store.apply(store.removeChange(["New"], from: source, caseSensitive: false), to: source)
        expect(try store.readTags(source) == original)
        try store.apply(store.moveChange(tag: "PurplePlus", to: .first, on: source, caseSensitive: false), to: source)
        expect(try store.readTags(source).first == StoredTag(name: "PurplePlus", color: 3))
        try store.apply(store.addChange(["purpleplus"], to: source, caseSensitive: false, position: nil), to: source)
        expect(try store.readTags(source).first == StoredTag(name: "purpleplus", color: 3))
        try store.apply(store.setChange(["Uncolored", "purpleplus"], on: source), to: source)
        expect(try store.readTags(source) == [StoredTag(name: "Uncolored", color: 0), StoredTag(name: "purpleplus", color: 3)])
        try FileTagMetadata.write(original, to: source)
        try FileTagMetadata.write(uncolored, to: destination)

        let listed = try run(["--color=force", "--no-name", source.path, destination.path]).out
        let lines = listed.split(separator: "\n")
        expect(lines[0].contains(purple + "PurplePlus" + reset))
        expect(!lines[1].contains(purple + "PurplePlus" + reset))
        let usage = try run(["--usage", "*", "--color=force", "--verbose", source.path, destination.path])
        expect(usage.out.contains("2\tPurplePlus\n"))
        expect(usage.err.contains("different stored colors [0, 3]"))

        let archive = work.appendingPathComponent("export.jsonl")
        let exported = try run(["--export", "--no-file-info", root.path]).out
        try Data(exported.utf8).write(to: archive)
        let exportedRecords = try records(exported)
        let sourceRecord = exportedRecords.first { $0["path"] as? String == "source" }!
        expect(sourceRecord["colors"] as? [Int] == [5, 3, 3, 0, 99])
        let converted = try run(["--convert", archive.path, "--color=force"]).out
        expect(converted.contains(purple + "PurplePlus" + reset))
        try FileTagMetadata.write(uncolored, to: source)
        _ = try run(["--restore", archive.path, "--no-backup"])
        expect(try store.readTags(source) == original)

        // Old records restore names while retaining known destination colors.
        let legacy = work.appendingPathComponent("legacy.jsonl")
        var legacyRecords = exportedRecords
        for index in legacyRecords.indices { legacyRecords[index].removeValue(forKey: "colors") }
        func writeRecords(_ records: [[String: Any]], to url: URL) throws {
            let lines = try records.map {
                String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self)
            }
            try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        }
        try writeRecords(legacyRecords, to: legacy)
        _ = try run(["--restore", legacy.path, "--no-backup"])
        expect(try store.readTags(source) == original)
        let oldConverted = try run(["--convert", legacy.path, "--color=force"]).out
        expect(!oldConverted.contains("\u{001B}["))

        try FileTagMetadata.write(original, to: destination)
        for bad: Any in [[3], [5, 3, true, 0, 99], [5, 3, 2.5, 0, 99]] {
            var malformed = exportedRecords
            let index = malformed.firstIndex { $0["path"] as? String == "source" }!
            malformed[index]["colors"] = bad
            let path = work.appendingPathComponent("invalid.jsonl")
            try writeRecords(malformed, to: path)
            _ = try run(["--restore", path.path, "--no-backup"], status: 74)
            expect(try store.readTags(source) == original)
            expect(try store.readTags(destination) == original)
        }

        let safety = work.appendingPathComponent("safety", isDirectory: true)
        let safetyRoot = safety.appendingPathComponent("root", isDirectory: true)
        let outside = safety.appendingPathComponent("outside", isDirectory: true)
        try fileManager.createDirectory(at: safetyRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        let baseline = [StoredTag(name: "Keep", color: 0)]
        func fixture(_ url: URL, tags: [StoredTag] = baseline) throws {
            try Data().write(to: url)
            try FileTagMetadata.write(tags, to: url)
        }
        let good = safetyRoot.appendingPathComponent("good")
        let outsideFile = outside.appendingPathComponent("victim")
        let unicodeFile = safety.appendingPathComponent("\u{0301}victim")
        try fixture(good)
        try fixture(outsideFile)
        try fixture(unicodeFile)
        try fileManager.createSymbolicLink(atPath: safetyRoot.appendingPathComponent("sub").path,
                                           withDestinationPath: "../outside")
        let safetyArchive = safety.appendingPathComponent("archive.jsonl")
        func item(_ path: String, tags: [StoredTag] = [StoredTag(name: "Changed", color: 3)]) -> [String: Any] {
            return ["type": "item", "kind": "file", "path": path, "tags": tags.map { $0.name },
                    "colors": tags.map { $0.color.map { $0 as Any } ?? NSNull() }]
        }
        func safetyDocument(_ items: [[String: Any]], headerPatch: [String: Any] = [:]) throws {
            var header = exportedRecords[0]
            for (key, value) in headerPatch { header[key] = value }
            let summary: [String: Any] = [
                "type": "summary", "operation": "export", "visited": items.count,
                "emitted": items.count, "tagged": items.count, "errors": 0, "warnings": 0
            ]
            try writeRecords([header, ["type": "root", "path": safetyRoot.path]] + items + [summary], to: safetyArchive)
        }

        try safetyDocument([item("good")])
        var truncated = try records(String(contentsOf: safetyArchive, encoding: .utf8))
        truncated.removeLast()
        try writeRecords(truncated, to: safetyArchive)
        _ = try run(["--restore", safetyArchive.path, "--no-backup"], status: 74)
        expect(try store.readTags(good) == baseline)

        // Reject escapes before even an earlier, valid record can change tags.
        for path in ["../\u{0301}victim", "sub/victim"] {
            try safetyDocument([item("good"), item(path)])
            _ = try run(["--restore", safetyArchive.path, "--no-backup"], status: 74)
            expect(try store.readTags(good) == baseline)
            expect(try store.readTags(outsideFile) == baseline)
            expect(try store.readTags(unicodeFile) == baseline)
        }
        // Explicit following remains supported with a matching archive mode.
        try safetyDocument([item("sub/victim")], headerPatch: ["followSymlinks": true])
        _ = try run(["--restore", safetyArchive.path, "-L", "--no-backup"])
        expect(try store.readTags(outsideFile) == [StoredTag(name: "Changed", color: 3)])

        let parentUndo = safety.appendingPathComponent("parent-undo.jsonl")
        let throughParent = safetyRoot.appendingPathComponent("sub/victim")
        _ = try run(["--set", "ViaParent", throughParent.path, "--backup", parentUndo.path])
        _ = try run(["--restore", parentUndo.path, "--no-backup"])
        expect(try store.readTags(outsideFile) == [StoredTag(name: "Changed", color: 3)])

        // A real filename beginning with a combining character is not an escape.
        let validUnicode = safetyRoot.appendingPathComponent("\u{0301}valid")
        try fixture(validUnicode)
        let unicodeExport = try run(["--export", safetyRoot.path, "--no-file-info"]).out
        expect(try records(unicodeExport).contains { $0["path"] as? String == "\u{0301}valid" })

        for patch: [String: Any] in [["version": 3.9], ["purpose": 42], ["followSymlinks": "true"],
                                     ["followSymlinks": 1], ["fileInfo": []], ["taggedOnly": NSNull()]] {
            try safetyDocument([item("good")], headerPatch: patch)
            _ = try run(["--restore", safetyArchive.path, "--no-backup"], status: 74)
            expect(try store.readTags(good) == baseline)
        }
        for patch: [String: Any] in [["size": true, "mtime": 0], ["size": 1.9, "mtime": 0],
                                     ["size": 0, "mtime": true], ["destination": 1], ["targetExists": 1],
                                     ["tags": ["Bad\r\nName"]]] {
            var bad = item("good")
            for (key, value) in patch { bad[key] = value }
            try safetyDocument([item("good"), bad.merging(["path": "\u{0301}valid"]) { _, new in new }])
            _ = try run(["--restore", safetyArchive.path, "--no-backup"], status: 74)
            expect(try store.readTags(good) == baseline)
        }

        // Undo must restore an explicit missing suffix, including a color-only edit.
        try FileTagMetadata.write([StoredTag(name: "Purple")], to: bare)
        try FileTagMetadata.write([StoredTag(name: "Purple", color: 3)], to: bareCopy)
        let nullUndo = safety.appendingPathComponent("null-undo.jsonl")
        _ = try run(["--copy", bareCopy.path, bare.path, "--backup", nullUndo.path])
        _ = try run(["--restore", nullUndo.path, "--no-backup"])
        expect(try store.readTags(bare) == [StoredTag(name: "Purple")])

        let alias = safetyRoot.appendingPathComponent("alias")
        try fileManager.linkItem(at: good, to: alias)
        try safetyDocument([item("good", tags: [StoredTag(name: "First", color: 3)]),
                            item("alias", tags: [StoredTag(name: "Second", color: 6)])])
        let aliasUndo = safety.appendingPathComponent("alias-undo.jsonl")
        _ = try run(["--restore", safetyArchive.path, "--backup", aliasUndo.path])
        _ = try run(["--restore", aliasUndo.path, "--no-backup"])
        expect(try store.readTags(good) == baseline)

        // Symlink aliases resolve to duplicate journal paths; both preimages
        // must survive so reversing the journal reaches the original state.
        let link = safetyRoot.appendingPathComponent("file-link")
        try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: "good")
        var linkItem = item("file-link", tags: [StoredTag(name: "Second", color: 6)])
        linkItem["kind"] = "symlink"
        try safetyDocument([item("good", tags: [StoredTag(name: "First", color: 3)]), linkItem],
                           headerPatch: ["followSymlinks": true])
        let linkUndo = safety.appendingPathComponent("link-undo.jsonl")
        _ = try run(["--restore", safetyArchive.path, "-L", "--backup", linkUndo.path])
        let journalItems = try records(String(contentsOf: linkUndo, encoding: .utf8))
            .filter { $0["type"] as? String == "item" }
        expect(journalItems.count == 2 && journalItems[0]["path"] as? String == journalItems[1]["path"] as? String)
        try fileManager.removeItem(at: link)
        try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: "../outside/victim")
        _ = try run(["--restore", linkUndo.path, "-L", "--no-backup"])
        expect(try store.readTags(good) == baseline)
        expect(try store.readTags(outsideFile) == [StoredTag(name: "Changed", color: 3)])

        let unsorted = [StoredTag(name: "B", color: 3), StoredTag(name: "A", color: 6)]
        try safetyDocument([item("good", tags: unsorted)])
        expect(try run(["--convert", safetyArchive.path, "--sorted-tags", "-N"]).out == "A,B\n")
        _ = try run(["--restore", safetyArchive.path, "--sorted-tags", "--no-backup"])
        expect(try store.readTags(good) == sortedStoredTags(unsorted))
        _ = try run(["--convert", safetyArchive.path, "--jsonl"], status: 64)

        // Exclusive backup creation must refuse both files and dangling links.
        let protected = safety.appendingPathComponent("protected")
        try Data("keep".utf8).write(to: protected)
        let dangling = safety.appendingPathComponent("dangling-backup")
        let absent = safety.appendingPathComponent("must-not-be-created")
        try fileManager.createSymbolicLink(atPath: dangling.path, withDestinationPath: absent.path)
        let beforeBackup = try store.readTags(good)
        for backup in [protected, dangling] {
            _ = try run(["--set", "Collision", good.path, "--backup", backup.path], status: 74)
            expect(try store.readTags(good) == beforeBackup)
        }
        expect(try Data(contentsOf: protected) == Data("keep".utf8))
        expect(!fileManager.fileExists(atPath: absent.path))

        // Malformed raw metadata must fail before a mutation or undo write.
        let malformedData = try plist(["Bad\0Name\n3"])
        let setStatus = malformedData.withUnsafeBytes {
            setxattr(good.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, $0.count, 0, 0)
        }
        expect(setStatus == 0)
        let invalidUndo = safety.appendingPathComponent("invalid-undo.jsonl")
        _ = try run(["--set", "Healthy", good.path, "--backup", invalidUndo.path], status: 74)
        expect(!fileManager.fileExists(atPath: invalidUndo.path))
        _ = try run(["--export", safetyRoot.path, "--no-file-info"], status: 74)
        #endif
        print("Finder color tests passed")
    }
}
