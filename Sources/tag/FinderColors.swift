import Foundation

struct FinderColors {
    private let ansiByName: [String: String]
    let isEnabled: Bool

    init(enabled: Bool) {
        isEnabled = enabled
        ansiByName = enabled ? FinderColors.load() : [:]
    }

    func render(_ tag: String) -> String {
        guard let escape = ansiByName[foldedTag(tag)] else { return tag }
        return escape + tag + "\u{001B}[m"
    }

    private static let ansiByCode: [Int: String] = [
        1: "\u{001B}[48;5;241m", // gray
        2: "\u{001B}[42m",       // green
        3: "\u{001B}[48;5;129m", // purple
        4: "\u{001B}[44m",       // blue
        5: "\u{001B}[43m",       // yellow
        6: "\u{001B}[41m",       // red
        7: "\u{001B}[48;5;208m"  // orange
    ]

    private static func load() -> [String: String] {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/SyncedPreferences/com.apple.finder.plist"),
            home.appendingPathComponent("Library/Preferences/com.apple.finder.plist")
        ]

        for url in candidates {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                  ),
                  let entries = findFinderTags(in: plist)
            else { continue }

            var result: [String: String] = [:]
            for entry in entries {
                guard let name = entry["n"] as? String,
                      let color = entry["l"] as? NSNumber,
                      let escape = ansiByCode[color.intValue]
                else { continue }

                result[foldedTag(name)] = escape
            }
            return result
        }

        return [:]
    }

    private static func findFinderTags(in object: Any) -> [[String: Any]]? {
        if let dict = object as? [String: Any] {
            if let tags = dict["FinderTags"] as? [[String: Any]] {
                return tags
            }
            for value in dict.values {
                if let found = findFinderTags(in: value) { return found }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = findFinderTags(in: value) { return found }
            }
        }
        return nil
    }
}
