//
//  FolderConfig.swift
//  MCPFileEditor
//
//  Created by: tomieq on 29/07/2026
//

public struct FolderConfig: Decodable {
    public let projectPath: String
    public let fileExtensions: String
    public let excludedFolders: [String]?

    public init(projectPath: String, fileExtensions: String, excludedFolders: [String]? = nil) {
        self.projectPath = projectPath
        self.fileExtensions = fileExtensions
        self.excludedFolders = excludedFolders
    }
}
