import Foundation

/// Configuration for a shell MCP server that always starts commands in one project directory.
public struct ShellConfig: Decodable {
    /// Absolute path used as the working directory for every command.
    public let projectPath: String

    public init(projectPath: String) {
        self.projectPath = projectPath
    }
}