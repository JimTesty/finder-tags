import Foundation

@main
enum RegressionTests {
    static func main() throws {
        let context = TestContext(
            work: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
            binary: URL(fileURLWithPath: CommandLine.arguments[2])
        )
        try HelpTests.run(context)
        print("Help tests passed")
        try StdinTests.run(context)
        print("Stdin tests passed")
        try VerbosityTests.run(context)
        print("Verbosity tests passed")
        try MetadataTests.run(context)
        print("Metadata tests passed")
        try FileInfoTests.run(context)
        print("File info tests passed")
        try UnicodeTests.run(context)
        print("Unicode tests passed")
        try FinderColorTests.run(context)
        print("Finder color tests passed")
        try TextDisplayTests.run(context)
        print("Text display tests passed")
        #if canImport(Darwin)
        try InspectionTests.run(context)
        print("Inspection tests passed")
        try RepairTests.run(context)
        print("Repair tests passed")
        try ArchiveTests.run(context)
        print("Archive tests passed")
        try UndoTests.run(context)
        print("Undo tests passed")
        #endif
    }
}
