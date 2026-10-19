import Foundation
#if canImport(Darwin)
enum UndoTests {
    static func run(_ context: TestContext) throws {
        try checkBackupDefaults(context)
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
        _ = try context.run(["--copy", source.path, destination.path, "--backup-path", undo.path])
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
        _ = try context.run(["--set", "ViaParent", throughParent.path, "--backup-path", parentUndo.path])
        _ = try context.run(["--restore", parentUndo.path, "--no-backup"])
        expect(try store.readTags(outsideFile) == [StoredTag(name: "Changed", color: 3)])

        // Undo must restore an explicit missing suffix, including a color-only edit.
        try FileTagMetadata.write([StoredTag(name: "Purple")], to: bare)
        try FileTagMetadata.write([StoredTag(name: "Purple", color: 3)], to: bareCopy)
        let nullUndo = safety.appendingPathComponent("null-undo.jsonl")
        _ = try context.run(["--copy", bareCopy.path, bare.path, "--backup-path", nullUndo.path])
        _ = try context.run(["--restore", nullUndo.path, "--no-backup"])
        expect(try store.readTags(bare) == [StoredTag(name: "Purple")])

        let alias = safetyRoot.appendingPathComponent("alias")
        try fileManager.linkItem(at: good, to: alias)
        try safetyDocument([archiveItem("good", tags: [StoredTag(name: "First", color: 3)]),
                            archiveItem("alias", tags: [StoredTag(name: "Second", color: 6)])])
        let aliasUndo = safety.appendingPathComponent("alias-undo.jsonl")
        _ = try context.run(["--restore", safetyArchive.path, "--backup-path", aliasUndo.path])
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
        _ = try context.run(["--restore", safetyArchive.path, "-L", "--backup-path", linkUndo.path])
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
            _ = try context.run(["--set", "Collision", good.path, "--backup-path", backup.path], status: 74)
            expect(try store.readTags(good) == beforeBackup)
        }
        expect(try Data(contentsOf: protected) == Data("keep".utf8))
        expect(!fileManager.fileExists(atPath: absent.path))
    }

    private static func checkBackupDefaults(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("backup-defaults")
        let temporary = work.appendingPathComponent("temporary", isDirectory: true)
        let root = work.appendingPathComponent("targets", isDirectory: true)
        let tree = root.appendingPathComponent("tree", isDirectory: true)
        try fileManager.createDirectory(at: temporary, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tree, withIntermediateDirectories: true)
        let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
        let child = tree.appendingPathComponent("child")
        for file in [a, b, child] { try taggedFile(file, tags: []) }
        let store = TagStore()

        // Collect only the archives reported by these commands into this run's
        // fixtures. macOS may ignore TMPDIR when choosing its temporary path.
        // Check journals so mixed operations must cover every changed target.
        func check(
            _ args: [String], backedUp targets: [URL] = [], backupPath: URL? = nil,
            input: String? = nil
        ) throws {
            let result = try context.run(args, input: input)
            let prefix = context.binary.lastPathComponent + ": undo archive: "
            for line in result.err.split(separator: "\n") where line.hasPrefix(prefix) {
                let archive = URL(fileURLWithPath: String(line.dropFirst(prefix.count)))
                let collected = temporary.appendingPathComponent(archive.lastPathComponent)
                if archive != collected { try fileManager.moveItem(at: archive, to: collected) }
                if let backupPath = backupPath {
                    expect(archive.standardizedFileURL == backupPath.standardizedFileURL)
                } else {
                    expect(archive.lastPathComponent.hasPrefix("finder-tags-undo-"))
                }
            }
            let archives = try fileManager.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
            expect(archives.count == (targets.isEmpty ? 0 : 1), "unexpected backup count for \(args)")
            expect(result.err.contains("undo archive:") == !targets.isEmpty)
            if let archive = archives.first {
                let document = try ArchiveReader().read(path: archive.path)
                expect(document.header.purpose == "undo")
                expect(document.items.map { $0.path } == targets.map { String($0.path.dropFirst()) },
                       "backup did not cover all changed targets for \(args)")
                try fileManager.removeItem(at: archive)
            }
        }

        // Plain explicit paths, including an unentered directory, default off.
        try check(["--set", "Listed", a.path, b.path, tree.path])
        expect(try store.read(a) == ["Listed"] && store.read(b) == ["Listed"])
        expect(try store.read(tree) == ["Listed"] && store.read(child).isEmpty)
        try check(["--set", "CopyDestination", b.path])
        try check(["--copy", a.path, b.path])
        expect(try store.read(b) == ["Listed"])

        // Recursion flags enable backup even when no directory is supplied.
        for flag in ["-R", "-d", "--recursive", "--descend"] {
            try check(["--set", flag, a.path, flag], backedUp: [a])
            expect(try store.read(a) == [flag])
        }
        try check(["--set", "Mixed", a.path, tree.path, b.path, "-R"],
                  backedUp: [a, tree, child, b])
        expect(try store.read(a) == ["Mixed"] && store.read(child) == ["Mixed"])
        try check(["--set", "Entered", "--enter", tree.path], backedUp: [tree, child])
        try check(["--set", "EnterFile", "-e", a.path], backedUp: [a])

        try check(["--set", "Stdin", "--stdin"], backedUp: [a], input: a.path + "\n")
        try check(["--set", "Stdin0", b.path, "--stdin0"], backedUp: [b, a], input: a.path + "\0")
        let archive = work.appendingPathComponent("restore.jsonl")
        try writeTestArchive([archiveItem("a")], root: root, to: archive)
        try check(["--restore", archive.path], backedUp: [a])
        expect(try store.read(a) == ["Changed"])

        // Explicit settings retain their ordering and override either default.
        let explicit = temporary.appendingPathComponent("explicit.jsonl")
        try check(["--set", "Forced", a.path, "--backup"], backedUp: [a])
        try check(["--set", "ChosenPath", a.path, "--backup-path", explicit.path],
                  backedUp: [a], backupPath: explicit)
        try check(["--set", "Disabled", "-R", a.path, "--backup-path", explicit.path, "--no-backup"])
        try check(["--set", "EnabledLast", a.path, "--no-backup", "--backup-path", explicit.path],
                  backedUp: [a], backupPath: explicit)
        try check(["--set", "TemporaryLast", a.path, "--backup-path", explicit.path, "--backup"], backedUp: [a])
        try check(["--set", "PathLast", a.path, "--backup", "--backup-path", explicit.path],
                  backedUp: [a], backupPath: explicit)
        try check(["--set", "OffLast", a.path, "--backup", "--no-backup"])
        try check(["--set", "OnLast", a.path, "--no-backup", "--backup"], backedUp: [a])
        try check(["--set", "DisabledEnter", "-e", tree.path, "--no-backup"])
        try check(["--set", "DisabledStdin", "--stdin", "--no-backup"], input: a.path + "\n")
        try check(["--restore", archive.path, "--no-backup"])

        // Sync only modifies enabled backups; dry runs and unchanged files
        // still leave no archive behind.
        try check(["--set", "SyncOff", a.path, "--sync-backup"])
        try check(["--set", "SyncOn", a.path, "-R", "--sync-backup"], backedUp: [a])
        try check(["--set", "Dry", "-R", a.path, "--dry-run"])
        expect(try store.read(a) == ["SyncOn"])
        try check(["--set", "SyncOn", "-R", a.path])
        for flag in ["--backup", "--backup-path", "--no-backup", "--sync-backup"] {
            let args = flag == "--backup-path" ? ["--list", flag, explicit.path, a.path] : ["--list", flag, a.path]
            _ = try context.run(args, status: 64)
        }
        _ = try context.run(["--set", "MissingPath", "--backup-path"], status: 64)
    }
}
#endif
