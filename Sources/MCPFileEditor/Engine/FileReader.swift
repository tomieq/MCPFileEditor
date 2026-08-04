import Foundation

struct FileReadResult: Encodable {
    let filepath: String
    let startLine: Int
    let endLine: Int
    let totalLines: Int
    let content: String
    let truncated: Bool
    let nextStartLine: Int?
}

enum FileReaderError: LocalizedError {
    case invalidArgument(String)
    case notUTF8(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        case .notUTF8(let filepath): return "File is not valid UTF-8: \(filepath)"
        }
    }
}

struct FileReader {
    static let defaultLineCount = 200
    static let defaultMaxBytes = 64 * 1024
    static let maximumMaxBytes = 1024 * 1024

    func read(url: URL,
              filepath: String,
              startLine: Int?,
              endLine: Int?,
              maxBytes: Int?) throws -> FileReadResult {
        let start = startLine ?? 1
        guard start > 0 else {
            throw FileReaderError.invalidArgument("startLine must be at least 1")
        }
        let maximumBytes = maxBytes ?? Self.defaultMaxBytes
        guard (1...Self.maximumMaxBytes).contains(maximumBytes) else {
            throw FileReaderError.invalidArgument("maxBytes must be between 1 and \(Self.maximumMaxBytes)")
        }

        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw FileReaderError.notUTF8(filepath)
        }
        let lines = content.components(separatedBy: "\n")
        let contentLines = content.hasSuffix("\n") ? Array(lines.dropLast()) : lines
        let totalLines = contentLines.count
        guard start <= totalLines else {
            throw FileReaderError.invalidArgument("startLine \(start) exceeds the file's \(totalLines) line(s)")
        }

        let requestedEnd = endLine ?? min(totalLines, start + Self.defaultLineCount - 1)
        guard requestedEnd >= start else {
            throw FileReaderError.invalidArgument("endLine must not precede startLine")
        }
        let finalEnd = min(requestedEnd, totalLines)
        let selection = contentLines[(start - 1)..<finalEnd].joined(separator: "\n")
        let bounded = Self.prefix(selection, atMostUTF8Bytes: maximumBytes)
        let truncatedByBytes = bounded.utf8.count < selection.utf8.count
        let hasMoreLines = finalEnd < totalLines
        return FileReadResult(filepath: filepath,
                              startLine: start,
                              endLine: finalEnd,
                              totalLines: totalLines,
                              content: bounded,
                              truncated: truncatedByBytes || hasMoreLines,
                              nextStartLine: truncatedByBytes ? start : (hasMoreLines ? finalEnd + 1 : nil))
    }

    private static func prefix(_ value: String, atMostUTF8Bytes maximum: Int) -> String {
        guard value.utf8.count > maximum else { return value }
        var result = ""
        var count = 0
        for character in value {
            let characterBytes = String(character).utf8.count
            guard count + characterBytes <= maximum else { break }
            result.append(character)
            count += characterBytes
        }
        return result
    }
}
