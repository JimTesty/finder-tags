import Foundation

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
        for invalid: Any in [["Bad\nwrong"], [""], ["Bad\nname\n3"], ["Not": "an array"]] {
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
        #endif
        print("Finder color tests passed")
    }
}
