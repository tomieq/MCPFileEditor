import CryptoKit
import Foundation

struct FileMetadata: Encodable {
    let filepath: String
    let exists: Bool
    let type: String?
    let byteSize: Int?
    let modificationDate: Date?
    let creationDate: Date?
    let encoding: String?
    let isBinary: Bool?
    let sha256: String?
}

struct FileInspector {
    func inspect(url: URL, filepath: String, includeHash: Bool) throws -> FileMetadata {
        let manager = FileManager.default
        guard manager.fileExists(atPath: url.path) else {
            return FileMetadata(filepath: filepath,
                                exists: false,
                                type: nil,
                                byteSize: nil,
                                modificationDate: nil,
                                creationDate: nil,
                                encoding: nil,
                                isBinary: nil,
                                sha256: nil)
        }

        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey,
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey
        ])
        let type: String
        if values.isDirectory == true {
            type = "directory"
        } else if values.isSymbolicLink == true {
            type = "symlink"
        } else if values.isRegularFile == true {
            type = "file"
        } else {
            type = "other"
        }

        let data = values.isRegularFile == true ? try Data(contentsOf: url) : nil
        let isUTF8 = data.map { String(data: $0, encoding: .utf8) != nil }
        return FileMetadata(filepath: filepath,
                            exists: true,
                            type: type,
                            byteSize: values.fileSize,
                            modificationDate: values.contentModificationDate,
                            creationDate: values.creationDate,
                            encoding: isUTF8 == true ? "utf-8" : nil,
                            isBinary: data.map { $0.contains(0) || isUTF8 == false },
                            sha256: includeHash && values.isRegularFile == true ? digest(url) : nil)
    }

    private func digest(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try? handle.read(upToCount: 64 * 1024), data.isEmpty.not {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private extension Bool {
    var not: Bool { !self }
}
