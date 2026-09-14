import Foundation

let options = parseArguments()
let store = TagStore()
let output = Output(
    options: options,
    colors: FinderColors(enabled: options.color && !options.jsonLines && stdoutIsTerminal())
)
var hadError = false

func report(_ message: String) {
    eprint("\(programName): \(message)")
    hadError = true
}

func targetForExplicitPath(_ path: String) -> Target {
    let logical = expandedFileURL(path)
    let display = options.absolutePaths ? logical.path : path
    return Target(
        url: tagIOURL(logical, followSymlinks: options.followSymlinks),
        logicalURL: logical,
        displayPath: display,
        rootPath: logical.path
    )
}

switch options.operation {
case .copy:
    let sourcePath = options.paths[0]
    let destinationPath = options.paths[1]
    let source = targetForExplicitPath(sourcePath)
    let destination = targetForExplicitPath(destinationPath)

    do {
        if try !source.logicalURL.checkResourceIsReachable() {
            fail("source is not reachable: \(sourcePath)", code: ExitCode.noInput)
        }
        if try !destination.logicalURL.checkResourceIsReachable() {
            fail("destination is not reachable: \(destinationPath)", code: ExitCode.noInput)
        }

        var change = try store.copyChange(from: source.url, to: destination.url)
        change = sortedChangeIfRequested(change, options: options)
        if options.dryRun {
            try output.emitChange(
                operation: "copy", target: destination, change: change,
                source: source, dryRun: true
            )
        } else {
            try store.apply(change, to: destination.url)
            try output.emitChange(
                operation: "copy", target: destination, change: change,
                source: source, dryRun: false
            )
        }
    } catch {
        report("copying tags from \(sourcePath) to \(destinationPath): \(error.localizedDescription)")
    }

case .usage(let query):
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
        try output.emitUsage(counter.entries(sorted: options.sortedTags, reverse: options.reverse))
    } catch {
        report("writing output: \(error.localizedDescription)")
    }

case .find(let query):
    do {
        try SpotlightSearch(options: options).forEachTarget(query: query) { target in
            do {
                // Re-read the live Foundation value rather than trusting the
                // metadata index for displayed order or a just-changed file.
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

case .list, .match, .add, .remove, .set, .move:
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
                var change = try store.addChange(
                    tags,
                    to: target.url,
                    caseSensitive: options.caseSensitive,
                    position: options.position
                )
                change = sortedChangeIfRequested(change, options: options)
                if options.dryRun {
                    try output.emitChange(operation: "add", target: target, change: change, dryRun: true)
                } else {
                    try store.apply(change, to: target.url)
                    try output.emitChange(operation: "add", target: target, change: change, dryRun: false)
                }

            case .remove(let tags):
                var change = try store.removeChange(
                    tags,
                    from: target.url,
                    caseSensitive: options.caseSensitive
                )
                change = sortedChangeIfRequested(change, options: options)
                if options.dryRun {
                    try output.emitChange(operation: "remove", target: target, change: change, dryRun: true)
                } else {
                    try store.apply(change, to: target.url)
                    try output.emitChange(operation: "remove", target: target, change: change, dryRun: false)
                }

            case .set(let tags):
                var change = try store.setChange(tags, on: target.url)
                change = sortedChangeIfRequested(change, options: options)
                if options.dryRun {
                    try output.emitChange(operation: "set", target: target, change: change, dryRun: true)
                } else {
                    try store.apply(change, to: target.url)
                    try output.emitChange(operation: "set", target: target, change: change, dryRun: false)
                }

            case .move(let tag, let explicitPosition):
                guard let position = explicitPosition ?? options.position else {
                    preconditionFailure("move position validated by CLI")
                }
                var change = try store.moveChange(
                    tag: tag,
                    to: position,
                    on: target.url,
                    caseSensitive: options.caseSensitive
                )
                change = sortedChangeIfRequested(change, options: options)
                if options.dryRun {
                    try output.emitChange(operation: "move", target: target, change: change, dryRun: true)
                } else {
                    try store.apply(change, to: target.url)
                    try output.emitChange(operation: "move", target: target, change: change, dryRun: false)
                }

            case .copy, .usage, .find:
                preconditionFailure("operation handled outside traversal")
            }
        } catch {
            report("\(target.absolutePath): \(error.localizedDescription)")
        }
    }
}

do {
    try output.finish()
} catch {
    report("writing output: \(error.localizedDescription)")
}

exit(hadError ? ExitCode.ioError : 0)
