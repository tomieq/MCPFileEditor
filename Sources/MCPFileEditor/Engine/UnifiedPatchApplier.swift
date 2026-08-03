import Foundation

/// Applies standard unified diffs without relying on Git or a shell command.
struct UnifiedPatchApplier {
    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    func apply(_ patch: String, dryRun: Bool) throws -> UnifiedPatchResult {
        guard patch.isEmpty.not, patch.count <= 1_000_000, patch.contains("\0").not else {
            throw UnifiedPatchError.invalidPatch("patch must be between 1 and 1,000,000 characters and contain no NUL bytes")
        }

        let patches = try parse(patch)
        var changes: [PreparedChange] = []
        var reservedPaths = Set<String>()

        for filePatch in patches {
            let change = try prepare(filePatch)
            for path in Set([change.sourceURL?.path, change.destinationURL?.path].compactMap({ $0 })) {
                guard reservedPaths.insert(path).inserted else {
                    throw UnifiedPatchError.invalidPatch("The patch modifies \(path) more than once")
                }
            }
            changes.append(change)
        }

        if dryRun.not {
            for change in changes {
                try commit(change)
            }
        }

        return UnifiedPatchResult(
            filesChanged: changes.count,
            dryRun: dryRun,
            paths: changes.map(\.summary),
            report: PatchDryRunReport(files: changes.map { change in
                PatchDryRunFile(path: relativePath(change.destinationURL ?? change.sourceURL ?? rootURL),
                                operation: operation(sourceURL: change.sourceURL, destinationURL: change.destinationURL),
                                additions: change.additions,
                                removals: change.removals,
                                hunks: change.hunkMatches.map {
                                    PatchDryRunHunk(index: $0.index,
                                                    matchedLine: $0.position + 1,
                                                    matchingStrategy: $0.strategy.rawValue)
                                })
            })
        )
    }
}

private extension UnifiedPatchApplier {
    struct FilePatch {
        let oldPath: String?
        let newPath: String?
        let hunks: [Hunk]
    }

    struct Hunk {
        let oldStart: Int?
        let oldCount: Int
        let newCount: Int
        let lines: [HunkLine]
    }

    struct HunkLine {
        enum Kind: Character {
            case context = " "
            case removal = "-"
            case addition = "+"
        }

        let kind: Kind
        let content: String
        let hasTrailingNewline: Bool
    }

    struct PreparedChange {
        let sourceURL: URL?
        let destinationURL: URL?
        let content: String?
        let summary: String
        let hunkMatches: [HunkMatch]
        let additions: Int
        let removals: Int
    }

    struct HunkMatch {
        enum Strategy: String {
            case headerLine = "header-line"
            case exactContext = "exact-context"
            case whitespaceInsensitive = "whitespace-insensitive"
        }

        let index: Int
        let position: Int
        let strategy: Strategy
    }

    func parse(_ patch: String) throws -> [FilePatch] {
        var lines = patch.components(separatedBy: "\n")
        if patch.hasSuffix("\n") {
            lines.removeLast()
        }
        lines = lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }

