import Foundation

let options = parseArguments()
let store = TagStore()
let output = Output(options: options, colors: FinderColors(enabled: options.color && !options.json))
var hadError = false

func report(_ message: String) {
    eprint("\(programName): \(message)")
    hadError = true
}

func operationName(_ operation: Operation) -> String {
    switch operation {
    case .add: return "add"
    case .remove: return "remove"
    case .set: return "set"
    case .copy: return "copy"
    case .list: return "list"
    case .match: return "match"
    case .usage: return "usage"
    }
}

switch options.operation {
case .copy:
    let sourcePath = options.paths[0]
    let destinationPath = options.paths[1]
    let source = expandedFileURL(sourcePath)
    let destination = expandedFileURL(destinationPath)

    do {
        if try !source.checkResourceIsReachable() {
            fail("source is not reachable: \(sourcePath)", code: ExitCode.noInput)
        }
        if try !destination.checkResourceIsReachable() {
            fail("destination is not reachable: \(destinationPath)", code: ExitCode.noInput)
        }

        let change = try store.copyChange(from: source, to: destination)
        if options.dryRun {
            output.emitDryRun(
                operation: "copy",
                target: Target(url: destination, displayPath: destinationPath),
                change: change,
                sourcePath: sourcePath
            )
        } else {
            try store.apply(change, to: destination)
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
            if tagsMatch(tags, query: query) {
                counter.add(tags)
            }
        } catch {
            report("\(target.displayPath): \(error.localizedDescription)")
        }
    }
    output.emitUsage(counter.entries(reverse: options.reverse))

case .list, .match, .add, .remove, .set:
    let traversal = Traversal(options: options, onError: report)

    traversal.forEachTarget { target in
        do {
            switch options.operation {
            case .list:
                try output.emitFile(target, tags: store.read(target.url))

            case .match(let query):
                let tags = try store.read(target.url)
                if tagsMatch(tags, query: query) {
                    try output.emitFile(target, tags: tags)
                }

            case .add(let tags):
                let change = try store.addChange(tags, to: target.url)
                if options.dryRun {
                    output.emitDryRun(operation: "add", target: target, change: change)
                } else {
                    try store.apply(change, to: target.url)
                }

            case .remove(let tags):
                let change = try store.removeChange(tags, from: target.url)
                if options.dryRun {
                    output.emitDryRun(operation: "remove", target: target, change: change)
                } else {
                    try store.apply(change, to: target.url)
                }

            case .set(let tags):
                let change = try store.setChange(tags, on: target.url)
                if options.dryRun {
                    output.emitDryRun(operation: "set", target: target, change: change)
                } else {
                    try store.apply(change, to: target.url)
                }

            case .copy, .usage:
                preconditionFailure("operation handled outside traversal")
            }
        } catch {
            report("\(target.displayPath): \(error.localizedDescription)")
        }
    }
}

do {
    try output.finish()
} catch {
    report("writing JSON output: \(error.localizedDescription)")
}

exit(hadError ? ExitCode.ioError : 0)
