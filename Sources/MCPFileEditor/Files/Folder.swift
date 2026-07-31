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

class Folder {
    private let logger = Logger(Folder.self)
    let realUrl: URL
    let allowedExtensions: [String]
    let excludedFolders = [
        "venv", "runs", ".git"
    ]

    init(config: FolderConfig) {
        let projectPath = config.projectPath
        let extensions = config.fileExtensions.split(",").map{ $0.trimmed }
        logger.d("Starting in \(projectPath) with extensions: \(extensions)")
        self.realUrl = URL(fileURLWithPath: projectPath)
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

    func realPath(_ virtualPath: String) -> String {
        realUrl.appendingPathComponent(virtualPath).path()
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
