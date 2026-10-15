import Foundation
#if canImport(Darwin)
enum UndoTests {
    static func run(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("undo")
        let root = work.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        let original = colorFixtureTags
        let uncolored = original.map { StoredTag(name: $0.name, color: $0.name == "PurplePlus" ? 0 : $0.color) }
        try taggedFile(source, tags: original)
        try taggedFile(destination, tags: uncolored)
        let store = TagStore()
        let dry = try records(context.run(["--copy", source.path, destination.path, "--dry-run", "--jsonl"]).out)
        expect(dry.last?["changed"] as? Bool == true)
        expect(try store.readTags(destination) == uncolored)
        let undo = work.appendingPathComponent("undo.jsonl")
        _ = try context.run(["--copy", source.path, destination.path, "--backup", undo.path])
        expect(try store.readTags(destination) == original)
        _ = try context.run(["--restore", undo.path, "--no-backup"])
        expect(try store.readTags(destination) == uncolored)
        let safety = work.appendingPathComponent("safety", isDirectory: true)
        let safetyRoot = safety.appendingPathComponent("root", isDirectory: true)
        let outside = safety.appendingPathComponent("outside", isDirectory: true)
        try fileManager.createDirectory(at: safetyRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: outside, withIntermediateDirectories: true)
        let baseline = [StoredTag(name: "Keep", color: 0)]
        let good = safetyRoot.appendingPathComponent("good")
        let outsideFile = outside.appendingPathComponent("victim")
        try taggedFile(good, tags: baseline)
        try taggedFile(outsideFile, tags: [StoredTag(name: "Changed", color: 3)])
        try fileManager.createSymbolicLink(atPath: safetyRoot.appendingPathComponent("sub").path,
                                           withDestinationPath: "../outside")
        let safetyArchive = safety.appendingPathComponent("archive.jsonl")
        func safetyDocument(_ items: [[String: Any]], headerPatch: [String: Any] = [:]) throws {
            try writeTestArchive(items, root: safetyRoot, to: safetyArchive, headerPatch: headerPatch)
        }
        let bare = work.appendingPathComponent("bare")
        let bareCopy = work.appendingPathComponent("bare-copy")
        try Data().write(to: bare)
        try Data().write(to: bareCopy)
        let parentUndo = safety.appendingPathComponent("parent-undo.jsonl")
        let throughParent = safetyRoot.appendingPathComponent("sub/victim")
        _ = try context.run(["--set", "ViaParent", throughParent.path, "--backup", parentUndo.path])
        _ = try context.run(["--restore", parentUndo.path, "--no-backup"])
        expect(try store.readTags(outsideFile) == [StoredTag(name: "Changed", color: 3)])

        // Undo must restore an explicit missing suffix, including a color-only edit.
        try FileTagMetadata.write([StoredTag(name: "Purple")], to: bare)
        try FileTagMetadata.write([StoredTag(name: "Purple", color: 3)], to: bareCopy)
        let nullUndo = safety.appendingPathComponent("null-undo.jsonl")
        _ = try context.run(["--copy", bareCopy.path, bare.path, "--backup", nullUndo.path])
        _ = try context.run(["--restore", nullUndo.path, "--no-backup"])
        expect(try store.readTags(bare) == [StoredTag(name: "Purple")])

        let alias = safetyRoot.appendingPathComponent("alias")
        try fileManager.linkItem(at: good, to: alias)
        try safetyDocument([archiveItem("good", tags: [StoredTag(name: "First", color: 3)]),
                            archiveItem("alias", tags: [StoredTag(name: "Second", color: 6)])])
        let aliasUndo = safety.appendingPathComponent("alias-undo.jsonl")
        _ = try context.run(["--restore", safetyArchive.path, "--backup", aliasUndo.path])
        _ = try context.run(["--restore", aliasUndo.path, "--no-backup"])
        expect(try store.readTags(good) == baseline)

        // Symlink aliases resolve to duplicate journal paths; both preimages
        // must survive so reversing the journal reaches the original state.
        let link = safetyRoot.appendingPathComponent("file-link")
        try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: "good")
        var linkItem = archiveItem("file-link", tags: [StoredTag(name: "Second", color: 6)])
        linkItem["kind"] = "symlink"
        try safetyDocument([archiveItem("good", tags: [StoredTag(name: "First", color: 3)]), linkItem],
                           headerPatch: ["followSymlinks": true])
        let linkUndo = safety.appendingPathComponent("link-undo.jsonl")
        _ = try context.run(["--restore", safetyArchive.path, "-L", "--backup", linkUndo.path])
        let journalItems = try records(String(contentsOf: linkUndo, encoding: .utf8))
            .filter { $0["type"] as? String == "item" }
        expect(journalItems.count == 2 && journalItems[0]["path"] as? String == journalItems[1]["path"] as? String)
        try fileManager.removeItem(at: link)
        try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: "../outside/victim")
        _ = try context.run(["--restore", linkUndo.path, "-L", "--no-backup"])
        expect(try store.readTags(good) == baseline)
        expect(try store.readTags(outsideFile) == [StoredTag(name: "Changed", color: 3)])

        // Exclusive backup creation must refuse both files and dangling links.
        let protected = safety.appendingPathComponent("protected")
        try Data("keep".utf8).write(to: protected)
        let dangling = safety.appendingPathComponent("dangling-backup")
        let absent = safety.appendingPathComponent("must-not-be-created")
        try fileManager.createSymbolicLink(atPath: dangling.path, withDestinationPath: absent.path)
        let beforeBackup = try store.readTags(good)
        for backup in [protected, dangling] {
            _ = try context.run(["--set", "Collision", good.path, "--backup", backup.path], status: 74)
            expect(try store.readTags(good) == beforeBackup)
        }
        expect(try Data(contentsOf: protected) == Data("keep".utf8))
        expect(!fileManager.fileExists(atPath: absent.path))
    }
}
#endif
