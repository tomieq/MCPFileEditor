//
//  CoderEngine.swift
//  MCPServer
//
//  Created by: tomieq on 22/04/2026
//
import Foundation
import Swifter
import Logger
import MCPServer

enum CoderCommand: String {
    case list_files
    case find_file
    case read_file
    case rename_file
    case override_file
    case create_new_file
    case delete_file
    case file_glob_search
}

extension CoderCommand: CustomStringConvertible {
    var description: String {
        rawValue
    }
}

class CoderEngine: Engine {
    private let logger = Logger(CoderEngine.self)
    let folder: Folder
    let cache: FileCache

    init(folder: Folder, cache: FileCache) {
        self.folder = folder
        self.cache = cache
    }

    let instructions = "This tool can list and search all files in the project, read and write their content, and more."

    func command(for rawValue: String) -> CoderCommand? {
        CoderCommand(rawValue: rawValue)
    }

    func canHandle(_ command: String) -> Bool {
        self.command(for: command).notNil
    }

    let tools: [ToolsList.Schema] = [
        .init(CoderCommand.list_files,
              description: "Use this tool if you need to find out what files are in the project. Tool returs a list of absolute paths of all the files.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [:],
                            required: [])
        ),
        .init(CoderCommand.find_file,
              description: "Use this tool if you need to get absolute path for a file. Provide filename or its part and you will get absolute paths of matching files.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filename": .init(type: .string, description: "Filename or its part to search for")
                            ],
                            required: ["filepath"])
        ),
        .init(CoderCommand.read_file,
              description: "Use this tool if you need to view the contents of an existing file.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The absolute path of the file to read")
                            ],
                            required: ["filepath"])
        ),
        .init(CoderCommand.rename_file,
              description: "Use this tool if you need to chnage the file's name or move the file within the project",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "oldFilepath": .init(type: .string, description: "Current absolute path of the file"),
                                "newFilepath": .init(type: .string, description: "New absolute path of to be set for the file")
                            ],
                            required: ["oldFilepath", "newFilepath"])
        ),
        .init(CoderCommand.override_file,
              description: "Use this tool if you need to override the content of an existing file.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The absolute path of the file to write to"),
                                "content": .init(type: .string, description: "The utf8 content to write")
                            ],
                            required: ["filepath", "content"])
        ),
        .init(CoderCommand.create_new_file,
              description: "Create a new file. Only use this when a file doesn't exist and should be created",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The absolute path of the file to create"),
                                "content": .init(type: .string, description: "The utf8 content to write")
                            ],
                            required: ["filepath", "content"])
        ),
        .init(CoderCommand.delete_file,
              description: "Use this tool if you need to completely delete a file",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The absolute path of the file to delete")
                            ],
                            required: ["filepath"])
        ),
        .init(CoderCommand.file_glob_search,
              description: "Use this tool if you need to search files for a particular text(no regex). The result is the json list (filepath, line, lineContent) containing paths to files and line numbers ({\"filepath\": \"<PATH>\", \"mathingLine\": \"<LINE HERE>\"})",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "search": .init(type: .string, description: "The text to search for")
                            ],
                            required: ["search"])
        )
    ]

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        guard let command = self.command(for: command) else {
            return ToolResult([])
        }
        let dto: ToolResult
        switch command {
        case .list_files:
            logger.d("🗄️ List project's files")

            dto = ToolResult(folder.files())
        case .find_file:
            struct File: Codable {
                let filename: String
            }
            let command: Command<File> = try body.decode()
            let filename = command.params?.arguments?.filename ?? ""

            logger.d("🔎 Find file \(filename)")
            dto = ToolResult(folder.files().filter{ $0.contains(filename) })
        case .read_file:
            struct File: Codable {
                let filepath: String
            }
            let command: Command<File> = try body.decode()
            let virtualPath = command.params?.arguments?.filepath ?? ""
            let filepath = folder.realPath(virtualPath)

            logger.d("👀 Read file content: \(virtualPath)")
            let content = try? String(contentsOfFile: filepath, encoding: .utf8)
            dto = ToolResult([content.or("File not found at \(virtualPath)")])
        case .rename_file:
            struct Action: Codable {
                let oldFilepath: String
                let newFilepath: String
            }
            let command: Command<Action> = try body.decode()
            let virtualPath = command.params?.arguments?.oldFilepath ?? ""
            let newVirtualpath = command.params?.arguments?.newFilepath ?? ""

            let filepath = folder.realPath(virtualPath)
            let newFilepath = folder.realPath(newVirtualpath)

            guard FileManager.default.fileExists(atPath: filepath) else {
                dto = ToolResult(["File not found at \(virtualPath)"])
                break
            }
            guard FileManager.default.fileExists(atPath: newFilepath).not else {
                dto = ToolResult(["File already exists at \(virtualPath)"])
                break
            }
            try? FileManager.default.moveItem(atPath: filepath, toPath: newFilepath)
            logger.d("💾⚙️ Rename filename from \(virtualPath) ➡️ \(newVirtualpath)")
            dto = ToolResult(["File has been moved from \(virtualPath) to \(newVirtualpath)"])
        case .override_file:
            struct Action: Codable {
                let filepath: String
                let content: String
            }
            let command: Command<Action> = try body.decode()
            let virtualPath = command.params?.arguments?.filepath ?? ""
            let content = command.params?.arguments?.content ?? ""

            let filepath = folder.realPath(virtualPath)

            guard FileManager.default.fileExists(atPath: filepath) else {
                dto = ToolResult(["File not found at \(virtualPath)"])
                break
            }
            try? content.write(toFile: filepath, atomically: true, encoding: .utf8)
            logger.d("💾🟠 Override file \(virtualPath)")
            dto = ToolResult(["The content has been written to \(virtualPath)"])
        case .create_new_file:
            struct Action: Codable {
                let filepath: String
                let content: String
            }
            let command: Command<Action> = try body.decode()
            let virtualPath = command.params?.arguments?.filepath ?? ""
            let content = command.params?.arguments?.content ?? ""

            let filepath = folder.realPath(virtualPath)

            guard FileManager.default.fileExists(atPath: filepath).not else {
                dto = ToolResult(["File already exists at \(virtualPath)"])
                break
            }
            try? content.write(toFile: filepath, atomically: true, encoding: .utf8)
            logger.d("💾🟢 Create file \(virtualPath)")
            dto = ToolResult(["File has been created at \(virtualPath)"])
        case .delete_file:
            struct Action: Codable {
                let filepath: String
            }
            let command: Command<Action> = try body.decode()
            let virtualPath = command.params?.arguments?.filepath ?? ""
            let filepath = folder.realPath(virtualPath)

            guard FileManager.default.fileExists(atPath: filepath) else {
                dto = ToolResult(["File \(virtualPath) does not exists"])
                break
            }
            try? FileManager.default.removeItem(atPath: filepath)
            logger.d("💾🔴 Delete file \(virtualPath)")
            dto = ToolResult(["File \(virtualPath) has been deleted"])
        case .file_glob_search:
            struct Action: Codable {
                let search: String
            }
            let command: Command<Action> = try body.decode()
            let search = command.params?.arguments?.search ?? ""
            logger.i("🔎 Searching text: \(search)")

            dto = ToolResult(cache.matching(search).compactMap { $0.jsonOneLine })
        }
        return dto
    }
}
