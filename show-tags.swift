#!/usr/bin/env swift

import Foundation

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func usage() -> Never {
    fail("Usage: show-tags.swift FILE", code: 64)
}

let args = CommandLine.arguments

guard args.count == 2 else { usage() }

let path = NSString(string: args[1]).expandingTildeInPath
let url = URL(fileURLWithPath: path)

var isDirectory: ObjCBool = false
guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
    fail("show-tags: file does not exist: \(args[1])", code: 66)
}

do {
    let values = try url.resourceValues(forKeys: [.tagNamesKey])
    let tags = values.tagNames ?? []

    for tag in tags {
        print(tag)
    }
} catch {
    fail("show-tags: unable to read tags from \(args[1]): \(error)", code: 74)
}
