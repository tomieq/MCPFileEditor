import Foundation
import Logger
import Dispatch
import MCPFileEditor
import Env

#if os(Linux)
setvbuf(stdout, nil, _IONBF, 0)
#endif

let logger = Logger("MCPFileditor")
let config: FolderConfig = try Env.shared.decode()
let mcpFileEditor = try MCPFileEditor(config: config)
let port: UInt16
if let configuredPort = Env.shared.int("localPort") {
    port = UInt16(configuredPort)
} else {
    port = 8081
}

try mcpFileEditor.mcp.server.start(port, forceIPv4: true)
logger.i("Server started on port \(try mcpFileEditor.mcp.server.port)")
RunLoop.main.run()
