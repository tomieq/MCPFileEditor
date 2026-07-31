import Foundation

struct ShellResult {
    let output: String
    let status: Int32

    var succeeded: Bool { status == 0 }
}

/// Runs one executable with a fixed argument vector. It deliberately does not invoke a shell.
struct Shell {
    func exec(executable: String, arguments: [String], currentDirectory: URL) throws -> ShellResult {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        task.currentDirectoryURL = currentDirectory
        task.standardOutput = pipe
        task.standardError = pipe
        task.environment = [
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "GIT_PAGER": "cat",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_OPTIONAL_LOCKS": "0"
        ]

        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return ShellResult(
            output: String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines),
            status: task.terminationStatus
        )
    }
}