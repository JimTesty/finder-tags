import Foundation

enum FinderColorTests {
    static func run(_ context: TestContext) throws {
        let renderer = TextRenderer(options: Options(), colors: FinderColors(enabled: true))
        let purple = "\u{001B}[48;5;129m"
        let reset = "\u{001B}[m"
        expect(renderer.tag(StoredTag(name: "PurplePlus", color: 3)) == purple + "PurplePlus" + reset)
        expect(renderer.tag(StoredTag(name: "Purple", color: 0)) == "Purple")
        expect(renderer.tag(StoredTag(name: "Purple")) == "Purple")
        expect(renderer.tag(StoredTag(name: "Odd", color: 99)) == "Odd")
        expect(renderer.tag(StoredTag(name: "Odd", color: -3)) == "Odd")
        expect(renderer.tag(StoredTag(name: "💜Plus", color: 3), compact: true) == purple + "💜" + reset)
        expect(TextRenderer(options: Options(), colors: FinderColors(enabled: false)).tag(StoredTag(name: "Purple", color: 3)) == "Purple")

        var counter = UsageCounter()
        counter.add([StoredTag(name: "Custom", color: 3), StoredTag(name: "custom", color: 4)])
        counter.add([StoredTag(name: "Custom", color: 0)])
        let entries = counter.entries(sorted: false, reverse: false)
        expect(entries[0].count == 2 && entries[0].colors == [0, 3])
        expect(entries[1].count == 1 && entries[1].colors == [4])

        #if canImport(Darwin)
        let work = try context.makeWorkDirectory("colors")
        let root = work.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        let original = colorFixtureTags
        let uncolored = original.map { StoredTag(name: $0.name, color: $0.name == "PurplePlus" ? 0 : $0.color) }
        try taggedFile(source, tags: original)
        try taggedFile(destination, tags: uncolored)
        let store = TagStore()
        let change = try store.copyChange(from: source, to: destination)
        expect(change.before == change.after && change.hasChanges)
        _ = try context.run(["--copy", source.path, destination.path, "--sorted-tags", "--no-backup"])
        expect(try store.readTags(destination) == sortedStoredTags(original))

        // An existing tag without a suffix is not a request for a new color.
        let bare = work.appendingPathComponent("bare")
        let bareCopy = work.appendingPathComponent("bare-copy")
        try Data().write(to: bare)
        try Data().write(to: bareCopy)
        let bareTags = [StoredTag(name: "Purple")]
        try FileTagMetadata.write(bareTags, to: bare)
        _ = try context.run(["--copy", bare.path, bareCopy.path, "--no-backup"])
        expect(try store.readTags(bareCopy) == bareTags)
        _ = try context.run(["--add", "New", bareCopy.path, "--no-backup"])
        expect(try store.readTags(bareCopy).first == bareTags.first)

        // Exact spelling, rather than a folded-name palette, controls color.
        let caseTags = [StoredTag(name: "Custom", color: 3), StoredTag(name: "custom", color: 4)]
        try FileTagMetadata.write(caseTags, to: bare)
        let caseOutput = try context.run(["--color=force", "--no-name", bare.path]).out
        expect(caseOutput == purple + "Custom" + reset + ",\u{001B}[44mcustom" + reset + "\n")
        _ = try context.run(["--copy", bare.path, bareCopy.path, "--no-backup"])
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

        let listed = try context.run(["--color=force", "--no-name", source.path, destination.path]).out
        let lines = listed.split(separator: "\n")
        expect(lines[0].contains(purple + "PurplePlus" + reset))
        expect(!lines[1].contains(purple + "PurplePlus" + reset))
        let usage = try context.run(["--usage", "*", "--color=force", "--verbose", source.path, destination.path])
        expect(usage.out.contains("2\tPurplePlus\n"))
        expect(usage.err.contains("different stored colors [0, 3]"))

        #endif
    }
}
