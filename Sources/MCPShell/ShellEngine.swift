import Dispatch
import Foundation
import MCPServer
import Swifter

private enum ShellCommand: String, CustomStringConvertible {
    case run = "shell_run"

    var description: String { rawValue }
}

final class ShellEngine: Engine {
    private let projectDirectory: ShellProjectDirectory

    init(projectDirectory: ShellProjectDirectory) {
        self.projectDirectory = projectDirectory
    }

    let instructions = "Run shell commands with the configured project directory as the fixed initial working directory. This tool may change files and run arbitrary executables. It is not a filesystem sandbox."

    let tools: [ToolsList.Schema] = [
        .init(ShellCommand.run,
              description: "Run a zsh command from the configured project directory. The command may use shell syntax such as pipes and redirects. The working directory cannot be supplied by the caller. Optional environment variables apply only to this command.",
              inputSchema: .init(properties: [
                  "command": .init(type: .string, description: "Shell command to run from the project directory."),
                  "environment": .init(type: .object, description: "String-to-string environment variables for this command only."),
                  "timeoutSeconds": .init(type: .integer, description: "Maximum runtime in seconds, from 1 through 900; defaults to 300.")
              ], required: ["command"]))
    ]

    func canHandle(_ command: String) -> Bool {
        ShellCommand(rawValue: command) != nil
    }

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        guard ShellCommand(rawValue: command) == .run else { return ToolResult([]) }
        do {
            let request: Command<Arguments> = try body.decode()
            guard let arguments = request.params?.arguments else {
                throw ShellToolError.invalidArgument("Missing tool arguments")
            }
            let result = try run(arguments)
            let header = "exitStatus: \(result.status)\ntimedOut: \(result.timedOut)"
            return ToolResult([result.output.isEmpty ? header : "\(header)\n\n\(result.output)"])
        } catch {
            return ToolResult(["Shell command failed: \(error.localizedDescription)"])
        }
    }
}

private extension ShellEngine {
    func run(_ arguments: Arguments) throws -> ShellExecutionResult {
        let command = try validatedCommand(arguments.command)
        let timeout = try validatedTimeout(arguments.timeoutSeconds)
        let environment = try buildEnvironment(arguments.environment ?? [:])

        let task = Process()
        let outputPipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.arguments = ["-c", command]
        task.currentDirectoryURL = projectDirectory.url
        task.environment = environment
        task.standardOutput = outputPipe
        task.standardError = outputPipe

        let state = TimeoutState()
        let timeoutWork = DispatchWorkItem {
            guard task.isRunning else { return }
            state.markTimedOut()
            task.terminate()
        }
        try task.run()
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeout), execute: timeoutWork)
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        timeoutWork.cancel()

        return ShellExecutionResult(
            output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines),
            status: task.terminationStatus,
            timedOut: state.timedOut
        )
    }

    func validatedCommand(_ command: String) throws -> String {
        guard command.isEmpty.not, command.count <= 100_000, command.contains("\0").not else {
            throw ShellToolError.invalidArgument("command must be between 1 and 100,000 characters and contain no NUL bytes")
        }
        return command
    }

    func validatedTimeout(_ value: Int?) throws -> Int {
        let timeout = value ?? 300
        guard (1...900).contains(timeout) else {
            throw ShellToolError.invalidArgument("timeoutSeconds must be between 1 and 900")
        }
        return timeout
    }

    func buildEnvironment(_ requested: [String: String]) throws -> [String: String] {
        guard requested.count <= 100 else {
            throw ShellToolError.invalidArgument("environment may contain at most 100 variables")
        }
        var environment = ProcessInfo.processInfo.environment
        for (key, value) in requested {
            guard isValidEnvironmentKey(key), value.contains("\0").not else {
                throw ShellToolError.invalidArgument("Invalid environment variable: \(key)")
            }
            environment[key] = value
        }
        return environment
    }

    func isValidEnvironmentKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, first.properties.isAlphabetic || first == "_" else { return false }
        return key.unicodeScalars.allSatisfy { $0.properties.isAlphabetic || $0.properties.numericType != nil || $0 == "_" }
    }
}

private struct Arguments: Decodable {
    let command: String
    let environment: [String: String]?
    let timeoutSeconds: Int?
}

private struct ShellExecutionResult {
    let output: String
    let status: Int32
    let timedOut: Bool
}

private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var timedOut: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func markTimedOut() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private enum ShellToolError: LocalizedError {
    case invalidArgument(String)

    var errorDescription: String? {
        switch self {
        case .invalidArgument(let message): return message
        }
    }
}

private extension Bool {
    var not: Bool { !self }
}