import Foundation

struct Traversal {
    let options: Options
    var onError: (String) -> Void

    func forEachTarget(_ body: (Target) -> Void) {
        if options.paths.isEmpty {
            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            var active = Set<String>()
            enumerateDirectory(
                resolvedTagURL(cwd),
                displayPrefix: "",
                recursive: options.recursive,
                activeDirectories: &active,
                body: body
            )
            return
        }

        for path in options.paths {
            let logicalURL = expandedFileURL(path)
            do {
                guard try logicalURL.checkResourceIsReachable() else {
                    onError("not reachable: \(path)")
                    continue
                }
            } catch {
                onError("\(path): \(error.localizedDescription)")
                continue
            }

            let targetURL = resolvedTagURL(logicalURL)
            let target = Target(url: targetURL, displayPath: path)
            body(target)

            guard options.enterDirectories || options.recursive else { continue }
            do {
                if try directoryFlag(targetURL) {
                    var active = Set<String>()
                    enumerateDirectory(
                        targetURL,
                        displayPrefix: "",
                        recursive: options.recursive,
                        activeDirectories: &active,
                        body: body
                    )
                }
            } catch {
                onError("\(path): cannot determine file type: \(error.localizedDescription)")
            }
        }
    }

    func directoryFlag(_ url: URL) throws -> Bool {
        return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }

    private func enumerateDirectory(
        _ directoryURL: URL,
        displayPrefix: String,
        recursive: Bool,
        activeDirectories: inout Set<String>,
        body: (Target) -> Void
    ) {
        let resolvedDirectory = resolvedTagURL(directoryURL)
        let identity = resolvedDirectory.path
        if !activeDirectories.insert(identity).inserted {
            return
        }
        defer { activeDirectories.remove(identity) }

        var enumerationOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { enumerationOptions.insert(.skipsHiddenFiles) }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: resolvedDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .tagNamesKey],
                options: enumerationOptions
            )
        } catch {
            onError("\(resolvedDirectory.path): \(error.localizedDescription)")
            return
        }

        for logicalChild in children {
            let name = logicalChild.lastPathComponent
            let displayPath = displayPrefix.isEmpty ? name : displayPrefix + "/" + name
            let resolvedChild = resolvedTagURL(logicalChild)
            body(Target(url: resolvedChild, displayPath: displayPath))

            if recursive {
                do {
                    if try directoryFlag(resolvedChild) {
                        enumerateDirectory(
                            resolvedChild,
                            displayPrefix: displayPath,
                            recursive: true,
                            activeDirectories: &activeDirectories,
                            body: body
                        )
                    }
                } catch {
                    onError("\(logicalChild.path): cannot determine file type: \(error.localizedDescription)")
                }
            }
        }
    }
}
