import Foundation

struct Traversal {
    let options: Options
    var onError: (String) -> Void

    func forEachTarget(_ body: (Target) -> Void) {
        if options.paths.isEmpty {
            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            enumerateDirectory(
                Target(url: cwd, displayPath: ""),
                recursive: options.recursive,
                body: body
            )
            return
        }

        for path in options.paths {
            let url = expandedFileURL(path)

            do {
                guard try url.checkResourceIsReachable() else {
                    onError("not reachable: \(path)")
                    continue
                }
            } catch {
                onError("\(path): \(error.localizedDescription)")
                continue
            }

            let target = Target(url: url, displayPath: path)
            body(target)

            guard options.enterDirectories || options.recursive else { continue }
            do {
                if try directoryFlag(url) {
                    enumerateDirectory(target, recursive: options.recursive, body: body)
                }
            } catch {
                onError("\(path): cannot determine file type: \(error.localizedDescription)")
            }
        }
    }

    func directoryFlag(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }

    private func enumerateDirectory(
        _ directory: Target,
        recursive: Bool,
        body: (Target) -> Void
    ) {
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { enumerationOptions.insert(.skipsHiddenFiles) }
        if !recursive { enumerationOptions.insert(.skipsSubdirectoryDescendants) }

        guard let enumerator = fileManager.enumerator(
            at: directory.url,
            includingPropertiesForKeys: [.isDirectoryKey, .tagNamesKey],
            options: enumerationOptions,
            errorHandler: { url, error in
                onError("\(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            onError("unable to enumerate \(directory.displayPath.isEmpty ? "." : directory.displayPath)")
            return
        }

        for case let url as URL in enumerator {
            // Match jdberry/tag: after printing an explicit directory itself,
            // enumerate its children relative to that directory rather than
            // repeating the directory argument as a prefix.
            let relative = relativePath(of: url, under: directory.url)
            body(Target(url: url, displayPath: relative))
        }
    }

    private func relativePath(of child: URL, under directory: URL) -> String {
        let base = directory.standardizedFileURL.path
        let full = child.standardizedFileURL.path

        guard full == base || full.hasPrefix(base + "/") else {
            return child.lastPathComponent
        }

        if full == base { return "" }
        return String(full.dropFirst(base.count + 1))
    }

}
