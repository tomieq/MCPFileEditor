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

func toolSuccess<Value: Encodable>(_ data: Value) -> ToolResult {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let value = ToolSuccess(data: data)
    let output = (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{\"ok\":false,\"errorCode\":\"serialization_failed\",\"error\":\"Could not serialize tool response\"}"
    return (try? ToolResult(structuredContent: value, text: [output])) ?? ToolResult([output])
}

func toolFailure(_ error: Error, code: String = "operation_failed") -> ToolResult {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let value = ToolFailure(errorCode: code, error: error.localizedDescription)
    let output = (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{\"ok\":false,\"errorCode\":\"serialization_failed\",\"error\":\"Could not serialize tool error\"}"
    return (try? ToolResult(structuredContent: value, text: [output])) ?? ToolResult([output])
}

func toolFailure(_ message: String, code: String) -> ToolResult {
    toolFailure(ToolResponseError(message: message), code: code)
}

private struct ToolResponseError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
