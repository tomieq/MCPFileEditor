//
//  FileCache.swift
//  MCPServer
//
//  Created by: tomieq on 16/02/2026
//
import Foundation
import Logger
import SwiftExtensions

struct SearchResult: Codable {
    let filepath: String
    let line: Int
    let lineContent: String
}

class FileCache {
    private let folder: Folder
    private var cache: [String: String] = [:]
    private let logger = Logger(FileCache.self)

    init(folder: Folder) {
        self.folder = folder
        for virtualPath in folder.files() {
            load(virtualPath: virtualPath)
        }
    }

    func matching(_ text: String) -> [SearchResult] {
        var results: [SearchResult] = []
        for (virtualPath, content) in cache where content.contains(text) {
            let lines = content.split("\n")
            for (number, line) in lines.enumerated() {
                if line.contains(text) {
                    results.append(SearchResult(filepath: virtualPath,
                                                line: number.incremented,
                                                lineContent: line))
                }
            }
        }
        return results
    }

    func fileChanged(_ change: FolderChange) {
        switch change {
        case .deleted(let url):
            cache[folder.virtualPath(url.path())] = nil
        case .added(let url), .changed(let url):
            load(virtualPath: folder.virtualPath(url.path()))
        }
    }

    private func load(virtualPath: String) {
        let path = folder.realPath(virtualPath)
        let fileExtension = virtualPath.split("/").last?.split(".").last
        if let fileExtension, folder.allowedExtensions.contains(fileExtension), let content = try? String(contentsOfFile: path) {
            self.cache[virtualPath] = content
            logger.d("🔁 Loaded content from \(virtualPath)")
        } else {
            logger.d("🔁 Unloaded content from \(virtualPath)")
            self.cache[virtualPath] = nil
        }
    }
}
