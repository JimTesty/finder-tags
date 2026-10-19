import Foundation

enum OptionCompatibilityTests {
    static func run(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("option-compatibility")
        let root = work.appendingPathComponent("root", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("file"), destination = root.appendingPathComponent("destination")
        for target in [file, destination] { try Data().write(to: target) }
        let backup = work.appendingPathComponent("unused-backup.jsonl")
        let listing = ["--no-tags", file.path]
        let harmless = ["--backup-path", backup.path, "--sync-backup", "--at", "first"]
        for verbosity in [[], ["-q"], ["-vq"]] {
            let result = try context.run(listing + harmless + verbosity)
            expect(result.out == file.path + "\n" && result.err.isEmpty)
        }
        let verbose = try context.run(listing + harmless + ["-v", "--no-color"])
        for option in ["backup options", "--sync-backup", "--at/--before/--after"] {
            expect(verbose.err.contains("warning: \(option) ignored:"))
        }
        // Dry runs and structured output warn at default, including aliases.
        // The final quiet/verbose balance controls these advisory warnings.
        for mode in ["--dry-run", "--dryrun", "--jsonl", "--ndjson"] {
            for (verbosity, warns) in [([], true), (["-q"], false), (["-vq"], true),
                                       (["-qqv"], false), (["-vvq"], true)] {
                let result = try context.run(listing + harmless + [mode] + verbosity)
                for option in ["backup options", "--sync-backup", "--at/--before/--after"] {
                    expect(result.err.contains("warning: \(option) ignored:") == warns)
                }
                if mode.hasPrefix("--dry") {
                    expect(result.out == file.path + "\n")
                    expect(result.err.contains("--dry-run ignored:") == warns)
                } else {
                    expect(try records(result.out).last?["tags"] as? [String] == [])
                }
                if !warns { expect(result.err.isEmpty) }
            }
        }
        expect(!fileManager.fileExists(atPath: backup.path))

        // Layout flags cannot corrupt JSONL, truncate tag names, or add metadata.
        let layout = ["-p", "--align-tags", "20", "--compact-tags", "--space-indent", "-g", "-0"]
        let listed = try context.run(["--jsonl", file.path] + layout)
        expect(listed.err.contains("--compact-tags layout ignored:") && !listed.out.contains("\0"))
        expect(try records(listed.out).last?["tags"] as? [String] == [])
        let jsonVerbose = try context.run(["--jsonl", file.path, "-v", "--no-color"] + layout)
        for option in ["--align-tags", "--compact-tags layout", "--one-per-line", "--null", "--slash"] {
            expect(jsonVerbose.err.contains("warning: \(option) ignored:"))
        }
        expect(!jsonVerbose.err.contains("--space-indent ignored:"), "implied indentation warning duplicated")
        expect(try context.run(["--jsonl", "--space-indent", "-v", file.path]).err.contains("--space-indent ignored:"))

        // Accept presentation options across mutation operations without writing.
        let mutations = [["--add", "Added", file.path], ["--remove", "Missing", file.path],
                         ["--set", "Set", file.path], ["--fix", file.path],
                         ["--copy", file.path, destination.path]]
        for operation in mutations {
            let result = try context.run(operation + layout + ["--file-info", "--jsonl", "--dry-run", "--no-backup"])
            let items = try records(result.out).filter { $0["type"] as? String == "item" }
            expect(items.count == 1 && items[0]["dryRun"] as? Bool == true)
            expect(result.err.contains("--file-info ignored:") && items[0]["size"] == nil)
        }

        // Retain errors when ignoring a flag could target or edit the wrong items.
        for args in [["--set", "New", "--before", "Anchor", file.path],
                     ["--set", "New", "--root", root.path, file.path],
                     ["--copy", file.path, destination.path, "--exclude", "file"],
                     ["--set", "New", "--remove", "Old", file.path]] {
            _ = try context.run(args, status: 64)
        }

        #if canImport(Darwin)
        let baseline = [StoredTag(name: "LongB", color: 3), StoredTag(name: "LongA", color: 0)]
        try FileTagMetadata.write(baseline, to: file)
        let added = try context.run(["--add", "LongC", "-p", "--file-info", "--compact-tags", "--no-color", file.path])
        expect(added.out == "Added LongC => Now: LongC, LongA, LongB\n" && added.err.isEmpty)
        expect(try TagStore().read(file) == ["LongB", "LongA", "LongC"])
        let noOp = try context.run(["--add", "LongC", "-p", "--file-info", "--compact-tags", "-v", "--no-color", file.path])
        for option in ["--file-info", "--compact-tags layout", "--slash"] {
            expect(noOp.err.contains("warning: \(option) ignored:"))
        }
        let json = try records(context.run(["--jsonl", "--compact-tags", file.path]).out)
        expect(json.last?["tags"] as? [String] == ["LongC", "LongA", "LongB"])

        let archive = work.appendingPathComponent("archive.jsonl")
        let archiveFlags = layout + ["--absolute", "--sorted-tags"]
        let exported = try context.run(["--export", "--no-file-info", root.path] + archiveFlags)
        expect(exported.err.contains("--sorted-tags ignored:") && !exported.out.contains("\0"))
        let quietExport = try context.run(["--export", "--no-file-info", root.path, "-q"] + archiveFlags)
        expect(quietExport.err.isEmpty && quietExport.out == exported.out)
        try Data(exported.out.utf8).write(to: archive)
        let document = try ArchiveReader().read(path: archive.path)
        expect(document.items.first { $0.path == "file" }?.tags == ["LongB", "LongA", "LongC"])
        let exportVerbose = try context.run(["--export", "-v", "--no-color", root.path] + archiveFlags)
        for option in ["--absolute", "--sorted-tags", "--reverse", "--compact-tags layout", "--null"] {
            expect(exportVerbose.err.contains("warning: \(option) ignored:"))
        }
        // Restore warns without relying on --dry-run or --jsonl being supplied.
        let restore = ["--restore", archive.path, "--no-sort-files", "--no-backup"]
        expect(try context.run(restore).err.contains("--no-sort-files ignored:"))
        let quietRestore = try context.run(restore + ["--quiet"])
        expect(quietRestore.out.isEmpty && quietRestore.err.isEmpty)
        expect(try !context.run(["--convert", archive.path, "--no-sort-files"]).err.contains("ignored:"))
        for operation in [["--copy", file.path, destination.path], ["--restore", archive.path],
                          ["--convert", archive.path]] {
            let result = try context.run(operation + ["--no-sort-files", "--file-info", "--dry-run", "--no-backup", "-v"])
            expect(result.err.contains("--no-sort-files ignored:"))
        }
        _ = try context.run(["--restore", archive.path, "--root", root.path, "--dry-run", "--no-backup"] + layout + ["--file-info"])
        _ = try context.run(["--move", "LongA", "first", file.path, "--dry-run", "--file-info"] + layout)
        _ = try context.run(["--convert", archive.path, "--jsonl"], status: 64)
        _ = try context.run(["--restore", archive.path, "--exclude", "file"], status: 64)
        #endif
    }
}
