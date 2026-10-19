import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum FileInfoTests {
    static func run(_ context: TestContext) throws {
        var options = Options()
        options.fileInfo = true
        let renderer = TextRenderer(options: options, colors: FinderColors(enabled: false))
        expect(renderer.fileRecords(formattedName: "file", tags: [], metadata: nil)
            == ["[--------    ---] file"])
        let colored = TextRenderer(options: options, colors: FinderColors(enabled: true))
        expect(colored.fileRecords(formattedName: "file", tags: [], metadata: nil)
            == ["\u{1b}[32m[--------    ---]\u{1b}[m file"])

        let work = try context.makeWorkDirectory("file-info")
        let root = work.appendingPathComponent("root", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let regular = root.appendingPathComponent("regular")
        try Data(repeating: 0, count: 100_000).write(to: regular)
        let destinations = ["missing", root.appendingPathComponent("absent").path, "dangling-0", "regular/child"]
        let timestamp: Double = 1_704_196_800.125
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd"
        let date = formatter.string(from: Date(timeIntervalSince1970: timestamp))
        let singleWarning = "tag: warning: 1 symlink with non-existent target; using its own file info\n"

        for (index, destination) in destinations.enumerated() {
            let link = root.appendingPathComponent("dangling-\(index)")
            try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: destination)
            let times = [timespec(tv_sec: 1_704_196_800, tv_nsec: 125_000_000),
                         timespec(tv_sec: 1_704_196_800, tv_nsec: 125_000_000)]
            expect(utimensat(AT_FDCWD, link.path, times, AT_SYMLINK_NOFOLLOW) == 0)

            // No per-tag xattr is a successful empty read of the link itself.
            let empty = try context.run(["--file-info", "--jsonl", link.path])
            expect(try records(empty.out).last?["tags"] as? [String] == [])
            let ownTags = try plist(["LinkOnly\n3", "中文\n5"])
            #if canImport(Darwin)
            writeRawTagMetadata(ownTags, to: link, followSymlinks: false)
            #endif

            for follow in [[], ["-L"]] {
                let result = try context.run(follow + ["--file-info", "--jsonl", link.path])
                let record = try records(result.out).last!
                expect(record["kind"] as? String == "symlink")
                expect(record["size"] as? Int == destination.utf8.count)
                expect(abs((record["mtime"] as! Double) - timestamp) < 0.000001)
                expect(result.err == singleWarning)
                expect(record["path"] as? String == ".")
                #if canImport(Darwin)
                expect(record["tags"] as? [String] == ["LinkOnly", "中文"])
                expect(record["colors"] as? [Int] == [3, 5])
                #endif
            }
            let text = try context.run(["--file-info", "--no-tags", "--print-symlinks", link.path])
            expect(text.out.hasPrefix("[\(date)   ~0MB] "))
            expect(text.out.contains("\(link.path) [BROKEN SYMLINK] -> \(destination)\n"))
            expect(text.err == singleWarning)
            let literal = try context.run(["-0T", link.path])
            expect(literal.out == link.path + "\0" && literal.err == singleWarning)
            #if canImport(Darwin)
            let filtered = try context.run(["--filter", "LinkOnly", "--file-info", "--jsonl", link.path])
            expect(try records(filtered.out).last?["tags"] as? [String] == ["LinkOnly", "中文"])
            let width = link.path.count + 30
            let decoratedName = link.path + " [BROKEN SYMLINK]"
            let expected = "[\(date)   ~0MB] " + decoratedName
                + String(repeating: " ", count: width - decoratedName.count + 2) + "LinkOnly,中文\n"
            let aligned = try context.run(["--file-info", "--align-tags", String(width), link.path])
            expect(aligned.out == expected && aligned.err == singleWarning)
            let colored = try context.run(["--file-info", "--align-tags", String(width), "--color=force", link.path])
            expect(colored.out.contains(" \u{1b}[41;1m[BROKEN SYMLINK]\u{1b}[m"))
            expect(colored.out.replacingOccurrences(of: "\u{1b}\\[[0-9;]*m", with: "", options: .regularExpression) == expected)
            expect(readRawTagMetadata(link, followSymlinks: false) == ownTags)
            #endif
        }

        // A live target supplies both the tags and file info, even when the
        // symlink itself has different tags. Loops are not missing targets.
        let live = root.appendingPathComponent("live")
        try fileManager.createSymbolicLink(atPath: live.path, withDestinationPath: "regular")
        #if canImport(Darwin)
        try FileTagMetadata.write([StoredTag(name: "TargetOnly", color: 5)], to: regular)
        writeRawTagMetadata(try plist(["LinkOnly\n3"]), to: live, followSymlinks: false)
        #endif
        let liveResult = try context.run(["--file-info", "--jsonl", live.path])
        let liveRecord = try records(liveResult.out).last!
        expect(liveRecord["size"] as? Int == 100_000 && liveResult.err.isEmpty)
        #if canImport(Darwin)
        expect(liveRecord["tags"] as? [String] == ["TargetOnly"])
        expect(liveRecord["colors"] as? [Int] == [5])
        #endif
        let loop = work.appendingPathComponent("loop")
        try fileManager.createSymbolicLink(atPath: loop.path, withDestinationPath: "loop")
        expect(try symbolicLinkInfo(for: loop)?.targetIsMissing == false)

        let recursive = try context.run(["-RT", "--file-info", root.path])
        expect(recursive.out.components(separatedBy: "[BROKEN SYMLINK]").count - 1 == 4)
        expect(recursive.err == "tag: warning: 4 symlinks with non-existent targets; using their own file info\n")

        #if canImport(Darwin)
        // Other warnings remain visible; the broken-link count is the last line.
        let imperfect = root.appendingPathComponent("dangling-0")
        writeRawTagMetadata(try plist(["", "LinkOnly\n3"]), to: imperfect, followSymlinks: false)
        let repaired = try context.run(["--file-info", imperfect.path])
        expect(repaired.err.contains("ignoring empty tag") && repaired.err.hasSuffix(singleWarning))
        expect(repaired.err.split(separator: "\n").count == 2)
        writeRawTagMetadata(try plist(["LinkOnly\n3", "中文\n5"]), to: imperfect, followSymlinks: false)

        // An export can preserve link file info, but must not offer the link's
        // own tags for restoration onto a referent that might appear later.
        let exported = try context.run(["--export", root.path])
        let exportedRecords = try records(exported.out)
        let broken = exportedRecords.first { $0["path"] as? String == "dangling-0" }!
        expect(broken["tags"] == nil && broken["mtime"] as? Double == timestamp)
        expect(exported.err.hasSuffix(recursive.err))
        expect(!exported.err.contains("tags unavailable for symlink"))
        expect(exportedRecords.last?["warnings"] as? Int == 4)
        expect(exported.err.split(separator: "\n").filter { $0.contains("warning:") }.count == 1)
        let noInfo = try context.run(["--export", "--no-file-info", root.path])
        expect(noInfo.err.hasSuffix("tag: warning: 4 symlinks with non-existent targets; target tags omitted\n"))
        let archive = work.appendingPathComponent("export.jsonl")
        try Data(exported.out.utf8).write(to: archive)
        let converted = try context.run(["--convert", archive.path, "--no-tags"])
        expect(converted.out.contains("[\(date)   ~0MB] dangling-0\n"))
        #endif
    }
}
