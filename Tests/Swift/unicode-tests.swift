import Foundation

enum UnicodeTests {
    static func run(_ context: TestContext) throws {
        let tags = [
            StoredTag(name: "待處理", color: 5),       // Traditional Chinese
            StoredTag(name: "项目", color: 3),         // Simplified Chinese
            StoredTag(name: "やること", color: 0),     // Japanese hiragana
            StoredTag(name: "レビュー", color: 5),     // Japanese katakana
            StoredTag(name: "검토", color: 2),         // Korean
            StoredTag(name: "مراجعة", color: 1),       // Arabic
            StoredTag(name: "בדיקה", color: 4),        // Hebrew
            StoredTag(name: "समीक्षा", color: 6),       // Hindi
            StoredTag(name: "ตรวจสอบ", color: 7),      // Thai
            StoredTag(name: "Проверка"),               // Russian
            StoredTag(name: "Έλεγχος", color: 99),     // Greek
            StoredTag(name: "révision", color: 3),     // Accented Latin
            StoredTag(name: "Cafe\u{301}", color: 0),  // Decomposed accent
            StoredTag(name: "𠮷"),                    // Supplementary-plane CJK
            StoredTag(name: "👩🏽‍💻", color: 6)         // Emoji with joiner and modifier
        ]
        let names = tags.map { $0.name }
        let nameBytes = names.map { Array($0.utf8) }
        let rawValues = tags.map { tag in
            tag.color.map { tag.name + "\n" + String($0) } ?? tag.name
        }
        var warnings: [String] = []
        let state = try FileTagMetadata.decodeState(plist(rawValues)) { warnings.append($0) }
        expect(state.tags == tags, "multilingual tag names, colors, or order changed")
        expect(state.tags.map { Array($0.name.utf8) } == nameBytes, "Unicode bytes changed during decoding")
        expect(!state.needsRepair && warnings.isEmpty, "valid multilingual tags were treated as invalid")
        expect(parseTagList(names.joined(separator: ",")).map { Array($0.utf8) } == nameBytes)
        for name in names {
            expect(parseTagQuery(name) == .tag(name), "multilingual query tag changed: \(name)")
            expect(escapedDisplayText(name) == name, "ordinary Unicode was escaped: \(name)")
        }

        // Repairs must change the illegal scalars, not the surrounding script.
        let damaged = try FileTagMetadata.decodeState(plist(["待\r處\n理\0\n5", "مرا\rجعة\n3"])) { _ in }
        expect(damaged.tags == [StoredTag(name: "待�處�理�", color: 5), StoredTag(name: "مرا�جعة", color: 3)])
        expect(damaged.repairs.fixed == 2 && damaged.repairs.deleted == 0)
        let duplicates = try FileTagMetadata.decodeState(plist(["工作\n5", "工作\n3", "工作\n0", "工作�\n6"])) { _ in }
        expect(duplicates.tags.map { $0.name } == ["工作", "工作��", "工作���", "工作�"])
        expect(duplicates.tags.map { $0.color } == [5, 3, 0, 6])
        expect(duplicates.repairs.fixed == 2 && duplicates.repairs.deleted == 0)

        #if canImport(Darwin)
        let work = try context.makeWorkDirectory("unicode")
        let root = work.appendingPathComponent("root", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("file")
        try taggedFile(source, tags: tags)
        let originalBytes = readRawTagMetadata(source)
        let text = try context.run(["--no-name", source.path])
        expect(text.out == names.joined(separator: ",") + "\n" && text.err.isEmpty)
        let listed = try records(context.run(["--jsonl", source.path]).out).last!
        expect((listed["tags"] as? [String])?.map { Array($0.utf8) } == nameBytes)
        let colors = listed["colors"] as! [Any]
        expect(colors.count == tags.count)
        for (index, tag) in tags.enumerated() { expect(colors[index] as? Int == tag.color) }

        let fixed = try context.run(["--fix", source.path, "--jsonl", "--no-backup"])
        let summary = try records(fixed.out).last!
        expect(summary["tagsFixed"] as? Int == 0 && summary["tagsDeleted"] as? Int == 0)
        expect(summary["filesUpdated"] as? Int == 0 && fixed.err.isEmpty)
        expect(readRawTagMetadata(source) == originalBytes, "--fix rewrote valid multilingual metadata")

        let destination = work.appendingPathComponent("destination")
        try taggedFile(destination, tags: [])
        let set = try context.run(["--set", names.joined(separator: ","), destination.path, "--no-backup"])
        expect(set.err.isEmpty)
        let setNames = try FileTagMetadata.read(destination)!.map { $0.name }
        // Initial-color assignment can decompose Hangul on macOS. Swift String
        // equality accepts canonically equivalent Unicode representations.
        expect(setNames == names, "CLI tag creation changed a multilingual name")
        let copied = try context.run(["--copy", source.path, destination.path, "--no-backup"])
        expect(copied.err.isEmpty)
        expect(try FileTagMetadata.read(destination) == tags)

        let exported = try context.run(["--export", root.path, "--no-file-info"])
        let exportedFile = try records(exported.out).first { $0["path"] as? String == "file" }!
        expect((exportedFile["tags"] as? [String])?.map { Array($0.utf8) } == nameBytes)
        let archive = work.appendingPathComponent("unicode.jsonl")
        try Data(exported.out.utf8).write(to: archive)
        let converted = try context.run(["--convert", archive.path, "--no-name"])
        expect(converted.out == names.joined(separator: ",") + "\n")
        try FileTagMetadata.write([], to: source)
        _ = try context.run(["--restore", archive.path, "--no-backup"])
        expect(try FileTagMetadata.read(source) == tags)
        expect(try FileTagMetadata.read(source)?.map { Array($0.name.utf8) } == nameBytes)
        #endif
    }
}
