import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct TagColorInfo {
    let name: String
    let color: Int
}

struct FinderColors {
    private let ansiByName: [String: String]
    let isEnabled: Bool
    let archiveTagColors: [TagColorInfo]

    init(enabled: Bool, verbose: Bool = false) {
        let report: ((String) -> Void)? = verbose ? {
            eprint("\(programName): info: \($0)")
        } : nil
        self.init(enabled: enabled, tagColors: FinderColors.load(report: report))
    }

    init(enabled: Bool, tagColors: [TagColorInfo]) {
        isEnabled = enabled
        archiveTagColors = tagColors
        var escapes: [String: String] = [:]
        if enabled {
            for tag in tagColors {
                escapes[foldedTag(tag.name)] = FinderColors.ansiByCode[tag.color]
            }
        }
        ansiByName = escapes
    }

    func render(_ tag: String) -> String {
        guard let escape = ansiByName[foldedTag(tag)] else { return tag }
        return escape + tag + "\u{001B}[m"
    }

    func renderFirstCharacter(of tag: String) -> String {
        guard let first = tag.first else { return "" }
        let character = String(first)
        guard let escape = ansiByName[foldedTag(tag)] else { return character }
        return escape + character + "\u{001B}[m"
    }

    func renderMissing(_ text: String) -> String {
        guard isEnabled else { return text }
        return "\u{001B}[31m\(text)\u{001B}[m"
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

    private static func load(report: ((String) -> Void)?) -> [TagColorInfo] {
        // Finder need not persist its standard tags in its private preferences.
        // NSWorkspace exposes their localized names in label-number order.
        #if canImport(AppKit)
        let defaults: [TagColorInfo] = NSWorkspace.shared.fileLabels.enumerated().compactMap { code, name in
            code == 0 || name.isEmpty ? nil : TagColorInfo(name: name, color: code)
        }
        report?("loaded \(defaults.count) standard Finder tag colors from macOS")
        #else
        let defaults: [TagColorInfo] = []
        #endif

        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/SyncedPreferences/com.apple.finder.plist"),
            home.appendingPathComponent("Library/Preferences/com.apple.finder.plist")
        ]
        return load(defaultTagColors: defaults, preferenceURLs: candidates, report: report)
    }

    static func load(
        defaultTagColors: [TagColorInfo],
        preferenceURLs: [URL],
        report: ((String) -> Void)? = nil
    ) -> [TagColorInfo] {
        var metadata = defaultTagColors
        var indexByName: [String: Int] = [:]
        for (index, tag) in metadata.enumerated() {
            indexByName[foldedTag(tag.name)] = index
        }

        // Keep Finder's synced list authoritative when present. Fill in standard
        // labels from macOS rather than resurrecting stale custom definitions
        // from a lower-priority preference file.
        for url in preferenceURLs {
            let plist: Any
            do {
                let data = try Data(contentsOf: url)
                plist = try PropertyListSerialization.propertyList(
                    from: data, options: [], format: nil
                )
            } catch {
                report?("could not load Finder tag colors from \(url.path): \(error.localizedDescription)")
                continue
            }
            guard let entries = findFinderTags(in: plist) else {
                report?("no FinderTags list in \(url.path)")
                continue
            }

            var loadedCount = 0
            for entry in entries {
                guard let name = entry["n"] as? String,
                      let color = entry["l"] as? NSNumber
                else { continue }

                let tag = TagColorInfo(name: name, color: color.intValue)
                let key = foldedTag(name)
                if let index = indexByName[key] {
                    metadata[index] = tag
                } else {
                    indexByName[key] = metadata.count
                    metadata.append(tag)
                }
                loadedCount += 1
            }
            report?("loaded \(loadedCount) Finder tag color definitions from \(url.path)")
            return metadata
        }

        return metadata
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
