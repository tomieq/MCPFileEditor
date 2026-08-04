//
//  FileCache.swift
//  MCPServer
//
//  Created by: tomieq on 16/02/2026
//
import Foundation
import Logger
import SwiftExtensions

struct SearchResult: Codable {
    let filepath: String
    let line: Int
    let lineContent: String
    let contextBefore: [String]
    let contextAfter: [String]
}

struct SearchOptions {
    let query: String
    let useRegex: Bool
    let caseSensitive: Bool
    let includeGlobs: [String]
    let excludeGlobs: [String]
    let limit: Int
    let contextLines: Int
}

struct SearchMatches {
    let results: [SearchResult]
    let truncated: Bool
}

enum SearchError: LocalizedError {
    case invalidQuery(String)

    var errorDescription: String? {
        switch self {
        case .invalidQuery(let message): return message
        }
    }
}

class FileCache {
    private let folder: Folder
    private var cache: [String: String] = [:]
    private let logger = Logger(FileCache.self)

    init(folder: Folder) {
        self.folder = folder
        for virtualPath in folder.files() {
            load(virtualPath: virtualPath)
        }
    }

    func matching(_ options: SearchOptions) throws -> SearchMatches {
        guard options.query.isEmpty.not, options.query.count <= 4_096 else {
            throw SearchError.invalidQuery("search must contain 1 through 4,096 characters")
        }
        guard (1...1_000).contains(options.limit) else {
            throw SearchError.invalidQuery("limit must be between 1 and 1,000")
        }
        guard (0...20).contains(options.contextLines) else {
            throw SearchError.invalidQuery("contextLines must be between 0 and 20")
        }

        let expression: NSRegularExpression?
        if options.useRegex {
            do {
                expression = try NSRegularExpression(
                    pattern: options.query,
                    options: options.caseSensitive ? [] : [.caseInsensitive]
                )
            } catch {
                throw SearchError.invalidQuery("Invalid regular expression: \(error.localizedDescription)")
            }
        } else {
            expression = nil
        }

        var results: [SearchResult] = []
        for (virtualPath, content) in cache.sorted(by: { $0.key < $1.key }) where matchesPath(virtualPath, options: options) {
            let lines = content.components(separatedBy: "\n")
            for (number, line) in lines.enumerated() {
                if lineMatches(line, options: options, expression: expression) {
                    results.append(SearchResult(filepath: virtualPath,
                                                line: number.incremented,
                                                lineContent: line,
                                                contextBefore: Array(lines[max(0, number - options.contextLines)..<number]),
                                                contextAfter: Array(lines[(number + 1)..<min(lines.count, number + options.contextLines + 1)])))
                    if results.count > options.limit {
                        return SearchMatches(results: Array(results.dropLast()), truncated: true)
                    }
                }
            }
        }
        return SearchMatches(results: results, truncated: false)
    }

    func replacementTargets(_ text: String) -> [TextReplacementTarget] {
        guard text.isEmpty.not else { return [] }
        return cache.compactMap { virtualPath, content in
            let matchCount = content.components(separatedBy: text).count - 1
            guard matchCount > 0 else { return nil }
            return TextReplacementTarget(filepath: virtualPath, expectedMatches: matchCount)
        }.sorted { $0.filepath < $1.filepath }
    }

    func fileChanged(_ change: FolderChange) {
        switch change {
        case .deleted(let url):
            cache[folder.virtualPath(url.path())] = nil
        case .added(let url), .changed(let url):
            load(virtualPath: folder.virtualPath(url.path()))
        }
    }

    private func load(virtualPath: String) {
        guard let url = try? folder.projectURL(for: virtualPath) else {
            cache[virtualPath] = nil
            return
        }
        if folder.isAllowedFile(url), let content = try? String(contentsOf: url, encoding: .utf8) {
            self.cache[virtualPath] = content
            logger.d("🔁 Loaded content from \(virtualPath)")
        } else {
            logger.d("🔁 Unloaded content from \(virtualPath)")
            self.cache[virtualPath] = nil
        }
    }

    private func lineMatches(_ line: String, options: SearchOptions, expression: NSRegularExpression?) -> Bool {
        if let expression {
            let range = NSRange(line.startIndex..., in: line)
            return expression.firstMatch(in: line, range: range) != nil
        }
        if options.caseSensitive {
            return line.contains(options.query)
        }
        return line.range(of: options.query, options: .caseInsensitive) != nil
    }

    private func matchesPath(_ path: String, options: SearchOptions) -> Bool {
        let isIncluded = options.includeGlobs.isEmpty || options.includeGlobs.contains { globMatches(path, glob: $0) }
        return isIncluded && options.excludeGlobs.contains { globMatches(path, glob: $0) }.not
    }

    private func globMatches(_ path: String, glob: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: glob)
            .replacingOccurrences(of: "\\*\\*", with: ".*")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
            .replacingOccurrences(of: "\\?", with: "[^/]")
        return path.range(of: "^\(escaped)$", options: .regularExpression) != nil
    }
}
