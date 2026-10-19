import Foundation

enum VerbosityTests {
    static func run(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("verbosity")
        let file = work.appendingPathComponent("file")
        try Data().write(to: file)
        for flags in [[], ["-q"], ["-qqv"], ["-qv"], ["-vq"],
                      ["--quiet", "--verbose"]] {
            let listed = try context.run(flags + ["--no-tags", file.path])
            expect(listed.out == file.path + "\n" && listed.err.isEmpty)
        }
        for flags in [["-v"], ["-vvq"], ["-qvv"], ["--verbose", "--verbose", "--quiet"]] {
            let listed = try context.run(flags + ["--no-tags", file.path])
            expect(listed.out == file.path + "\n")
            expect(listed.err.contains("info: listing traversed files"))
        }
        let quietHelp = try context.run(["-hqv"])
        expect(!quietHelp.out.contains("Important differences from jdberry/tag:"))
        expect(try context.run(["-hhq"]).out.contains("Important differences from jdberry/tag:"))
        let dry = try context.run(["--quiet", "--set", "Changed", "--dry-run", file.path])
        expect(dry.out.contains("[dry-run]") && dry.err.isEmpty)
        let missing = work.appendingPathComponent("missing")
        expect(try context.run(["--quiet", missing.path], status: 74).err.contains("tag:"))

        #if canImport(Darwin)
        let baseline = [StoredTag(name: "Keep", color: 0)]
        try FileTagMetadata.write(baseline, to: file)
        let unchanged = try context.run(["--fix", file.path])
        expect(unchanged.out == "Unchanged => Now: Keep\n" && unchanged.err.isEmpty)
        expect(try context.run(["--fix", "--quiet", file.path]).err.isEmpty)
        let fixed = try records(context.run(["--fix", "--quiet", "--jsonl", file.path]).out)
        expect(fixed.last?["operation"] as? String == "fix")
        let backup = work.appendingPathComponent("undo.jsonl")
        let changed = try context.run(["--set", "Changed", "--quiet", "--backup-path", backup.path, file.path])
        expect(changed.err == "tag: undo archive: \(backup.path)\n")
        let restored = try context.run(["--restore", backup.path, "--quiet", "--no-backup"])
        expect(restored.out.isEmpty && restored.err.isEmpty)
        expect(try TagStore().readTags(file) == baseline)

        let root = work.appendingPathComponent("root", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try taggedFile(root.appendingPathComponent("file"), tags: baseline)
        let exported = try context.run(["--export", "--quiet", root.path])
        let exportedRecords = try records(exported.out)
        expect(exported.err.isEmpty && exportedRecords.last?["operation"] as? String == "export")
        let archive = work.appendingPathComponent("export.jsonl")
        try Data(exported.out.utf8).write(to: archive)
        let converted = try context.run(["--convert", archive.path, "--quiet"])
        expect(converted.err.isEmpty && converted.out.contains("Keep"))
        #endif
    }
}
