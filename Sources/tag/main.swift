import Foundation

let options = parseArguments()
let store = TagStore()
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
        guard try source.checkResourceIsReachable() else {
            fail("source is not reachable: \(sourcePath)", code: ExitCode.noInput)
        }
        guard try destination.checkResourceIsReachable() else {
            fail("destination is not reachable: \(destinationPath)", code: ExitCode.noInput)
        }
        try store.copy(from: source, to: destination)
    } catch {
        fail(
            "copying tags from \(sourcePath) to \(destinationPath): \(error.localizedDescription)",
            code: ExitCode.ioError
        )
    }

case .list, .add, .remove, .set:
    let traversal = Traversal(options: options, onError: report)
    let output = Output(options: options, colors: FinderColors(enabled: options.color))

    traversal.forEachTarget { target in
        do {
            switch options.operation {
            case .list:
                try output.emit(target, tags: store.read(target.url))
            case let .add(tags):
                try store.add(tags, to: target.url)
            case let .remove(tags):
                try store.remove(tags, from: target.url)
            case let .set(tags):
                try store.set(tags, on: target.url)
            case .copy:
                preconditionFailure("copy is handled before traversal")
            }
        } catch {
            report("\(target.displayPath): \(error.localizedDescription)")
        }
    }
}

exit(hadError ? ExitCode.ioError : 0)
