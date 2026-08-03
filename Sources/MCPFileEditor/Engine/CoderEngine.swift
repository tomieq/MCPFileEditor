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
    case file_tree
    case list_paths
    case find_file
    case read_file
    case rename_file
    case override_file
    case create_new_file
    case delete_file
    case file_glob_search
    case apply_patch
    case replace_text
    case replace_all
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
        .init(CoderCommand.file_tree,
              description: "Use this tool to get a file tree of the project. Tool returns equivalent of `tree` command.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [:],
                            required: [])
        ),
        .init(CoderCommand.list_paths,
              description: "Use this tool to get list of files' paths are in the project. Tool returs a list of relative paths.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [:],
                            required: [])
        ),
        .init(CoderCommand.find_file,
              description: "Use this tool to find an relative path for a file in the project",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filename": .init(type: .string, description: "Filename or its part to search for. No regex support")
                            ],
                            required: ["filepath"])
        ),
        .init(CoderCommand.read_file,
              description: "Use this tool if you want to get the contents of file.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The relative path of the file to read")
                            ],
                            required: ["filepath"])
        ),
        .init(CoderCommand.rename_file,
              description: "Use this tool to rename or move the file within the project",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "oldFilepath": .init(type: .string, description: "Current relative path of the file"),
                                "newFilepath": .init(type: .string, description: "New relative path of to be set for the file")
                            ],
                            required: ["oldFilepath", "newFilepath"])
        ),
        .init(CoderCommand.override_file,
              description: "Use this tool to override the content of an existing file.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The relative path of the file to write to"),
                                "content": .init(type: .string, description: "The utf8 content to write")
                            ],
                            required: ["filepath", "content"])
        ),
        .init(CoderCommand.create_new_file,
              description: "Create a new file. Only use this when a file doesn't exist and should be created",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The relative path of the file to create"),
                                "content": .init(type: .string, description: "The utf8 content to write")
                            ],
                            required: ["filepath", "content"])
        ),
        .init(CoderCommand.delete_file,
              description: "Use this tool to delete a file",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The relative path of the file to delete")
                            ],
                            required: ["filepath"])
        ),
        .init(CoderCommand.file_glob_search,
              description: "Use this tool to search files for a particular text(no regex). The result is the json list (filepath, line, lineContent)",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "search": .init(type: .string, description: "The text to search for")
                            ],
                            required: ["search"])
        ),
        .init(CoderCommand.apply_patch,
              description: "Apply a unified diff to project-relative UTF-8 text files without requiring Git. Use ---/+++ headers; a/ and b/ path prefixes are optional. Standard @@ -oldStart,oldCount +newStart,newCount @@ headers are supported, as are minimal @@ context-matched hunks. Multiple hunks and files are supported. Hunks first match exactly, then may use unique nearby or whitespace-insensitive context matching. dryRun returns structured JSON with target paths, match positions, match strategies, and added/removed line counts.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "patch": .init(type: .string, description: "A unified diff with --- and +++ file headers. Paths must be project-relative; a/ and b/ prefixes are optional. Prefer explicit line ranges; minimal @@ hunks need unique source context."),
                                "dryRun": .init(type: .boolean, description: "Validate without writing and return structured JSON diagnostics. Defaults to false.")
                            ],
                            required: ["patch"])
        ),
        .init(CoderCommand.replace_text,
              description: "Replace exact text in one project-relative UTF-8 file. For safety, the current number of matches must exactly equal expectedMatches (which defaults to 1). Set replaceAll only when every verified match should change. Use dryRun to validate and return structured JSON without writing.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "filepath": .init(type: .string, description: "The project-relative path of the existing UTF-8 file."),
                                "find": .init(type: .string, description: "The non-empty exact text to find."),
                                "replace": .init(type: .string, description: "The text that replaces the match; it may be empty."),
                                "expectedMatches": .init(type: .integer, description: "Exact number of current matches required before writing. Defaults to 1."),
                                "replaceAll": .init(type: .boolean, description: "Replace every match after expectedMatches validation. Defaults to false."),
                                "dryRun": .init(type: .boolean, description: "Validate without writing and return structured JSON. Defaults to false.")
                            ],
                            required: ["filepath", "find", "replace"])
        ),
        .init(CoderCommand.replace_all,
              description: "Replace exact text in every cached, tracked project file containing it. The cached total must exactly equal expectedMatches, then every file is revalidated from disk before any write. Always use dryRun first; the result lists affected files and replacement counts.",
              inputSchema:
              ToolParameter(type: .object,
                            properties: [
                                "find": .init(type: .string, description: "The non-empty exact text to find in all cached project files."),
                                "replace": .init(type: .string, description: "The text that replaces every verified match; it may be empty."),
                                "expectedMatches": .init(type: .integer, description: "Exact total number of matches required across cached project files."),
                                "dryRun": .init(type: .boolean, description: "Validate without writing and return structured JSON. Defaults to false.")
                            ],
                            required: ["find", "replace", "expectedMatches"])
        )
    ]

    func call(_ command: String, body: HttpRequestBody) throws -> ToolResult {
        guard let command = self.command(for: command) else {
            return ToolResult([])
        }
        let dto: ToolResult
        switch command {
        case .file_tree:
            logger.d("🗄️ Tree of project's files")

            dto = ToolResult([folder.tree()])
        case .list_paths:
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
        case .apply_patch:
            struct Action: Codable {
                let patch: String
                let dryRun: Bool?
            }
            let command: Command<Action> = try body.decode()
            let patch = command.params?.arguments?.patch ?? ""
            let dryRun = command.params?.arguments?.dryRun ?? false

            do {
                let result = try UnifiedPatchApplier(rootURL: folder.realUrl).apply(patch, dryRun: dryRun)
                logger.d("💾🩹 \(result.message)")
                dto = ToolResult([dryRun ? result.structuredMessage : result.message])
            } catch {
                dto = ToolResult(["Patch was not applied: \(error.localizedDescription)"])
            }
        case .replace_text:
            struct Action: Codable {
                let filepath: String
                let find: String
                let replace: String
                let expectedMatches: Int?
                let replaceAll: Bool?
                let dryRun: Bool?
            }
            let command: Command<Action> = try body.decode()
            let arguments = command.params?.arguments

            do {
                let result = try TextReplacer(rootURL: folder.realUrl).replace(
                    filepath: arguments?.filepath ?? "",
                    find: arguments?.find ?? "",
                    replacement: arguments?.replace ?? "",
                    expectedMatches: arguments?.expectedMatches ?? 1,
                    replaceAll: arguments?.replaceAll ?? false,
                    dryRun: arguments?.dryRun ?? false
                )
                logger.d("💾🔁 \(result.message)")
                dto = ToolResult([result.dryRun ? result.structuredMessage : result.message])
            } catch {
                dto = ToolResult(["Text was not replaced: \(error.localizedDescription)"])
            }
        case .replace_all:
            struct Action: Codable {
                let find: String
                let replace: String
                let expectedMatches: Int
                let dryRun: Bool?
            }
            let command: Command<Action> = try body.decode()
            let arguments = command.params?.arguments
            let find = arguments?.find ?? ""
            let dryRun = arguments?.dryRun ?? false

            do {
                let result = try TextReplacer(rootURL: folder.realUrl).replaceAll(
                    targets: cache.replacementTargets(find),
                    find: find,
                    replacement: arguments?.replace ?? "",
                    expectedMatches: arguments?.expectedMatches ?? 0,
                    dryRun: dryRun
                )
                logger.d("💾🔁 \(result.message)")
                dto = ToolResult([dryRun ? result.structuredMessage : result.message])
            } catch {
                dto = ToolResult(["Text was not replaced: \(error.localizedDescription)"])
            }
        }
        return dto
    }
}
