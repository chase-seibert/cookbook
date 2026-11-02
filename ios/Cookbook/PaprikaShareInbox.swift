import Foundation

enum PaprikaShareInbox {
    static let appGroupIdentifier = "group.com.cseibert.cookbook"
    private static let directoryName = "PendingPaprikaImports"
    private static let maximumFileSize = 100 * 1024 * 1024
    private static let maximumWebCaptureBytes = 180_000

    struct WebCapture: Codable, Sendable {
        let url: String
        let title: String
        let text: String
        let imageURL: String?
        let capturedAt: Date
    }

    static func enqueueWebCapture(_ capture: WebCapture) throws -> URL {
        guard let url = URL(string: capture.url), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              capture.url.utf8.count <= 4_096, capture.title.utf8.count <= 2_000,
              (capture.imageURL?.utf8.count ?? 0) <= 8_192,
              capture.text.utf8.count <= maximumWebCaptureBytes else { throw ShareInboxError.invalidWebCapture }
        let directory = try pendingDirectory()
        let destination = directory.appendingPathComponent("\(UUID().uuidString).webrecipecapture")
        try JSONEncoder().encode(capture).write(to: destination, options: .atomic)
        return destination
    }

    static func readWebCapture(at url: URL) throws -> WebCapture {
        let directory = try pendingDirectory()
        guard url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/"), url.pathExtension == "webrecipecapture" else {
            throw ShareInboxError.invalidWebCapture
        }
        let data = try Data(contentsOf: url)
        guard data.count <= maximumWebCaptureBytes + 8_192 else { throw ShareInboxError.invalidWebCapture }
        return try JSONDecoder().decode(WebCapture.self, from: data)
    }

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
            .filter { ["paprikarecipe", "paprikarecipes", "webrecipecapture"].contains($0.pathExtension.lowercased()) }
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
        case invalidWebCapture

        var errorDescription: String? {
            switch self {
            case .fileTooLarge: "This Paprika file exceeds the 100 MiB import limit."
            case .unsupportedFile: "Choose a Paprika .paprikarecipe or .paprikarecipes file."
            case .sharedContainerUnavailable: "Cookbook could not access its shared import folder."
            case .invalidWebCapture: "Safari did not provide a valid recipe page capture. Try sharing the page again."
            }
        }
    }
}
