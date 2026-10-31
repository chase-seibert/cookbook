import Foundation

enum PaprikaShareInbox {
    static let appGroupIdentifier = "group.com.cseibert.cookbook"
    private static let directoryName = "PendingPaprikaImports"
    private static let maximumFileSize = 100 * 1024 * 1024

    static func enqueue(_ data: Data) throws -> URL {
        guard data.count <= maximumFileSize else { throw ShareInboxError.fileTooLarge }

        let fileExtension: String
        if data.starts(with: [0x1f, 0x8b]) {
            fileExtension = "paprikarecipe"
        } else if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) {
            fileExtension = "paprikarecipes"
        } else {
            throw ShareInboxError.unsupportedFile
        }

        let directory = try pendingDirectory()
        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        try data.write(to: destination, options: .atomic)
        return destination
    }

    static func isSupportedPayload(_ data: Data) -> Bool {
        data.starts(with: [0x1f, 0x8b]) || data.starts(with: [0x50, 0x4b, 0x03, 0x04])
    }

    static func nextPendingURL() -> URL? {
        guard let directory = try? pendingDirectory(),
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return nil }

        return urls
            .filter { ["paprikarecipe", "paprikarecipes"].contains($0.pathExtension.lowercased()) }
            .sorted {
                let first = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let second = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return first < second
            }
            .first
    }

    static func removeIfPending(_ url: URL) {
        guard let directory = try? pendingDirectory() else { return }
        let expectedPrefix = directory.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(expectedPrefix) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func pendingDirectory() throws -> URL {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw ShareInboxError.sharedContainerUnavailable
        }
        let directory = group.appendingPathComponent(directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    enum ShareInboxError: LocalizedError {
        case fileTooLarge
        case unsupportedFile
        case sharedContainerUnavailable

        var errorDescription: String? {
            switch self {
            case .fileTooLarge: "This Paprika file exceeds the 100 MiB import limit."
            case .unsupportedFile: "Choose a Paprika .paprikarecipe or .paprikarecipes file."
            case .sharedContainerUnavailable: "Cookbook could not access its shared import folder."
            }
        }
    }
}