        var index = 0
        var files: [FilePatch] = []
        while index < lines.count {
            guard lines[index].hasPrefix("--- ") else {
                index += 1
                continue
            }

            let oldPath = try patchPath(from: lines[index], prefix: "--- ")
            index += 1
            guard index < lines.count, lines[index].hasPrefix("+++ ") else {
                throw UnifiedPatchError.invalidPatch("Missing +++ header after \(oldPath ?? "/dev/null")")
            }
            let newPath = try patchPath(from: lines[index], prefix: "+++ ")
            index += 1
            guard oldPath != nil || newPath != nil else {
                throw UnifiedPatchError.invalidPatch("A file patch cannot use /dev/null for both paths")
            }

            var hunks: [Hunk] = []
            while index < lines.count, lines[index].hasPrefix("@@") {
                let header = try hunkHeader(lines[index])
                index += 1
                var hunkLines: [HunkLine] = []

                while index < lines.count {
                    let line = lines[index]
                    if line.hasPrefix("--- ") || line.hasPrefix("diff --git ") {
                        break
                    }
                    guard let prefix = line.first, let kind = HunkLine.Kind(rawValue: prefix) else {
                        if line == "\\ No newline at end of file", var last = hunkLines.popLast() {
                            last = HunkLine(kind: last.kind, content: last.content, hasTrailingNewline: false)
                            hunkLines.append(last)
                            index += 1
                            continue
                        }
                        break
                    }
                    hunkLines.append(HunkLine(kind: kind, content: String(line.dropFirst()), hasTrailingNewline: true))
                    index += 1
                }

                let oldLineCount = hunkLines.filter { $0.kind != .addition }.count
                let newLineCount = hunkLines.filter { $0.kind != .removal }.count
                if let oldCount = header.oldCount, let newCount = header.newCount,
                   oldLineCount != oldCount || newLineCount != newCount {
                    throw UnifiedPatchError.invalidPatch("Hunk header count mismatch: header declares \(oldCount) old and \(newCount) new line(s), but its body contains \(oldLineCount) old and \(newLineCount) new line(s). Use @@ -start,oldCount +start,newCount @@.")
                }
                hunks.append(Hunk(oldStart: header.oldStart,
                                  oldCount: header.oldCount ?? oldLineCount,
                                  newCount: header.newCount ?? newLineCount,
                                  lines: hunkLines))
            }

            guard hunks.isEmpty.not else {
                throw UnifiedPatchError.invalidPatch("The patch for \(newPath ?? oldPath ?? "file") contains no hunks")
            }
            files.append(FilePatch(oldPath: oldPath, newPath: newPath, hunks: hunks))
        }

