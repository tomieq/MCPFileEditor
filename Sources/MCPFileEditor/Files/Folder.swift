//
//  Folder.swift
//  MCPServer
//
//  Created by: tomieq on 16/02/2026
//
import Foundation
import Logger
import SwiftExtensions
import Env
import FileTree

enum FolderError: LocalizedError {
    case invalidProjectPath(String)

    var errorDescription: String? {
        switch self {
        case .invalidProjectPath(let path):
            return "Path must be a non-empty project-relative path that remains within the configured project: \(path)"
        }
    }
}

class Folder {
    private let logger = Logger(Folder.self)
    let realUrl: URL
    let allowedExtensions: [String]
    let excludedFolders: [String]

    init(config: FolderConfig) {
        let projectPath = config.projectPath
        let extensions = config.fileExtensions.split(",").map{ $0.trimmed }
        logger.d("Starting in \(projectPath) with extensions: \(extensions)")
        self.excludedFolders = config.excludedFolders ?? [
            "venv", "runs", ".git", ".build", ".swiftpm"
        ]
        self.realUrl = URL(fileURLWithPath: projectPath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        self.allowedExtensions = extensions
    }

    private let virtualUrl = URL(fileURLWithPath: "/")
    private let fileManager = FileManager.default

    func files() -> [String] {
        self.crawl(url: self.realUrl, prefix: "")
    }

    func tree() -> String {
        FileTree(realUrl, configuration: .init(allowedFileExtensions: allowedExtensions,
                                               showsEmptyFolders: false,
                                               excludedFolders: excludedFolders))
            .tree
            .replacingOccurrences(of: realUrl.path().dropLast(), with: ".")
    }

    func projectURL(for virtualPath: String) throws -> URL {
        guard virtualPath.isEmpty.not,
              virtualPath.hasPrefix("/").not,
              virtualPath.split(separator: "/").contains("..").not else {
            throw FolderError.invalidProjectPath(virtualPath)
        }

        let rootPath = realUrl.path.hasSuffix("/") ? realUrl.path : realUrl.path + "/"
        var candidate = realUrl
        for component in virtualPath.split(separator: "/") {
            candidate = candidate.appendingPathComponent(String(component)).standardizedFileURL
            if fileManager.fileExists(atPath: candidate.path) {
                candidate = candidate.resolvingSymlinksInPath().standardizedFileURL
            }
            guard candidate.path.hasPrefix(rootPath) else {
                throw FolderError.invalidProjectPath(virtualPath)
            }
        }
        return candidate
    }

    func virtualPath(_ realPath: String) -> String {
        realPath.replacingOccurrences(of: realUrl.path(), with: virtualUrl.path())
    }

    func isAllowedFile(_ url: URL) -> Bool {
        allowedExtensions.isEmpty || allowedExtensions.contains(url.pathExtension)
    }

    private func crawl(url: URL, prefix: String) -> [String] {
        let files = (try? self.fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [])) ?? []
        var output: [String] = []
        files.enumerated().forEach { index, fileUrl in
            let isDir = (try? fileUrl.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let filename = fileUrl.pathComponents.last ?? "nil"
//            guard filename.starts(with: ".").not else { return }
            if isDir, excludedFolders.contains(filename).not {
                let newPrefix = prefix + filename + "/"
                let fileUrl = url.appendingPathComponent(filename)
                output.append(contentsOf: self.crawl(url: fileUrl, prefix: newPrefix))
            } else if isAllowedFile(fileUrl) {
                output.append(prefix + filename)
            }
        }
        return output
    }
}
