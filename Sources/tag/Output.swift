import Foundation

struct Output {
    let options: Options
    let colors: FinderColors

    func emit(_ target: Target, tags storedTags: [String]) throws {
        var tags = storedTags
        if options.reverse { tags.reverse() }

        let renderedTags = options.showTags ? tags.map(colors.render) : []
        let name = options.showNames ? try displayPath(target) : nil

        if options.oneTagPerLine {
            if let name = name { record(name) }
            for tag in renderedTags {
                record((name == nil ? "" : "    ") + tag)
            }
            return
        }

        if let name = name {
            if renderedTags.isEmpty {
                record(name)
            } else {
                let padding = max(1, 31 - name.count)
                record(
                    name
                    + String(repeating: " ", count: padding)
                    + "\t"
                    + renderedTags.joined(separator: ",")
                )
            }
        } else if !renderedTags.isEmpty {
            record(renderedTags.joined(separator: ","))
        }
    }

    private func displayPath(_ target: Target) throws -> String {
        guard options.slashDirectories else { return target.displayPath }
        guard try target.url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            return target.displayPath
        }
        return target.displayPath.hasSuffix("/") ? target.displayPath : target.displayPath + "/"
    }

    private func record(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
        FileHandle.standardOutput.write(Data([options.nulTerminate ? 0 : 10]))
    }
}
