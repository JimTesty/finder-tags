import Foundation

enum StdinTests {
    static func run(_ context: TestContext) throws {
        let work = try context.makeWorkDirectory("stdin")
        let explicit = work.appendingPathComponent("explicit")
        let piped = work.appendingPathComponent("piped")
        let replacement = work.appendingPathComponent("�")
        let baseline = [StoredTag(name: "Keep", color: 0)]
        for file in [explicit, piped, replacement] {
            try Data().write(to: file)
            #if canImport(Darwin)
            try FileTagMetadata.write(baseline, to: file)
            #endif
        }
        let backup = work.appendingPathComponent("must-not-be-created.jsonl")
        for (flag, separator) in [("--stdin", UInt8(10)), ("--stdin0", UInt8(0))] {
            var input = Data(piped.path.utf8)
            input.append(separator)
            input.append(contentsOf: (work.path + "/").utf8)
            input.append(0xff) // Lossy decoding would select the real � file.
            input.append(separator)
            let failed = try context.run([flag, "--set", "Changed", explicit.path,
                                          "--backup-path", backup.path], status: 64, inputData: input)
            expect(failed.out.isEmpty && failed.err.contains("record 2 is not valid UTF-8"))
            expect(!fileManager.fileExists(atPath: backup.path))
        }
        _ = try context.run(["--stdin", "--set", "Changed", explicit.path, "--no-backup"],
                            status: 64, input: piped.path + "\0" + replacement.path + "\n")
        #if canImport(Darwin)
        for file in [explicit, piped, replacement] {
            expect(try TagStore().readTags(file) == baseline)
        }
        #endif

        let embeddedCR = work.appendingPathComponent("one\rtwo")
        let finalCR = work.appendingPathComponent("final\r")
        let newline = work.appendingPathComponent("line\nbreak\rend")
        for file in [embeddedCR, finalCR, newline] { try Data().write(to: file) }
        let lines = try context.run(["--stdin", "-0T"],
                                    input: embeddedCR.path + "\r\n" + replacement.path + "\n" + finalCR.path)
        expect(lines.out == [embeddedCR.path, replacement.path, finalCR.path].joined(separator: "\0") + "\0")
        let nul = try context.run(["--stdin0", "-0T"], input: newline.path + "\0" + finalCR.path + "\0")
        expect(nul.out == newline.path + "\0" + finalCR.path + "\0")
    }
}
