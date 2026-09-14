#!/usr/bin/env swift

import Foundation

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func usage() -> Never {
    fail("Usage: copy-tags.swift SOURCE DESTINATION", code: 64)
}

let args = CommandLine.arguments
guard args.count == 3 else { usage() }

let sourcePath = NSString(string: args[1]).expandingTildeInPath
let destinationPath = NSString(string: args[2]).expandingTildeInPath
let sourceURL = URL(fileURLWithPath: sourcePath)
let destinationURL = URL(fileURLWithPath: destinationPath)
let fm = FileManager.default

guard fm.fileExists(atPath: sourcePath) else {
    fail("copy-tags: source does not exist: \(args[1])", code: 66)
}
guard fm.fileExists(atPath: destinationPath) else {
    fail("copy-tags: destination does not exist: \(args[2])", code: 66)
}

do {
    let tags = try sourceURL.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    // Destructive by design. Array order is copied unchanged.
    try (destinationURL as NSURL).setResourceValue(tags, forKey: .tagNamesKey)
} catch {
    fail("copy-tags: failed to copy tags from \(args[1]) to \(args[2]): \(error)", code: 74)
}
