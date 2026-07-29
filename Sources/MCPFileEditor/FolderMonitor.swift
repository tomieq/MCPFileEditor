//
//  FolderMonitor.swift
//  MCPServer
//
//  Created by: tomieq on 16/02/2026
//

import Foundation
import FileMonitor
import Logger

enum FolderChange {
    case added(file: URL)
    case deleted(file: URL)
    case changed(file: URL)
}

extension FileChange {
    var folderChange: FolderChange {
        switch self {
        case .added(let file):
            return .added(file: file)
        case .deleted(let file):
            return .deleted(file: file)
        case .changed(let file):
            return .changed(file: file)
        }
    }
}

class FolderMonitor: FileDidChangeDelegate {
    private let watcher: (FolderChange) -> Void
    private let logger = Logger(FolderMonitor.self)
    private var previouslyChangedFile: URL?

    init(folder: URL, watcher: @escaping (FolderChange) -> Void) throws {
        self.watcher = watcher
        logger.i("Starting in \(folder.path)")
        let monitor = try FileMonitor(directory: folder, delegate: self)
        try monitor.start()
    }

    public func fileDidChanged(event: FileChange) {
        logger.i("🗂️ \(event)")
        watcher(event.folderChange)
    }
}
