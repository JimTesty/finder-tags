import Foundation

let options = parseArguments()
let store = TagStore()
let output = Output(options: options, colors: FinderColors(enabled: options.color && !options.json && stdoutIsTerminal()))
var hadError = false

func report(_ message: String) {
    eprint("\(programName): \(message)")
    hadError = true
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
        let target = Target(url: destination, displayPath: destinationPath)
        if options.dryRun {
            output.emitChange(
                operation: "copy", target: target, change: change,
                sourcePath: sourcePath, dryRun: true
            )
        } else {
            try store.apply(change, to: destination)
            output.emitChange(
                operation: "copy", target: target, change: change,
                sourcePath: sourcePath, dryRun: false
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
            if tagsMatch(tags, query: query) {
                counter.add(tags)
            }
        } catch {
            report("\(target.url.path): \(error.localizedDescription)")
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
                    output.emitChange(operation: "add", target: target, change: change, dryRun: true)
                } else {
                    try store.apply(change, to: target.url)
                    output.emitChange(operation: "add", target: target, change: change, dryRun: false)
                }

            case .remove(let tags):
                let change = try store.removeChange(tags, from: target.url)
                if options.dryRun {
                    output.emitChange(operation: "remove", target: target, change: change, dryRun: true)
                } else {
                    try store.apply(change, to: target.url)
                    output.emitChange(operation: "remove", target: target, change: change, dryRun: false)
                }

            case .set(let tags):
                let change = try store.setChange(tags, on: target.url)
                if options.dryRun {
                    output.emitChange(operation: "set", target: target, change: change, dryRun: true)
                } else {
                    try store.apply(change, to: target.url)
                    output.emitChange(operation: "set", target: target, change: change, dryRun: false)
                }

            case .copy, .usage:
                preconditionFailure("operation handled outside traversal")
            }
        } catch {
            report("\(target.url.path): \(error.localizedDescription)")
        }
    }
}

do {
    try output.finish()
} catch {
    report("writing JSON output: \(error.localizedDescription)")
}

exit(hadError ? ExitCode.ioError : 0)
