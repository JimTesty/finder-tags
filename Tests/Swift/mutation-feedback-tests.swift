import Foundation
#if canImport(Darwin)
enum MutationFeedbackTests {
    static func run(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("mutation-feedback")
        let file = work.appendingPathComponent("file")
        let store = TagStore()
        try taggedFile(file, tags: [StoredTag(name: "Red", color: 6)])
        let added = try context.run(["--add", "Red,Yellow", file.path])
        expect(added.out == "Added Yellow => Now: Red, Yellow\n" && added.err.isEmpty)
        expect(try context.run(["--add", "Yellow", file.path]).out == "Unchanged => Now: Red, Yellow\n")
        expect(try context.run(["--add", "yellow", file.path]).out
            == "Changed case Yellow to yellow => Now: Red, yellow\n")
        expect(try context.run(["--remove", "Missing,Red", file.path]).out == "Removed Red => Now: yellow\n")
        expect(try context.run(["--remove", "*", file.path]).out == "Cleared tags => Now: (empty)\n")
        expect(try context.run(["--set", "", file.path]).out == "Unchanged => Now: (empty)\n")
        expect(try context.run(["--set", "B,A,C", file.path]).out == "Set tags => Now: B, A, C\n")
        let moved = try context.run(["--move", "C", "first", "--reverse", file.path])
        expect(moved.out == "Reordered tags => Now: A, B, C\n")
        expect(try store.read(file) == ["C", "B", "A"])

        // Placement always starts from raw order; sorting runs last and
        // reversal only changes the report. Cover all three placement forms.
        for (placement, raw) in [(["--at", "0"], ["C", "B", "A"]),
                                 (["--before", "B"], ["C", "B", "A"]),
                                 (["--after", "B"], ["B", "C", "A"])] {
            for sorted in [false, true] {
                try FileTagMetadata.write([StoredTag(name: "B", color: 3), StoredTag(name: "A", color: 0)], to: file)
                let flags = sorted ? ["--sorted-tags"] : []
                let result = try context.run(["--add", "C", "--reverse", file.path] + placement + flags)
                let stored = sorted ? ["A", "B", "C"] : raw
                expect(try store.read(file) == stored)
                expect(result.out == "Added C => Now: " + stored.reversed().joined(separator: ", ") + "\n")
            }
        }

        let purple = "\u{1b}[48;5;129m", reset = "\u{1b}[m"
        let baseline = [StoredTag(name: "B", color: 3), StoredTag(name: "A", color: 0)]
        try FileTagMetadata.write(baseline, to: file)
        let colored = try context.run(["--remove", "A", "--color=force", file.path])
        expect(colored.out == "Removed A => Now: \(purple)B\(reset)\n")
        expect(try context.run(["--remove", "Missing", "--no-color", file.path]).out == "Unchanged => Now: B\n")
        expect(try context.runInTerminal(["--remove", "Missing", file.path]).contains(purple + "B" + reset))
        expect(try context.run(["--remove", "Missing", "-0", file.path]).out == "Unchanged => Now: B\0")

        let verbose = try context.run(["--set", "A,B", "--reverse", "-v", file.path])
        expect(verbose.out.hasPrefix("Set tags => Before (stored): B [color 3] => Now: B [color 3], A [color "))
        expect(verbose.out.split(separator: "\n").count == 1 && !verbose.err.contains("Now:"))
        expect(verbose.err.contains("0 unchanged, 0 skipped, 0 errors") && verbose.err.contains("(1 visited)"))
        let quiet = try context.run(["--set", "Quiet", "-q", file.path])
        expect(quiet.out.isEmpty && quiet.err.isEmpty)
        for flags in [[], ["-q"], ["-v"]] {
            let json = try context.run(["--set", "JSON", "--jsonl", "--color=force", file.path] + flags)
            expect(!json.out.contains("\u{1b}") && !json.err.contains("Now:"))
            expect(try records(json.out).last?["after"] as? [String] == ["JSON"])
        }

        let left = work.appendingPathComponent("left"), right = work.appendingPathComponent("right")
        try fileManager.createDirectory(at: left, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: right, withIntermediateDirectories: true)
        let first = left.appendingPathComponent("same"), second = right.appendingPathComponent("same")
        try taggedFile(first, tags: baseline)
        try taggedFile(second, tags: baseline)
        let bulkArgs = ["--set", "Bulk", "-R", "--no-backup", left.path, right.path]
        let bulk = try context.run(bulkArgs)
        expect(bulk.out.split(separator: "\n").count == 4)
        for path in [left.path, right.path, first.path, second.path] {
            expect(bulk.out.contains(path + ": Set tags => Now: Bulk\n"))
        }
        expect(bulk.err == "tag: 4 files changed\n")
        let repeated = try context.run(bulkArgs)
        expect(repeated.out.isEmpty && repeated.err == "tag: 0 files changed, 4 unchanged\n")
        let repeatedVerbose = try context.run(bulkArgs + ["-v"])
        expect(repeatedVerbose.out.split(separator: "\n").count == 4)
        expect(repeatedVerbose.out.contains(first.path + ": Unchanged => Before (stored):"))
        expect(repeatedVerbose.err.contains("4 unchanged, 0 skipped, 0 errors (4 visited)"))

        try FileTagMetadata.write(baseline, to: second)
        let mixed = try context.run(["--add", "Bulk", first.path, second.path])
        expect(mixed.out == second.path + ": Added Bulk => Now: B, A, Bulk\n")
        expect(mixed.err == "tag: 1 file changed, 1 unchanged\n")
        let empty = work.appendingPathComponent("empty")
        try taggedFile(empty, tags: [])
        let skipped = try context.run(["--set", "Next", "--tagged-only", first.path, empty.path])
        expect(skipped.out == first.path + ": Set tags => Now: Next\n")
        expect(skipped.err == "tag: 1 file changed, 1 skipped\n")
        let skippedVerbose = try context.run(["--set", "Next", "--tagged-only", "-v", empty.path])
        expect(skippedVerbose.out.isEmpty && skippedVerbose.err.contains("skipping \(empty.path): no tags"))

        let missing = work.appendingPathComponent("missing")
        let failed = try context.run(["--set", "AfterError", missing.path, first.path], status: 74)
        expect(failed.out == first.path + ": Set tags => Now: AfterError\n")
        expect(failed.err.contains("not reachable:") && failed.err.contains("1 file changed, 1 errors"))
        let piped = try context.run(["--add", "Piped", "--stdin0", "--no-backup"], input: empty.path + "\0")
        expect(piped.out == empty.path + ": Added Piped => Now: Piped\n")
        expect(piped.err == "tag: 1 file changed\n")

        let copied = try context.run(["--copy", first.path, second.path])
        expect(copied.out == second.path + ": Copied tags from " + first.path + " => Now: AfterError\n")
        expect(copied.err.isEmpty)
        writeRawTagMetadata(try plist(["Keep\n0", ""]), to: file)
        let repaired = try context.run(["--fix", file.path])
        expect(repaired.out == "Repaired stored metadata (0 tags fixed, 1 deleted) => Now: Keep\n")
        expect(repaired.err.contains("warning:") && !repaired.err.contains("fix:"))

        let archive = work.appendingPathComponent("restore.jsonl")
        try writeTestArchive([archiveItem("same", tags: [StoredTag(name: "Z", color: 3), StoredTag(name: "A", color: 5)])],
                             root: left, to: archive)
        let restored = try context.run(["--restore", archive.path, "--no-backup", "--sorted-tags", "--reverse"])
        expect(restored.out == "same: Restored tags => Now: Z, A\n")
        expect(restored.err == "tag: restore: 1 item restored\n")
        expect(try store.read(first) == ["A", "Z"])
        let restoreArgs = ["--restore", archive.path, "--no-backup", "--sorted-tags"]
        let unchangedRestore = try context.run(restoreArgs)
        expect(unchangedRestore.out.isEmpty && unchangedRestore.err == "tag: restore: 0 items restored, 1 unchanged\n")
        expect(try context.run(restoreArgs + ["-v"]).out.hasPrefix("same: Unchanged => Before (stored):"))
        expect(try records(context.run(restoreArgs + ["-v", "--jsonl"]).out).count == 1)
        try writeTestArchive([archiveItem("same", tags: [])], root: left, to: archive)
        let restoreSkipped = try context.run(restoreArgs + ["--tagged-only", "-v"])
        expect(restoreSkipped.out.isEmpty && restoreSkipped.err.contains("skipping same: archive item has no tags"))
        expect(restoreSkipped.err.contains("1 skipped") && restoreSkipped.err.contains("(1 visited)"))
    }
}
#endif