        guard files.isEmpty.not else {
            throw UnifiedPatchError.invalidPatch("Expected a standard unified diff with --- and +++ file headers")
        }
        return files
    }

    func patchPath(from line: String, prefix: String) throws -> String? {
        let value = String(line.dropFirst(prefix.count))
            .split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false).first
            .map(String.init) ?? ""
        guard value.isEmpty.not else {
            throw UnifiedPatchError.invalidPatch("The \(prefix.trimmingCharacters(in: .whitespaces)) header has no path")
        }
        guard value != "/dev/null" else { return nil }

        let path = value.hasPrefix("a/") || value.hasPrefix("b/") ? String(value.dropFirst(2)) : value
        guard path.isEmpty.not, path.hasPrefix("/").not, path.split(separator: "/").contains("..").not else {
            throw UnifiedPatchError.invalidPatch("Patch path must be a project-relative path: \(value)")
        }
        return path
    }

    func hunkHeader(_ line: String) throws -> (oldStart: Int?, oldCount: Int?, newCount: Int?) {
        guard line == "@@" || line.hasPrefix("@@ ") else {
            throw UnifiedPatchError.invalidPatch("Invalid hunk header: \(line). Expected @@ -oldStart,oldCount +newStart,newCount @@.")
        }
        guard line != "@@" else {
            return (nil, nil, nil)
        }
        let parts = line.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "@@", parts[1].first == "-", parts[2].first == "+" else {
            throw UnifiedPatchError.invalidPatch("Invalid hunk header: \(line). Expected @@ -oldStart,oldCount +newStart,newCount @@, or @@ for context-based matching.")
        }
        let oldRange = try lineRange(String(parts[1].dropFirst()))
        let newRange = try lineRange(String(parts[2].dropFirst()))
        return (oldRange.start, oldRange.count, newRange.count)
    }

    func lineRange(_ value: String) throws -> (start: Int, count: Int) {
        let parts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let start = Int(parts[0]), start >= 0 else {
            throw UnifiedPatchError.invalidPatch("Invalid hunk range: \(value)")
        }
        let count = parts.count == 2 ? Int(parts[1]) : 1
        guard let count, count >= 0 else {
            throw UnifiedPatchError.invalidPatch("Invalid hunk range: \(value)")
        }
        return (start, count)
    }

    func prepare(_ patch: FilePatch) throws -> PreparedChange {
        let sourceURL = try patch.oldPath.map(projectURL(for:))
        let destinationURL = try patch.newPath.map(projectURL(for:))

        if let sourceURL, fileManager.fileExists(atPath: sourceURL.path).not {
            throw UnifiedPatchError.applyFailed("Source file does not exist: \(relativePath(sourceURL))")
        }
        if let destinationURL, destinationURL != sourceURL, fileManager.fileExists(atPath: destinationURL.path) {
            throw UnifiedPatchError.applyFailed("Destination file already exists: \(relativePath(destinationURL))")
        }

        let original = try sourceURL.map(readFile) ?? TextFile(lines: [], lineEnding: "\n", hasTrailingNewline: true)
        let application = try applying(patch.hunks, to: original)
        let content = destinationURL.map { _ in application.file.serialized }
        return PreparedChange(sourceURL: sourceURL,
                              destinationURL: destinationURL,
                              content: content,
                              summary: summary(sourceURL: sourceURL, destinationURL: destinationURL),
                              hunkMatches: application.hunkMatches,
                              additions: patch.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .addition }.count },
                              removals: patch.hunks.reduce(0) { $0 + $1.lines.filter { $0.kind == .removal }.count })
    }

    func projectURL(for path: String) throws -> URL {
        let candidate = rootURL.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        let root = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(root) else {
            throw UnifiedPatchError.invalidPatch("Patch path escapes the configured project: \(path)")
        }
        return candidate
    }

    func readFile(_ url: URL) throws -> TextFile {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw UnifiedPatchError.applyFailed("Source file is not valid UTF-8: \(relativePath(url))")
        }
        let lineEnding = content.contains("\r\n") ? "\r\n" : "\n"
        var lines = content.components(separatedBy: lineEnding)
        let hasTrailingNewline = content.hasSuffix(lineEnding)
        if hasTrailingNewline {
            lines.removeLast()
        }
        return TextFile(lines: lines, lineEnding: lineEnding, hasTrailingNewline: hasTrailingNewline)
    }

    func applying(_ hunks: [Hunk], to original: TextFile) throws -> AppliedTextFile {
        var lines = original.lines
        var trailingNewline = original.hasTrailingNewline
        var offset = 0
        var hunkMatches: [HunkMatch] = []

        for (hunkIndex, hunk) in hunks.enumerated() {
            let hunkMatch = try position(for: hunk, in: lines, offset: offset, hunkIndex: hunkIndex + 1)
            hunkMatches.append(hunkMatch)
            var cursor = hunkMatch.position
            var additions: [String] = []

            for line in hunk.lines {
                switch line.kind {
                case .context:
                    try match(line.content, at: cursor, in: lines, strategy: hunkMatch.strategy)
                    cursor += 1
                    additions.append(line.content)
                case .removal:
                    try match(line.content, at: cursor, in: lines, strategy: hunkMatch.strategy)
                    cursor += 1
                case .addition:
                    additions.append(line.content)
                }
            }

            lines.replaceSubrange(hunkMatch.position..<cursor, with: additions)
            offset += hunk.newCount - hunk.oldCount
            if hunk.lines.last?.hasTrailingNewline == false,
               hunk.lines.last?.kind != .removal {
                trailingNewline = false
            }
        }
        return AppliedTextFile(file: TextFile(lines: lines, lineEnding: original.lineEnding, hasTrailingNewline: trailingNewline),
                               hunkMatches: hunkMatches)
    }

    func position(for hunk: Hunk, in lines: [String], offset: Int, hunkIndex: Int) throws -> HunkMatch {
        let expected = hunk.lines
            .filter { $0.kind != .addition }
            .map(\.content)

        if let oldStart = hunk.oldStart {
            let declaredPosition = oldStart == 0 ? 0 : oldStart - 1 + offset
            if (0...lines.count).contains(declaredPosition), matches(expected, at: declaredPosition, in: lines) {
                return HunkMatch(index: hunkIndex, position: declaredPosition, strategy: .headerLine)
            }
            if (0...lines.count).contains(declaredPosition), matchesIgnoringWhitespace(expected, at: declaredPosition, in: lines) {
                return HunkMatch(index: hunkIndex, position: declaredPosition, strategy: .whitespaceInsensitive)
            }
        }

        guard expected.isEmpty.not else {
            throw UnifiedPatchError.applyFailed("Hunk \(hunkIndex) has no source context. Add an explicit line range for an addition-only hunk, for example @@ -0,0 +1,1 @@.")
        }

        let exactPositions = matchingPositions(for: expected, in: lines)
        if let position = try preferredPosition(from: exactPositions, declaredStart: hunk.oldStart.map { $0 - 1 + offset }, hunkIndex: hunkIndex) {
            return HunkMatch(index: hunkIndex, position: position, strategy: .exactContext)
        }

        let whitespaceInsensitivePositions = matchingPositions(for: expected, in: lines, ignoringWhitespace: true)
        if let position = try preferredPosition(from: whitespaceInsensitivePositions, declaredStart: hunk.oldStart.map { $0 - 1 + offset }, hunkIndex: hunkIndex) {
            return HunkMatch(index: hunkIndex, position: position, strategy: .whitespaceInsensitive)
        }

        let expectedLine = expected[0]
        if let oldStart = hunk.oldStart {
            let lineNumber = max(1, oldStart + offset)
            let actualLine = (0..<lines.count).contains(lineNumber - 1) ? lines[lineNumber - 1] : "<end of file>"
            throw UnifiedPatchError.applyFailed("Hunk \(hunkIndex) failed near line \(lineNumber): expected \(quoted(expectedLine)), found \(quoted(actualLine)). Check surrounding whitespace/context or update the hunk range.")
        }
        throw UnifiedPatchError.applyFailed("Hunk \(hunkIndex) could not find its source context. Expected to find \(quoted(expectedLine)).")
    }

    func preferredPosition(from positions: [Int], declaredStart: Int?, hunkIndex: Int) throws -> Int? {
        guard positions.isEmpty.not else { return nil }
        guard positions.count > 1 else { return positions[0] }
        guard let declaredStart else {
            let candidates = positions.prefix(3).map { String($0 + 1) }.joined(separator: ", ")
            throw UnifiedPatchError.applyFailed("Hunk \(hunkIndex) matches multiple locations (lines \(candidates)). Add more unchanged context or an explicit hunk range.")
        }

        let sorted = positions.sorted { abs($0 - declaredStart) < abs($1 - declaredStart) }
        if sorted.count == 1 || abs(sorted[0] - declaredStart) < abs(sorted[1] - declaredStart) {
            return sorted[0]
        }
        let candidates = sorted.prefix(3).map { String($0 + 1) }.joined(separator: ", ")
        throw UnifiedPatchError.applyFailed("Hunk \(hunkIndex) has equally close matches at lines \(candidates). Add more unchanged context or correct its line range.")
    }

    func matchingPositions(for expected: [String], in lines: [String], ignoringWhitespace: Bool = false) -> [Int] {
        guard expected.count <= lines.count else { return [] }
        return (0...(lines.count - expected.count)).filter {
            ignoringWhitespace ? matchesIgnoringWhitespace(expected, at: $0, in: lines) : matches(expected, at: $0, in: lines)
        }
    }

    func matches(_ expected: [String], at index: Int, in lines: [String]) -> Bool {
        guard index >= 0, index + expected.count <= lines.count else { return false }
        return expected.enumerated().allSatisfy { offset, line in lines[index + offset] == line }
    }

    func matchesIgnoringWhitespace(_ expected: [String], at index: Int, in lines: [String]) -> Bool {
        guard index >= 0, index + expected.count <= lines.count else { return false }
        return expected.enumerated().allSatisfy { offset, line in
            normalizedWhitespace(line) == normalizedWhitespace(lines[index + offset])
        }
    }

    func quoted(_ line: String) -> String {
        "'\(line.isEmpty ? "<empty line>" : line)'"
    }

    func normalizedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func match(_ expected: String, at index: Int, in lines: [String], strategy: HunkMatch.Strategy) throws {
        guard index < lines.count else {
            throw UnifiedPatchError.applyFailed("Hunk extends past the end of the source file")
        }
        let matches = strategy == .whitespaceInsensitive
            ? normalizedWhitespace(lines[index]) == normalizedWhitespace(expected)
            : lines[index] == expected
        guard matches else {
            throw UnifiedPatchError.applyFailed("Hunk does not match source file at line \(index + 1): expected \(quoted(expected)), found \(quoted(lines[index])).")
        }
    }

    func commit(_ change: PreparedChange) throws {
        if let destinationURL = change.destinationURL, let content = change.content {
            try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: destinationURL, atomically: true, encoding: .utf8)
        }
        if let sourceURL = change.sourceURL, sourceURL != change.destinationURL {
            try fileManager.removeItem(at: sourceURL)
        }
    }

    func summary(sourceURL: URL?, destinationURL: URL?) -> String {
        let operation = operation(sourceURL: sourceURL, destinationURL: destinationURL)
        switch (sourceURL, destinationURL) {
        case let (_, .some(destination)) where operation == "updated":
            return "updated \(relativePath(destination))"
        case let (.some(source), .some(destination)):
            return "moved \(relativePath(source)) to \(relativePath(destination))"
        case let (.none, .some(destination)):
            return "created \(relativePath(destination))"
        case let (.some(source), .none):
            return "deleted \(relativePath(source))"
        case (.none, .none):
            return "no file changes"
        }
    }

    func operation(sourceURL: URL?, destinationURL: URL?) -> String {
        switch (sourceURL, destinationURL) {
        case let (.some(source), .some(destination)) where source == destination: return "updated"
        case (.some, .some): return "moved"
        case (.none, .some): return "created"
        case (.some, .none): return "deleted"
        case (.none, .none): return "none"
        }
    }

    func relativePath(_ url: URL) -> String {
        String(url.path.dropFirst(rootURL.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    struct TextFile {
        var lines: [String]
        let lineEnding: String
        var hasTrailingNewline: Bool

        var serialized: String {
            lines.joined(separator: lineEnding) + (hasTrailingNewline ? lineEnding : "")
        }
    }

    struct AppliedTextFile {
        let file: TextFile
        let hunkMatches: [HunkMatch]
    }
}

struct UnifiedPatchResult {
    let filesChanged: Int
    let dryRun: Bool
    let paths: [String]
    let report: PatchDryRunReport

    var message: String {
        let prefix = dryRun ? "Patch validated without changes" : "Patch applied"
        return "\(prefix) to \(filesChanged) file(s):\n\(paths.joined(separator: "\n"))"
    }

    var structuredMessage: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(data: (try? encoder.encode(report)) ?? Data(), encoding: .utf8) ?? "{}"
    }
}

struct PatchDryRunReport: Encodable {
    let files: [PatchDryRunFile]
}

struct PatchDryRunFile: Encodable {
    let path: String
    let operation: String
    let additions: Int
    let removals: Int
    let hunks: [PatchDryRunHunk]
}

struct PatchDryRunHunk: Encodable {
    let index: Int
    let matchedLine: Int
    let matchingStrategy: String
}

private enum UnifiedPatchError: LocalizedError {
    case invalidPatch(String)
    case applyFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidPatch(let message), .applyFailed(let message):
            return message
        }
    }
}

private extension Bool {
    var not: Bool { !self }
}
