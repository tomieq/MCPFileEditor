import Foundation

/// Configuration for a read-only Git MCP server.
public struct GitConfig: Decodable {
    /// Absolute path to the Git work-tree that the server may inspect.
    public let projectPath: String

    public init(projectPath: String) {
        self.projectPath = projectPath
    }
}