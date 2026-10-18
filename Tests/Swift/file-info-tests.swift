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
                expect(result.err.contains("symlink target not found; using symlink's own metadata"))
                expect(result.err.split(separator: "\n").count == 1)
                #if canImport(Darwin)
                expect(record["tags"] as? [String] == ["LinkOnly", "中文"])
                expect(record["colors"] as? [Int] == [3, 5])
                #endif
            }
            let text = try context.run(["--file-info", "--no-tags", "--print-symlinks", link.path])
            expect(text.out.hasPrefix("[\(date)   ~0MB] "))
            expect(text.out.contains(" -> \(destination) (NOT FOUND)"))
            #if canImport(Darwin)
            let filtered = try context.run(["--filter", "LinkOnly", "--file-info", "--jsonl", link.path])
            expect(try records(filtered.out).last?["tags"] as? [String] == ["LinkOnly", "中文"])
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
        expect(symbolicLinkInfo(for: loop)?.targetIsMissing == false)

        #if canImport(Darwin)
        // An export can preserve link file info, but must not offer the link's
        // own tags for restoration onto a referent that might appear later.
        let exported = try context.run(["--export", root.path])
        let exportedRecords = try records(exported.out)
        let broken = exportedRecords.first { $0["path"] as? String == "dangling-0" }!
        expect(broken["tags"] == nil && broken["mtime"] as? Double == timestamp)
        expect(exported.err.contains("symlink target not found; using symlink's own file info"))
        let archive = work.appendingPathComponent("export.jsonl")
        try Data(exported.out.utf8).write(to: archive)
        let converted = try context.run(["--convert", archive.path, "--no-tags"])
        expect(converted.out.contains("[\(date)   ~0MB] dangling-0\n"))
        #endif
    }
}
