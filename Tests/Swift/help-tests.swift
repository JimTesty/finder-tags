import Foundation

enum HelpTests {
    static func run(_ context: TestContext) throws {
        let brief = try context.run(["-h"])
        let detailed = try context.run(["-hh"])
        expect(brief.err.isEmpty && detailed.err.isEmpty)
        expect(brief.out != detailed.out)
        expect(try context.run(["--help"]).out == brief.out)

        // Repetition and verbosity select the same detail level in any order.
        for args in [["-h", "-h"], ["-h", "-v"], ["-v", "-h"], ["-hv"], ["-vh"],
                     ["--help", "--verbose"], ["--verbose", "--help"], ["--help", "--help"]] {
            let result = try context.run(args)
            expect(result.out == detailed.out && result.err.isEmpty, "help differs for \(args)")
        }
        expect(brief.out.contains("Many options have --no-... negations"))
        let name = context.binary.lastPathComponent
        expect(brief.out.hasSuffix("For detailed help: \(name) -hh (or \(name) -h -v)\n"))
        expect(!brief.out.contains("Important differences from jdberry/tag:"))
        expect(detailed.out.contains("Important differences from jdberry/tag:"))
        expect(brief.out.contains("--filter TAGS") && brief.out.contains("--tagged-only"))
        for text in [brief.out, detailed.out] {
            expect(text.contains("-c, --color[=yes/no]"))
            expect(text.contains("Color tags and other output (default: auto)"))
        }
        for option in ["--match", "--no-color", "--no-file-info", "--no-backup", "--no-sort-files", "--stdin0",
                       "--compact-tags", "--usage", "--convert", "--backup-path",
                       "--repair", "--replace", "--include-hidden", "--del", "--delete",
                       "--sort-tags", "--descend", "--root"] {
            expect(!brief.out.contains(option), "brief help contains \(option)")
            expect(detailed.out.contains(option), "detailed help omits \(option)")
        }

        // Help must exit before reading paths from stdin or validating an edit.
        expect(try context.run(["--stdin", "-h", "-v"], input: "").out == detailed.out)
        expect(try context.run(["--set", "Unused", "--help"]).out == brief.out)

        // Help-like text consumed as a tag operand must keep its literal meaning.
        let work = try context.makeWorkDirectory("help")
        let file = work.appendingPathComponent("file")
        try Data().write(to: file)
        for tag in ["-hh", "--help"] {
            let result = try context.run(["--set", tag, "--dry-run", "--jsonl", file.path])
            expect(try records(result.out).last?["after"] as? [String] == [tag])
        }
    }
}
