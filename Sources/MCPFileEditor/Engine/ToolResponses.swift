import Foundation
import MCPServer

struct ToolSuccess<Value: Encodable>: Encodable {
    let ok = true
    let data: Value
}

struct ToolFailure: Encodable {
    let ok = false
    let errorCode: String
    let error: String
}

struct FileTreeResult: Encodable { let tree: String }
struct FilePathsResult: Encodable { let paths: [String] }
struct FileMoveResult: Encodable { let oldFilepath: String; let newFilepath: String }
struct FileWriteResult: Encodable { let filepath: String; let changed: Bool }
struct FileDeleteResult: Encodable { let filepath: String; let deleted: Bool }
struct SearchTextResult: Encodable { let results: [SearchResult]; let limit: Int; let truncated: Bool }
struct PatchToolResult: Encodable {
    let filesChanged: Int
    let changed: Bool
    let dryRun: Bool
    let paths: [String]
    let report: PatchDryRunReport
}

struct ToolResponseFactory {
    let format: MCPFileEditor.ResponseFormat

    func success<Value: Encodable>(_ data: Value) -> ToolResult {
        response(ToolSuccess(data: data), fallback: "Could not serialize tool response")
    }

    func failure(_ error: Error, code: String = "operation_failed") -> ToolResult {
        response(ToolFailure(errorCode: code, error: error.localizedDescription), fallback: "Could not serialize tool error")
    }

    func failure(_ message: String, code: String) -> ToolResult {
        failure(ToolResponseError(message: message), code: code)
    }

    private func response<Value: Encodable>(_ value: Value, fallback: String) -> ToolResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let text = (try? String(data: encoder.encode(value), encoding: .utf8))
            ?? "{\"ok\":false,\"errorCode\":\"serialization_failed\",\"error\":\"\(fallback)\"}"
        switch format {
        case .text:
            return ToolResult([text])
        case .structured:
            return (try? ToolResult(structuredContent: value)) ?? ToolResult([text])
        case .both:
            return (try? ToolResult(structuredContent: value, text: [text])) ?? ToolResult([text])
        }
    }
}

private struct ToolResponseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
