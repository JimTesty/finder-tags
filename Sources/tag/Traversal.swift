import Foundation

struct Traversal {
    let options: Options
    var onError: (String) -> Void

    func forEachTarget(_ body: (Target) -> Void) {
        if options.paths.isEmpty {
            if options.pathInputExplicit { return }

            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
                .standardizedFileURL
            var active = Set<String>()
            enumerateDirectory(
                cwd,
                rootLogicalURL: cwd,
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
                let reachable = try logicalURL.checkResourceIsReachable()
                guard reachable || isSymbolicLink(logicalURL) else {
                    onError("not reachable: \(path)")
                    continue
                }
            } catch {
                onError("\(path): \(error.localizedDescription)")
                continue
            }

            let targetURL = tagIOURL(logicalURL, followSymlinks: options.followSymlinks)
            let displayPath = options.absolutePaths ? logicalURL.path : path
            let target = Target(
                url: targetURL,
                logicalURL: logicalURL,
                displayPath: displayPath,
                rootPath: logicalURL.path
            )
            body(target)

            guard options.enterDirectories || options.recursive else { continue }
            do {
                if try directoryFlag(logicalURL) {
                    var active = Set<String>()
                    enumerateDirectory(
                        logicalURL,
                        rootLogicalURL: logicalURL,
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

    func directoryFlag(_ logicalURL: URL) throws -> Bool {
        if isSymbolicLink(logicalURL) && !options.followSymlinks {
            return false
        }
        let url = tagIOURL(logicalURL, followSymlinks: options.followSymlinks)
        return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
    }

    private func enumerateDirectory(
        _ logicalDirectoryURL: URL,
        rootLogicalURL: URL,
        displayPrefix: String,
        recursive: Bool,
        activeDirectories: inout Set<String>,
        body: (Target) -> Void
    ) {
        let directoryForIdentity = options.followSymlinks
            ? resolvedTagURL(logicalDirectoryURL)
            : logicalDirectoryURL.standardizedFileURL
        let identity = directoryForIdentity.path
        if !activeDirectories.insert(identity).inserted {
            return
        }
        defer { activeDirectories.remove(identity) }

        var enumerationOptions: FileManager.DirectoryEnumerationOptions = []
        if !options.includeHidden { enumerationOptions.insert(.skipsHiddenFiles) }

        let contentDirectoryURL = options.followSymlinks
            ? resolvedTagURL(logicalDirectoryURL)
            : logicalDirectoryURL.standardizedFileURL

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: contentDirectoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .tagNamesKey],
                options: enumerationOptions
            )
        } catch {
            onError("\(logicalDirectoryURL.path): \(error.localizedDescription)")
            return
        }

        for rawChild in children {
            let name = rawChild.lastPathComponent
            let logicalChild = logicalDirectoryURL.appendingPathComponent(name).standardizedFileURL
            let relativePath = displayPrefix.isEmpty ? name : displayPrefix + "/" + name
            if isExcluded(relativePath) { continue }
            let displayPath = options.absolutePaths ? logicalChild.path : relativePath
            let targetURL = tagIOURL(logicalChild, followSymlinks: options.followSymlinks)

            body(Target(
                url: targetURL,
                logicalURL: logicalChild,
                displayPath: displayPath,
                rootPath: rootLogicalURL.path
            ))

            if recursive {
                do {
                    if try directoryFlag(logicalChild) {
                        enumerateDirectory(
                            logicalChild,
                            rootLogicalURL: rootLogicalURL,
                            displayPrefix: relativePath,
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

    private func isExcluded(_ relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        for pattern in options.excludePatterns {
            let patternComponents = pattern.split(separator: "/").map(String.init)
            if patternComponents.count == 1 {
                if components.contains(patternComponents[0]) { return true }
            } else if components.count >= patternComponents.count,
                      Array(components.prefix(patternComponents.count)) == patternComponents {
                return true
            }
        }
        return false
    }
}
