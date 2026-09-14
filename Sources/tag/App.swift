import Foundation

final class App {
    private let options: Options
    private let store = TagStore()
    private let output: Output
    private var hadError = false

    init(options: Options) {
        self.options = options
        self.output = Output(
            options: options,
            colors: FinderColors(
                enabled: options.color && !options.jsonLines && stdoutIsTerminal()
            )
        )
    }

    func run() -> Int32 {
        switch options.operation {
        case .copy:
            runCopy()
        case .usage(let query):
            runUsage(query)
        case .find(let query):
            runFind(query)
        case .list, .match, .add, .remove, .set, .move:
            runTraversal()
        }

        return hadError ? ExitCode.ioError : 0
    }

    private func report(_ message: String) {
        eprint("\(programName): \(message)")
        hadError = true
    }

    private func explicitTarget(_ path: String) -> Target {
        let logical = expandedFileURL(path)
        return Target(
            url: tagIOURL(logical, followSymlinks: options.followSymlinks),
            logicalURL: logical,
            displayPath: options.absolutePaths ? logical.path : path,
            rootPath: logical.path
        )
    }

    private func runCopy() {
        let sourcePath = options.paths[0]
        let destinationPath = options.paths[1]
        let source = explicitTarget(sourcePath)
        let destination = explicitTarget(destinationPath)

        do {
            guard try source.logicalURL.checkResourceIsReachable() else {
                fail("source is not reachable: \(sourcePath)", code: ExitCode.noInput)
            }
            guard try destination.logicalURL.checkResourceIsReachable() else {
                fail("destination is not reachable: \(destinationPath)", code: ExitCode.noInput)
            }

            let change = try store.copyChange(from: source.url, to: destination.url)
            try performMutation(
                "copy", target: destination, change: change, source: source
            )
        } catch {
            report("copying tags from \(sourcePath) to \(destinationPath): \(error.localizedDescription)")
        }
    }

    private func runUsage(_ query: [String]) {
        let traversal = Traversal(options: options, onError: report)
        var counter = UsageCounter()

        traversal.forEachTarget { target in
            do {
                let tags = try store.read(target.url)
                if tagsMatch(tags, query: query, caseSensitive: options.caseSensitive) {
                    counter.add(tags)
                }
            } catch {
                report("\(target.absolutePath): \(error.localizedDescription)")
            }
        }

        do {
            try output.emitUsage(
                counter.entries(sorted: options.sortedTags, reverse: options.reverse)
            )
        } catch {
            report("writing output: \(error.localizedDescription)")
        }
    }

    private func runFind(_ query: [String]) {
        do {
            try SpotlightSearch(options: options).forEachTarget(query: query) { target in
                do {
                    // Re-read the live Foundation value rather than trusting
                    // the metadata index for order or a just-changed file.
                    let tags = try store.read(target.url)
                    if tagsMatch(tags, query: query, caseSensitive: options.caseSensitive) {
                        try output.emitFile(target, tags: tags)
                    }
                } catch {
                    report("\(target.absolutePath): \(error.localizedDescription)")
                }
            }
        } catch {
            report(error.localizedDescription)
        }
    }

    private func runTraversal() {
        let traversal = Traversal(options: options, onError: report)

        traversal.forEachTarget { target in
            do {
                switch options.operation {
                case .list:
                    try output.emitFile(target, tags: store.read(target.url))

                case .match(let query):
                    let tags = try store.read(target.url)
                    if tagsMatch(tags, query: query, caseSensitive: options.caseSensitive) {
                        try output.emitFile(target, tags: tags)
                    }

                case .add(let tags):
                    let change = try store.addChange(
                        tags,
                        to: target.url,
                        caseSensitive: options.caseSensitive,
                        position: options.position
                    )
                    try performMutation("add", target: target, change: change)

                case .remove(let tags):
                    let change = try store.removeChange(
                        tags,
                        from: target.url,
                        caseSensitive: options.caseSensitive
                    )
                    try performMutation("remove", target: target, change: change)

                case .set(let tags):
                    let change = try store.setChange(tags, on: target.url)
                    try performMutation("set", target: target, change: change)

                case .move(let tag, let explicitPosition):
                    guard let position = explicitPosition ?? options.position else {
                        preconditionFailure("move position validated by CLI")
                    }
                    let change = try store.moveChange(
                        tag: tag,
                        to: position,
                        on: target.url,
                        caseSensitive: options.caseSensitive
                    )
                    try performMutation("move", target: target, change: change)

                case .copy, .usage, .find:
                    preconditionFailure("operation handled outside traversal")
                }
            } catch {
                report("\(target.absolutePath): \(error.localizedDescription)")
            }
        }
    }

    private func performMutation(
        _ operation: String,
        target: Target,
        change rawChange: TagChange,
        source: Target? = nil
    ) throws {
        let change = sortedChangeIfRequested(rawChange, options: options)
        if !options.dryRun {
            try store.apply(change, to: target.url)
        }
        try output.emitChange(
            operation: operation,
            target: target,
            change: change,
            source: source,
            dryRun: options.dryRun
        )
    }
}
