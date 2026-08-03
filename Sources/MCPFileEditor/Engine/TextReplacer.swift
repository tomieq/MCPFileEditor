import Foundation

/// Replaces an exact text fragment in one project-relative UTF-8 file.
struct TextReplacer {
    private let rootURL: URL
    private let fileManager = FileManager.default

    init(rootURL: URL) {
        self.rootURL = rootURL.resolvingSymlinksInPath().standardizedFileURL
    }

    func replace(filepath: String,
                 find: String,
                 replacement: String,
                 expectedMatches: Int,
                 replaceAll: Bool,
                 dryRun: Bool) throws -> TextReplacementResult {
        guard find.isEmpty.not else {
            throw TextReplacementError.invalidArgument("find must not be empty")
        }
        guard expectedMatches > 0 else {
            throw TextReplacementError.invalidArgument("expectedMatches must be at least 1")
        }
        guard replaceAll || expectedMatches == 1 else {
            throw TextReplacementError.invalidArgument("expectedMatches must be 1 unless replaceAll is true")
        }

        let url = try projectURL(for: filepath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw TextReplacementError.fileNotFound(filepath)
        }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw TextReplacementError.invalidUTF8(filepath)
        }

        let matchCount = occurrences(of: find, in: content)
        guard matchCount == expectedMatches else {
            throw TextReplacementError.matchCountMismatch(expected: expectedMatches, found: matchCount, filepath: filepath)
        }

        let replacements = replaceAll ? matchCount : 1
        let updatedContent: String
        if replaceAll {
            updatedContent = content.replacingOccurrences(of: find, with: replacement)
        } else if let range = content.range(of: find) {
            updatedContent = content.replacingCharacters(in: range, with: replacement)
        } else {
            throw TextReplacementError.matchCountMismatch(expected: expectedMatches, found: 0, filepath: filepath)
        }

        if dryRun.not {
            try updatedContent.write(to: url, atomically: true, encoding: .utf8)
        }

        return TextReplacementResult(filepath: filepath,
                                     matches: matchCount,
                                     replacements: replacements,
                                     replaceAll: replaceAll,
                                     dryRun: dryRun)
    }

    func replaceAll(targets: [TextReplacementTarget],
                    find: String,
                    replacement: String,
                    expectedMatches: Int,
                    dryRun: Bool) throws -> TextReplacementBatchResult {
        guard find.isEmpty.not else {
            throw TextReplacementError.invalidArgument("find must not be empty")
        }
        guard expectedMatches > 0 else {
            throw TextReplacementError.invalidArgument("expectedMatches must be at least 1")
        }
        guard targets.isEmpty.not else {
            throw TextReplacementError.matchCountMismatch(expected: expectedMatches, found: 0, filepath: "the cached project files")
        }
        guard Set(targets.map(\.filepath)).count == targets.count else {
            throw TextReplacementError.invalidArgument("Cached replacement targets contain duplicate paths")
        }

        let cachedMatches = targets.reduce(0) { $0 + $1.expectedMatches }
        guard cachedMatches == expectedMatches else {
            throw TextReplacementError.matchCountMismatch(expected: expectedMatches, found: cachedMatches, filepath: "the cached project files")
        }

        let changes = try targets.map { target -> PreparedTextReplacement in
            let url = try projectURL(for: target.filepath)
            guard fileManager.fileExists(atPath: url.path) else {
                throw TextReplacementError.fileNotFound(target.filepath)
            }
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                throw TextReplacementError.invalidUTF8(target.filepath)
            }
            let matchCount = occurrences(of: find, in: content)
            guard matchCount == target.expectedMatches else {
                throw TextReplacementError.matchCountMismatch(expected: target.expectedMatches, found: matchCount, filepath: target.filepath)
            }
            return PreparedTextReplacement(filepath: target.filepath,
                                           url: url,
                                           updatedContent: content.replacingOccurrences(of: find, with: replacement),
                                           matches: matchCount)
        }

        if dryRun.not {
            for change in changes {
                try change.updatedContent.write(to: change.url, atomically: true, encoding: .utf8)
            }
        }

        return TextReplacementBatchResult(files: changes.map {
            TextReplacementResult(filepath: $0.filepath,
                                  matches: $0.matches,
                                  replacements: $0.matches,
                                  replaceAll: true,
                                  dryRun: dryRun)
        })
    }
}

private extension TextReplacer {
    func projectURL(for filepath: String) throws -> URL {
        guard filepath.isEmpty.not, filepath.hasPrefix("/").not, filepath.split(separator: "/").contains("..").not else {
            throw TextReplacementError.invalidArgument("filepath must be a non-empty project-relative path")
        }

        let candidate = rootURL.appendingPathComponent(filepath).resolvingSymlinksInPath().standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPath) else {
            throw TextReplacementError.invalidArgument("filepath escapes the configured project")
        }
        return candidate
    }

    func occurrences(of find: String, in content: String) -> Int {
        var count = 0
        var searchStart = content.startIndex
        while let range = content.range(of: find, range: searchStart..<content.endIndex) {
            count += 1
            searchStart = range.upperBound
        }
        return count
    }

    struct PreparedTextReplacement {
        let filepath: String
        let url: URL
        let updatedContent: String
        let matches: Int
    }
}

struct TextReplacementTarget {
    let filepath: String
    let expectedMatches: Int
}

struct TextReplacementResult: Encodable {
    let filepath: String
    let matches: Int
    let replacements: Int
    let replaceAll: Bool
    let dryRun: Bool

    var message: String {
        let action = dryRun ? "Validated" : "Replaced"
        return "\(action) \(replacements) occurrence(s) in \(filepath)"
    }

    var structuredMessage: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "{}"
    }
}

struct TextReplacementBatchResult: Encodable {
    let files: [TextReplacementResult]

    var message: String {
        let replacements = files.reduce(0) { $0 + $1.replacements }
        return "Replaced \(replacements) occurrence(s) across \(files.count) file(s)"
    }

    var structuredMessage: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(data: (try? encoder.encode(self)) ?? Data(), encoding: .utf8) ?? "{}"
    }
}

private enum TextReplacementError: LocalizedError {
    case invalidArgument(String)
    case fileNotFound(String)
    case invalidUTF8(String)
    case matchCountMismatch(expected: Int, found: Int, filepath: String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message):
            return message
        case .fileNotFound(let filepath):
            return "File not found at \(filepath)"
        case .invalidUTF8(let filepath):
            return "File is not valid UTF-8: \(filepath)"
        case let .matchCountMismatch(expected, found, filepath):
            return "Expected \(expected) match(es) in \(filepath), but found \(found). Refine find text or set expectedMatches to the verified count."
        }
    }
}

private extension Bool {
    var not: Bool { !self }
}
