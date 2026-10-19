import Foundation
#if canImport(Darwin)
import Darwin
#endif

let colorFixtureTags = [
    StoredTag(name: "Yellow", color: 5), StoredTag(name: "Purple", color: 3),
    StoredTag(name: "PurplePlus", color: 3), StoredTag(name: "Uncolored", color: 0),
    StoredTag(name: "Unexpected", color: 99)
]

func expect(_ condition: Bool, _ message: String = "assertion failed", file: StaticString = #file, line: UInt = #line) {
    precondition(condition, message, file: file, line: line)
}

struct TestContext {
    let work: URL
    let binary: URL

    func makeWorkDirectory(_ name: String) throws -> URL {
        let directory = work.appendingPathComponent(name, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func run(
        _ args: [String], status: Int32 = 0, executable: URL? = nil,
        input: String? = nil, inputData: Data? = nil,
        file: StaticString = #file, line: UInt = #line
    ) throws -> (out: String, err: String) {
        let process = Process()
        process.executableURL = executable ?? binary
        process.arguments = args
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        precondition(input == nil || inputData == nil, "specify input or inputData, not both")
        let stdinData = inputData ?? input.map { Data($0.utf8) }
        let stdin = stdinData.map { _ in Pipe() }
        if let stdin = stdin { process.standardInput = stdin }
        try process.run()
        if let input = stdinData, let stdin = stdin {
            stdin.fileHandleForWriting.write(input)
            stdin.fileHandleForWriting.closeFile()
        }
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        expect(process.terminationStatus == status,
            "CLI exit \(process.terminationStatus), expected \(status): \(escapedDisplayText(args.joined(separator: " ")))\n"
            + escapedDisplayText(String(decoding: err, as: UTF8.self)), file: file, line: line)
        return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
    }

    #if canImport(Darwin)
    func runInTerminal(_ args: [String], status: Int32 = 0) throws -> String {
        let log = work.appendingPathComponent("terminal-\(UUID().uuidString).log")
        let result = try run(["-q", log.path, binary.path] + args, status: status,
                             executable: URL(fileURLWithPath: "/usr/bin/script"), input: "")
        expect(result.err.isEmpty, result.err)
        return result.out
    }
    #endif
}

#if canImport(Darwin)
func captureOutput(_ body: () throws -> Void) throws -> (out: String, err: String) {
    fflush(nil)
    let stdout = Pipe(), stderr = Pipe()
    let savedOut = dup(STDOUT_FILENO), savedErr = dup(STDERR_FILENO)
    expect(savedOut >= 0 && savedErr >= 0)
    do {
        defer {
            fflush(nil)
            expect(dup2(savedOut, STDOUT_FILENO) >= 0 && dup2(savedErr, STDERR_FILENO) >= 0)
            close(savedOut)
            close(savedErr)
        }
        expect(dup2(stdout.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) >= 0)
        expect(dup2(stderr.fileHandleForWriting.fileDescriptor, STDERR_FILENO) >= 0)
        try body()
    }
    try stdout.fileHandleForWriting.close()
    try stderr.fileHandleForWriting.close()
    let out = try stdout.fileHandleForReading.readToEnd() ?? Data()
    let err = try stderr.fileHandleForReading.readToEnd() ?? Data()
    return (String(decoding: out, as: UTF8.self), String(decoding: err, as: UTF8.self))
}
#endif

func records(_ text: String) throws -> [[String: Any]] {
    try text.split(separator: "\n").map {
        try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
    }
}

func writeRecords(_ records: [[String: Any]], to url: URL) throws {
    let lines = try records.map {
        String(decoding: try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]), as: UTF8.self)
    }
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
}

func plist(_ value: Any) throws -> Data {
    try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
}

func taggedFile(_ url: URL, tags: [StoredTag]) throws {
    try Data().write(to: url)
    try FileTagMetadata.write(tags, to: url)
}

#if canImport(Darwin)
func writeRawTagMetadata(_ data: Data, to url: URL, followSymlinks: Bool = true) {
    let status = data.withUnsafeBytes {
        setxattr(url.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, $0.count, 0, followSymlinks ? 0 : XATTR_NOFOLLOW)
    }
    expect(status == 0, "cannot write raw metadata fixture: \(url.path)")
}

func readRawTagMetadata(_ url: URL, followSymlinks: Bool = true) -> Data {
    let attribute = "com.apple.metadata:_kMDItemUserTags"
    let flags: Int32 = followSymlinks ? 0 : XATTR_NOFOLLOW
    let size = getxattr(url.path, attribute, nil, 0, 0, flags)
    expect(size >= 0, "cannot read raw metadata fixture: \(url.path)")
    var data = Data(count: size)
    let count = data.withUnsafeMutableBytes {
        getxattr(url.path, attribute, $0.baseAddress, $0.count, 0, flags)
    }
    expect(count == size, "raw metadata fixture changed during read: \(url.path)")
    return data
}
#endif

func archiveItem(_ path: String, tags: [StoredTag] = [StoredTag(name: "Changed", color: 3)]) -> [String: Any] {
    ["type": "item", "kind": "file", "path": path, "tags": tags.map { $0.name },
     "colors": tags.map { $0.color.map { $0 as Any } ?? NSNull() }]
}

func writeTestArchive(
    _ items: [[String: Any]], root: URL, to url: URL, headerPatch: [String: Any] = [:]
) throws {
    var header: [String: Any] = [
        "type": "header", "format": "jsonl", "version": 3, "purpose": "export",
        "followSymlinks": false, "fileInfo": false, "taggedOnly": false,
        "exclude": [], "tagColors": []
    ]
    for (key, value) in headerPatch { header[key] = value }
    let summary: [String: Any] = [
        "type": "summary", "operation": "export", "visited": items.count,
        "emitted": items.count, "tagged": items.count, "errors": 0, "warnings": 0
    ]
    try writeRecords([header, ["type": "root", "path": root.path]] + items + [summary], to: url)
}
