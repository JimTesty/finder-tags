import Foundation

@main
enum RegressionTests {
    static func main() throws {
        let context = TestContext(
            work: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
            binary: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        try MetadataTests.run(context)
        print("Metadata tests passed")
        try FinderColorTests.run(context)
        print("Finder color tests passed")
        try TextDisplayTests.run(context)
        print("Text display tests passed")
        #if canImport(Darwin)
        try RepairTests.run(context)
        print("Repair tests passed")
        try ArchiveTests.run(context)
        print("Archive tests passed")
        try UndoTests.run(context)
        print("Undo tests passed")
        #endif
    }
}
