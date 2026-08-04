import Foundation
import MCPServer
import Swifter

/// A read-only MCP server for inspecting one Git work-tree.
public final class MCPGit {
    public enum ResponseFormat {
        case text
        case structured
        case both
    }

    public let mcp: MCPServer

    public init(config: GitConfig,
                server: HttpServer? = nil,
                responseFormat: ResponseFormat = .both) throws {
        let repository = try GitRepository(projectPath: config.projectPath)
        let serverConfig = MCPServerConfig(
            serverName: "MCP Git",
            engines: [GitEngine(repository: repository, responseFormat: responseFormat)]
        )
        self.mcp = MCPServer(config: serverConfig, server: server)
    }
}