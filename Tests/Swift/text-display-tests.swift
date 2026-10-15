import Foundation

enum TextDisplayTests {
    static func run(_ context: TestContext) throws {
        expect(escapedDisplayText("a\\b\t\r\n\0\u{1b}\u{7f}\u{85}\u{2028}\u{2029}\u{202e}\u{2066}")
            == #"a\\b\t\r\n\0\u{1b}\u{7f}\u{85}\u{2028}\u{2029}\u{202e}\u{2066}"#)
        let unicode = "e\u{301} 中文 עברית العربية 👩‍💻"
        expect(escapedDisplayText(unicode) == unicode)
        expect(escapedDisplayText("\u{1b}[2J") != escapedDisplayText(#"\u{1b}[2J"#))

        let work = try context.makeWorkDirectory("text-display")
        func expectSafeDiagnostic(_ text: String) {
            expect(!text.unicodeScalars.contains {
                ($0.value < 32 && $0.value != 10) || (127...159).contains($0.value)
            }, "diagnostic contains a raw control character")
        }

        let name = "odd\tline\ncr\r\u{1b}[2J\u{7}\u{8}\u{7f}\u{85}\u{2028}\u{202e}\\n-💜"
        let file = work.appendingPathComponent(name)
        try Data().write(to: file)
        let path = escapedDisplayText(file.path)
        expect(try context.run(["--no-tags", file.path]).out == path + "\n")
        expect(try context.run(["-0T", file.path]).out == file.path + "\0")
        let listedJSON = try records(context.run(["--jsonl", "--absolute", file.path]).out)
        expect(listedJSON.first?["path"] as? String == file.path)
        expect(listedJSON.last?["path"] as? String == file.path)

        let link = work.appendingPathComponent("link\t\u{1b}[2J")
        try fileManager.createSymbolicLink(atPath: link.path, withDestinationPath: name)
        expect(try context.run(["--slash", "--print-symlinks", link.path]).out
            == escapedDisplayText(link.path) + "@ -> " + escapedDisplayText(name) + "\n")
        expect(try context.run(["-0", "--print-symlinks", link.path]).out
            == link.path + " -> " + name + "\0")
        let linkJSON = try records(context.run(["--jsonl", "--print-symlinks", link.path]).out)
        expect(linkJSON.last?["destination"] as? String == name)

        let missing = work.appendingPathComponent("missing\n\u{1b}[2J\\n")
        let error = try context.run(["--no-tags", missing.path], status: 74).err
        expect(error.contains(escapedDisplayText(missing.path)))
        expect(error.filter { $0 == "\n" }.count == 1)
        expectSafeDiagnostic(error)
        let optionError = try context.run(["--bad\t\u{1b}[2J"], status: 64).err
        expect(optionError.contains(#"--bad\t\u{1b}[2J"#))
        expectSafeDiagnostic(optionError)

        let alias = work.appendingPathComponent("tag\t\u{1b}[2J\\n")
        try fileManager.createSymbolicLink(atPath: alias.path, withDestinationPath: context.binary.path)
        let aliasName = escapedDisplayText(alias.lastPathComponent)
        expect(try context.run(["--version"], executable: alias).out == aliasName + " 8.0\n")
        let help = try context.run(["--help"], executable: alias).out
        expect(help.hasPrefix(aliasName + " - "))
        expect(!help.contains("\u{1b}"))

        let tag = "\u{1b}[2J\tPurple\\n"
        let dry = try context.run(["--set", tag, "--dry-run", "--verbose", file.path])
        expect(dry.out.contains(path + "\t"))
        expect(dry.out.contains(escapedDisplayText(tag)))
        expect(dry.err.contains(path) && dry.err.contains(escapedDisplayText(tag)))
        expectSafeDiagnostic(dry.err)
        let dryJSON = try records(context.run(["--set", tag, "--dry-run", "--jsonl", file.path]).out)
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
        try writeRecords(objects, to: archive)
        let purple = "\u{1b}[48;5;129m", reset = "\u{1b}[m"
        let converted = try context.run(["--convert", archive.path, "--print-symlinks", "--space-indent", "--color=force"])
        expect(converted.out == escapedDisplayText(name) + " -> " + escapedDisplayText(missing.lastPathComponent)
            + " \u{1b}[31m(NOT FOUND)" + reset + "  " + purple + escapedDisplayText(tag) + reset + "\n")
        expect(try context.run(["--convert", archive.path, "-0", "--no-name"]).out == tag + "\0")
        expect(try context.run(["--convert", archive.path, "--no-name", "--compact-tags", "--color=force"]).out
            == purple + #"\u{1b}"# + reset + "\n")

        #if canImport(Darwin)
        // Real stored names and color numbers must remain unchanged by display.
        let stored = [StoredTag(name: tag, color: 3)]
        try FileTagMetadata.write(stored, to: file)
        expect(try context.run(["--no-name", "--color=force", file.path]).out
            == purple + escapedDisplayText(tag) + reset + "\n")
        expect(try context.run(["-0N", file.path]).out == tag + "\0")
        expect(try context.run(["--one-per-line", "--no-name", file.path]).out == escapedDisplayText(tag) + "\n")
        expect(try context.run(["--usage", "*", file.path]).out == "1\t" + escapedDisplayText(tag) + "\n")
        expect(try context.run(["--usage", "*", "-0", file.path]).out == "1\t" + tag + "\0")
        let json = try records(context.run(["--jsonl", file.path]).out)
        expect(json.last?["tags"] as? [String] == [tag])
        let exported = try records(context.run(["--export", "--no-file-info", work.path]).out)
        expect(exported.first { $0["path"] as? String == name }?["tags"] as? [String] == [tag])
        expect(try TagStore().readTags(file) == stored)

        let destination = work.appendingPathComponent("destination\t\u{1b}[2J")
        try Data().write(to: destination)
        let copy = try context.run(["--copy", file.path, destination.path, "--dry-run", "--verbose"])
        expect(copy.err.contains(" from " + path + ":"))
        expectSafeDiagnostic(copy.err)
        try FileTagMetadata.write([StoredTag(name: tag, color: 99)], to: destination)
        let unknown = try context.run(["--verbose", destination.path]).err
        expect(unknown.contains("tag '" + escapedDisplayText(tag) + "' has unrecognized stored color 99"))
        let conflicting = try context.run(["--usage", "*", "--verbose", file.path, destination.path]).err
        expect(conflicting.contains("tag '" + escapedDisplayText(tag) + "' has different stored colors [3, 99]"))
        expectSafeDiagnostic(unknown + conflicting)
        let backup = work.appendingPathComponent("undo\n\u{1b}[2J.jsonl")
        let mutation = try context.run(["--set", "Changed", file.path, "--backup", backup.path])
        expect(mutation.err.contains(escapedDisplayText(backup.path)))
        expectSafeDiagnostic(mutation.err)
        _ = try context.run(["--restore", backup.path, "--no-backup"])
        expect(try TagStore().readTags(file) == stored)
        #endif
    }
}
