import Foundation

// Tests the production loader against isolated preferences, independently of
// the user's Finder settings. The shell runner owns this fixture directory.
@main
enum FinderColorTests {
    static func main() throws {
        let work = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let synced = work.appendingPathComponent("synced.plist")
        let ordinary = work.appendingPathComponent("ordinary.plist")
        let preferences = [synced, ordinary]
        let defaults = [
            TagColorInfo(name: "Gray", color: 1),
            TagColorInfo(name: "Green", color: 2),
            TagColorInfo(name: "Purple", color: 3),
            TagColorInfo(name: "Blue", color: 4),
            TagColorInfo(name: "Yellow", color: 5),
            TagColorInfo(name: "Red", color: 6),
            TagColorInfo(name: "Orange", color: 7)
        ]
        let red = "\u{001B}[41m"
        let blue = "\u{001B}[44m"
        let reset = "\u{001B}[m"

        func load(_ base: [TagColorInfo]? = nil) -> FinderColors {
            return FinderColors(enabled: true, tagColors: FinderColors.load(
                defaultTagColors: base ?? defaults, preferenceURLs: preferences
            ))
        }

        func write(_ object: Any, to url: URL) throws {
            let data = try PropertyListSerialization.data(
                fromPropertyList: object, format: .binary, options: 0
            )
            try data.write(to: url)
        }

        // Missing, malformed, absent-key, and empty preference data retain defaults.
        let missing = load()
        precondition(missing.archiveTagColors.count == 7)
        precondition(missing.render("rED") == red + "rED" + reset)
        precondition(missing.renderFirstCharacter(of: "Red") == red + "R" + reset)
        precondition(missing.render("Unknown") == "Unknown")
        try Data("invalid plist".utf8).write(to: synced)
        precondition(load().render("Red") == red + "Red" + reset)
        try write(["OtherSetting": true], to: synced)
        precondition(load().render("Red") == red + "Red" + reset)
        try write(["FinderTags": [[String: Any]]()], to: synced)
        precondition(load().archiveTagColors.count == 7)

        // Use ordinary preferences when the synced file is unavailable.
        try FileManager.default.removeItem(at: synced)
        try write(["FinderTags": [
            ["n": "Red", "l": 4], ["n": "Project", "l": 6],
            ["n": "OldProject", "l": 6]
        ]], to: ordinary)
        precondition(load().render("Red") == blue + "Red" + reset)
        precondition(load().render("Project") == red + "Project" + reset)

        // Synced definitions win case-insensitively, including explicit no color.
        // Omitted standard labels retain defaults; stale custom definitions in
        // the lower-priority file must not reappear.
        try write(["values": ["FinderTagDict": ["value": ["FinderTags": [
            ["n": "rED", "l": 0], ["n": "Project", "l": 4],
            ["n": "Unexpected", "l": 99], ["n": "MissingColor"]
        ]]]]], to: synced)
        let merged = load()
        precondition(merged.render("Red") == "Red")
        precondition(merged.renderFirstCharacter(of: "Red") == "R")
        precondition(merged.render("Project") == blue + "Project" + reset)
        precondition(merged.render("OldProject") == "OldProject")
        precondition(merged.render("Blue") == blue + "Blue" + reset)
        precondition(merged.archiveTagColors.filter { foldedTag($0.name) == "red" }.count == 1)
        precondition(merged.archiveTagColors.first { $0.name == "rED" }?.color == 0)
        precondition(merged.archiveTagColors.first { $0.name == "Unexpected" }?.color == 99)
        precondition(merged.render("Unexpected") == "Unexpected")

        // Localized names are used as supplied by macOS, without English aliases.
        let localized = load([TagColorInfo(name: "Rouge", color: 6)])
        precondition(localized.render("rouge") == red + "rouge" + reset)
        let disabled = FinderColors(enabled: false, tagColors: merged.archiveTagColors)
        precondition(disabled.render("Project") == "Project")
        precondition(disabled.archiveTagColors.count == merged.archiveTagColors.count)

        try write(["FinderTags": [[String: Any]]()], to: synced)
        precondition(load().render("Red") == red + "Red" + reset)
        precondition(load().render("OldProject") == "OldProject")
        print("Finder color tests passed")
    }
}
