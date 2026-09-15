import Foundation

struct ArchiveConverter {
    let document: ArchiveDocument
    let options: Options
    let output: Output

    func run() throws {
        var emitted = 0
        var tagged = 0

        for item in document.items {
            if options.taggedOnly && (item.tags == nil || item.tags!.isEmpty) { continue }
            try output.emitArchiveItem(item)
            emitted += 1
            if let tags = item.tags, !tags.isEmpty { tagged += 1 }
        }

        eprint("\(programName): converted \(tagged) tagged items (\(emitted) records)")
    }
}
