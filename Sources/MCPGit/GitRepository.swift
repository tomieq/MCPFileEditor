import Foundation

enum GitRepositoryError: LocalizedError {
    case invalidProjectPath(String)
    case notRepository(String)
    case projectPathIsNotRepositoryRoot(projectPath: String, repositoryRoot: String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectPath(let path):
            return "Project path is not a directory: \(path)"
        case .notRepository(let path):
            return "Project path is not a Git work-tree: \(path)"
        case .projectPathIsNotRepositoryRoot(let projectPath, let repositoryRoot):
            return "Project path must be the Git work-tree root (got \(projectPath), expected \(repositoryRoot))."
        }
    }
}

final class GitRepository {
    let rootURL: URL
    private let shell = Shell()

    init(projectPath: String) throws {
        let inputURL = URL(fileURLWithPath: projectPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: inputURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw GitRepositoryError.invalidProjectPath(projectPath)
        }

        let result = try shell.exec(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "--show-toplevel"],
            currentDirectory: inputURL
        )
        guard result.succeeded, result.output.isEmpty.not else {
            throw GitRepositoryError.notRepository(projectPath)
        }

        let repositoryURL = URL(fileURLWithPath: result.output)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard repositoryURL.path == inputURL.path else {
            throw GitRepositoryError.projectPathIsNotRepositoryRoot(
                projectPath: inputURL.path,
                repositoryRoot: repositoryURL.path
            )
        }
        self.rootURL = repositoryURL
    }

    func run(_ arguments: [String]) throws -> ShellResult {
        try shell.exec(executable: "/usr/bin/git", arguments: arguments, currentDirectory: rootURL)
    }
}

private extension Bool {
    var not: Bool { !self }
}