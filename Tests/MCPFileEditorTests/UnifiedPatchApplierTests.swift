import Foundation
import XCTest
@testable import MCPFileEditor

final class UnifiedPatchApplierTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testAppliesUpdateAndCreatesNestedFile() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "one\ntwo\n".write(to: existing, atomically: true, encoding: .utf8)

        let patch = """
        diff --git a/example.txt b/example.txt
        --- a/example.txt
        +++ b/example.txt
        @@ -1,2 +1,3 @@
         one
        -two
        +two changed
        +three
        --- /dev/null
        +++ b/nested/new.txt
        @@ -0,0 +1 @@
        +created
        """

        let result = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: false)

        XCTAssertEqual(result.filesChanged, 2)
        XCTAssertEqual(try String(contentsOf: existing), "one\ntwo changed\nthree\n")
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("nested/new.txt")), "created\n")
    }

    func testDryRunAndMismatchedHunkDoNotWrite() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "one\n".write(to: existing, atomically: true, encoding: .utf8)
        let applier = UnifiedPatchApplier(rootURL: directory)

        let validPatch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -1 +1 @@
        -one
        +two
        """
        _ = try applier.apply(validPatch, dryRun: true)
        XCTAssertEqual(try String(contentsOf: existing), "one\n")

        let invalidPatch = validPatch.replacingOccurrences(of: "-one", with: "-missing")
        XCTAssertThrowsError(try applier.apply(invalidPatch, dryRun: false))
        XCTAssertEqual(try String(contentsOf: existing), "one\n")
    }
}
