import Foundation
#if canImport(Darwin)
import Darwin
#endif

enum MetadataTests {
    static func run(_ context: TestContext) throws {
        let decoded = try FileTagMetadata.decode(plist(["Custom\n3", "None\n0", "Odd\n99", "Negative\n-3", "Bare"]))
        expect(decoded.map { $0.color } == [3, 0, 99, -3, nil])
        for invalid: Any in [["Bad\nwrong"], [""], ["Bad\nname\n3"], ["Not": "an array"],
                             ["Bad\r\nName\n3"], ["Bad\0Name\n3"], ["Bad\rName"], ["Bad\r\n3"]] {
            do {
                _ = try FileTagMetadata.decode(plist(invalid))
                preconditionFailure("accepted malformed tag metadata")
            } catch {}
        }

        #if canImport(Darwin)
        let work = try context.makeWorkDirectory("metadata")
        let root = work.appendingPathComponent("root", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let good = root.appendingPathComponent("good")
        try taggedFile(good, tags: [StoredTag(name: "Keep", color: 0)])
        // Malformed raw metadata must fail before a mutation or undo write.
        let malformedData = try plist(["Bad\0Name\n3"])
        let setStatus = malformedData.withUnsafeBytes {
            setxattr(good.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, $0.count, 0, 0)
        }
        expect(setStatus == 0)
        let invalidUndo = work.appendingPathComponent("invalid-undo.jsonl")
        let invalidMutation = try context.run(["--set", "Healthy", good.path, "--backup", invalidUndo.path], status: 74)
        expect(invalidMutation.err.contains(#"invalid stored tag: 'Bad\0Name\n3'"#))
        expect(!fileManager.fileExists(atPath: invalidUndo.path))
        _ = try context.run(["--export", root.path, "--no-file-info"], status: 74)
        #endif
    }
}
