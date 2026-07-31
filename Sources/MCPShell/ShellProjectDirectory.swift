import Foundation

enum ShellProjectDirectoryError: LocalizedError {
    case invalidProjectPath(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectPath(let path):
            return "Project path is not a directory: \(path)"
        }
    }
}

final class ShellProjectDirectory {
    let url: URL

    init(projectPath: String) throws {
        let url = URL(fileURLWithPath: projectPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ShellProjectDirectoryError.invalidProjectPath(projectPath)
        }
        self.url = url
    }
}