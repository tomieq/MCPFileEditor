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
        (realUrl.relativePath + "\n" + self.crawlTree(url: realUrl, prefix: ""))
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
        guard allowedExtensions.isEmpty.not else { return true }
        return allowedExtensions.contains(url.pathExtension)
            || (url.pathExtension.isEmpty && allowedExtensions.contains(url.lastPathComponent))
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
            } else if isDir.not, isAllowedFile(fileUrl) {
                output.append(prefix + filename)
            }
        }
        return output
    }

    private func crawlTree(url: URL, prefix: String) -> String {
        let visibleFiles = self.visibleFiles(in: url)
        var output = ""

        visibleFiles.enumerated().forEach { index, fileUrl in
            let isDirectory = (try? fileUrl.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let isLast = index == visibleFiles.count - 1
            let graphic = isLast ? "└──" : "├──"
            let filename = fileUrl.lastPathComponent
            output.append("\(prefix)\(graphic) \(filename) \n")

            if isDirectory {
                let newPrefix = prefix + (isLast ? "    " : "│   ")
                output.append(self.crawlTree(url: fileUrl, prefix: newPrefix))
            }
        }
        return output
    }

    private func visibleFiles(in url: URL) -> [URL] {
        let files = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [])) ?? []
        return files.filter { fileUrl in
            let isDirectory = (try? fileUrl.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else { return isAllowedFile(fileUrl) }
            return excludedFolders.contains(fileUrl.lastPathComponent).not
                && visibleFiles(in: fileUrl).isEmpty.not
        }
    }
}
