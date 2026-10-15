import Foundation

enum TextDisplayTests {
    static func expect(_ condition: Bool, _ message: String = "text display assertion failed", line: UInt = #line) {
        precondition(condition, message, file: #file, line: line)
    }

    static func run(work parent: URL, binary: URL) throws {
        expect(escapedDisplayText("a\\b\t\r\n\0\u{1b}\u{7f}\u{85}\u{2028}\u{2029}\u{202e}\u{2066}")
            == #"a\\b\t\r\n\0\u{1b}\u{7f}\u{85}\u{2028}\u{2029}\u{202e}\u{2066}"#)
        let unicode = "e\u{301} 中文 עברית العربية 👩‍💻"
        expect(escapedDisplayText(unicode) == unicode)
        expect(escapedDisplayText("\u{1b}[2J") != escapedDisplayText(#"\u{1b}[2J"#))

        let work = parent.appendingPathComponent("text-display", isDirectory: true)
        try fileManager.createDirectory(at: work, withIntermediateDirectories: true)
        func run(_ args: [String], status: Int32 = 0, executable: URL? = nil) throws -> (out: String, err: String) {
            let process = Process()
            process.executableURL = executable ?? binary
            process.arguments = args
            let stdout = Pipe(), stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            expect(process.terminationStatus == status,
                "CLI exit \(process.terminationStatus), expected \(status): \(escapedDisplayText(args.joined(separator: " ")))\n"
                + escapedDisplayText(String(decoding: err, as: UTF8.self)))
            return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
        }
        func records(_ text: String) throws -> [[String: Any]] {
            try text.split(separator: "\n").map {
                try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
            }
        }
        func expectSafeDiagnostic(_ text: String) {
            expect(!text.unicodeScalars.contains {
                ($0.value < 32 && $0.value != 10) || (127...159).contains($0.value)
            }, "diagnostic contains a raw control character")
        }

        let name = "odd\tline\ncr\r\u{1b}[2J\u{7}\u{8}\u{7f}\u{85}\u{2028}\u{202e}\\n-💜"
        let file = work.appendingPathComponent(name)
        try Data().write(to: file)
        let path = escapedDisplayText(file.path)
        expect(try run(["--no-tags", file.path]).out == path + "\n")
        expect(try run(["-0T", file.path]).out == file.path + "\0")
        let listedJSON = try records(run(["--jsonl", "--absolute", file.path]).out)
        expect(listedJSON.first?["path"] as? String == file.path)
        expect(listedJSON.last?["path"] as? String == file.path)

        let link = work.appendingPathComponent("link\t\u{1b}[2J")
        try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: name)
        expect(try run(["--slash", "--print-symlinks", link.path]).out
            == escapedDisplayText(link.path) + "@ -> " + escapedDisplayText(name) + "\n")
        expect(try run(["-0", "--print-symlinks", link.path]).out
            == link.path + " -> " + name + "\0")
        let linkJSON = try records(run(["--jsonl", "--print-symlinks", link.path]).out)
        expect(linkJSON.last?["destination"] as? String == name)

        let missing = work.appendingPathComponent("missing\n\u{1b}[2J\\n")
        let error = try run(["--no-tags", missing.path], status: 74).err
        expect(error.contains(escapedDisplayText(missing.path)))
        expect(error.filter { $0 == "\n" }.count == 1)
        expectSafeDiagnostic(error)
        let optionError = try run(["--bad\t\u{1b}[2J"], status: 64).err
        expect(optionError.contains(#"--bad\t\u{1b}[2J"#))
        expectSafeDiagnostic(optionError)

        let alias = work.appendingPathComponent("tag\t\u{1b}[2J\\n")
        try fileManager.createSymbolicLink(atPath: alias.path, withDestinationPath: binary.path)
        let aliasName = escapedDisplayText(alias.lastPathComponent)
        expect(try run(["--version"], executable: alias).out == aliasName + " 8.0\n")
        let help = try run(["--help"], executable: alias).out
        expect(help.hasPrefix(aliasName + " - "))
        expect(!help.contains("\u{1b}"))

        let tag = "\u{1b}[2J\tPurple\\n"
        let dry = try run(["--set", tag, "--dry-run", "--verbose", file.path])
        expect(dry.out.contains(path + "\t"))
        expect(dry.out.contains(escapedDisplayText(tag)))
        expect(dry.err.contains(path) && dry.err.contains(escapedDisplayText(tag)))
        expectSafeDiagnostic(dry.err)
        let dryJSON = try records(run(["--set", tag, "--dry-run", "--jsonl", file.path]).out)
        expect(dryJSON.last?["after"] as? [String] == [tag])

        // Conversion must escape each field before adding the program's colors.
        let archive = work.appendingPathComponent("display.jsonl")
        let objects: [[String: Any]] = [
            ["type": "header", "format": "jsonl", "version": 3, "followSymlinks": true],
            ["type": "root", "path": work.path],
            ["type": "item", "path": name, "kind": "symlink", "tags": [tag], "colors": [3],
             "destination": missing.lastPathComponent, "targetExists": false],
            ["type": "summary"]
        ]
        let lines = try objects.map { try JSONSerialization.data(withJSONObject: $0) }
        var data = Data()
        for line in lines { data.append(line); data.append(10) }
        try data.write(to: archive)
        let purple = "\u{1b}[48;5;129m", reset = "\u{1b}[m"
        let converted = try run(["--convert", archive.path, "--print-symlinks", "--space-indent", "--color=force"])
        expect(converted.out == escapedDisplayText(name) + " -> " + escapedDisplayText(missing.lastPathComponent)
            + " \u{1b}[31m(NOT FOUND)" + reset + "  " + purple + escapedDisplayText(tag) + reset + "\n")
        expect(try run(["--convert", archive.path, "-0", "--no-name"]).out == tag + "\0")
        expect(try run(["--convert", archive.path, "--no-name", "--compact-tags", "--color=force"]).out
            == purple + #"\u{1b}"# + reset + "\n")

        #if canImport(Darwin)
        // Real stored names and color numbers must remain unchanged by display.
        let stored = [StoredTag(name: tag, color: 3)]
        try FileTagMetadata.write(stored, to: file)
        expect(try run(["--no-name", "--color=force", file.path]).out
            == purple + escapedDisplayText(tag) + reset + "\n")
        expect(try run(["-0N", file.path]).out == tag + "\0")
        expect(try run(["--one-per-line", "--no-name", file.path]).out == escapedDisplayText(tag) + "\n")
        expect(try run(["--usage", "*", file.path]).out == "1\t" + escapedDisplayText(tag) + "\n")
        expect(try run(["--usage", "*", "-0", file.path]).out == "1\t" + tag + "\0")
        let json = try records(run(["--jsonl", file.path]).out)
        expect(json.last?["tags"] as? [String] == [tag])
        let exported = try records(run(["--export", "--no-file-info", work.path]).out)
        expect(exported.first { $0["path"] as? String == name }?["tags"] as? [String] == [tag])
        expect(try TagStore().readTags(file) == stored)

        let destination = work.appendingPathComponent("destination\t\u{1b}[2J")
        try Data().write(to: destination)
        let copy = try run(["--copy", file.path, destination.path, "--dry-run", "--verbose"])
        expect(copy.err.contains(" from " + path + ":"))
        expectSafeDiagnostic(copy.err)
        try FileTagMetadata.write([StoredTag(name: tag, color: 99)], to: destination)
        let unknown = try run(["--verbose", destination.path]).err
        expect(unknown.contains("tag '" + escapedDisplayText(tag) + "' has unrecognized stored color 99"))
        let conflicting = try run(["--usage", "*", "--verbose", file.path, destination.path]).err
        expect(conflicting.contains("tag '" + escapedDisplayText(tag) + "' has different stored colors [3, 99]"))
        expectSafeDiagnostic(unknown + conflicting)
        let backup = work.appendingPathComponent("undo\n\u{1b}[2J.jsonl")
        let mutation = try run(["--set", "Changed", file.path, "--backup", backup.path])
        expect(mutation.err.contains(escapedDisplayText(backup.path)))
        expectSafeDiagnostic(mutation.err)
        _ = try run(["--restore", backup.path, "--no-backup"])
        expect(try TagStore().readTags(file) == stored)
        #endif
        print("Text display tests passed")
    }
}
