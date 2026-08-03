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

    func testAppliesRangeLessContextPatch() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "before\nold value\nafter\n".write(to: existing, atomically: true, encoding: .utf8)

        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@
        -old value
        +new value
        """

        _ = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: false)

        XCTAssertEqual(try String(contentsOf: existing), "before\nnew value\nafter\n")
    }

    func testFindsAUniqueHunkWhenItsLineRangeIsOffset() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "inserted\nbefore\nold value\nafter\n".write(to: existing, atomically: true, encoding: .utf8)

        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -2,3 +2,3 @@
         before
        -old value
        +new value
         after
        """

        _ = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: false)

        XCTAssertEqual(try String(contentsOf: existing), "inserted\nbefore\nnew value\nafter\n")
    }

    func testReportsHeaderCountMismatchesClearly() throws {
        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -1,2 +1,2 @@
        -old value
        +new value
        """

        XCTAssertThrowsError(try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: true)) {
            XCTAssertTrue($0.localizedDescription.contains("Hunk header count mismatch"))
        }
    }

    func testAppliesWhitespaceInsensitiveContext() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "\told value\n".write(to: existing, atomically: true, encoding: .utf8)
        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -1 +1 @@
        -    old value
        +new value
        """

        _ = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: false)

        XCTAssertEqual(try String(contentsOf: existing), "new value\n")
    }

    func testDryRunReturnsStructuredMatchMetadata() throws {
        let existing = directory.appendingPathComponent("example.txt")
        try "old value\n".write(to: existing, atomically: true, encoding: .utf8)
        let patch = """
        --- a/example.txt
        +++ b/example.txt
        @@ -1 +1 @@
        -old value
        +new value
        """

        let result = try UnifiedPatchApplier(rootURL: directory).apply(patch, dryRun: true)
        let json = try JSONSerialization.jsonObject(with: try XCTUnwrap(result.structuredMessage.data(using: .utf8))) as? [String: Any]
        let files = try XCTUnwrap(json?["files"] as? [[String: Any]])
        let file = try XCTUnwrap(files.first)
        let hunks = try XCTUnwrap(file["hunks"] as? [[String: Any]])

        XCTAssertEqual(file["path"] as? String, "example.txt")
        XCTAssertEqual(file["additions"] as? Int, 1)
        XCTAssertEqual(file["removals"] as? Int, 1)
        XCTAssertEqual(hunks.first?["matchedLine"] as? Int, 1)
        XCTAssertEqual(hunks.first?["matchingStrategy"] as? String, "header-line")
        XCTAssertEqual(try String(contentsOf: existing), "old value\n")
    }
}
