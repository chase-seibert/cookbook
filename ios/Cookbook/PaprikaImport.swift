import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import UIKit
import CryptoKit

enum PaprikaFileType {
    static let supported: [UTType] = [
        UTType(filenameExtension: "paprikarecipe", conformingTo: .data) ?? .data,
        UTType(filenameExtension: "paprikarecipes", conformingTo: .data) ?? .data
    ]
}

struct PaprikaImportDraft: Identifiable, Sendable {
    let uid: String
    let recipe: Recipe
    let sourceCategories: [String]
    let photoData: Data?
    var id: String { uid }
}

struct PaprikaImportReviewSession: Identifiable {
    let id = UUID()
    let drafts: [PaprikaImportDraft]
}

enum PaprikaImportError: LocalizedError {
    case unsupportedFile
    case invalidArchive(String)
    case archiveTooLarge
    case noRecipes
    case invalidRecipe(String)
    case imageWriteFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "Choose a Paprika .paprikarecipe or .paprikarecipes file."
        case .invalidArchive(let reason): "Could not read this Paprika file: \(reason)"
        case .archiveTooLarge: "This Paprika file exceeds the supported size limits."
        case .noRecipes: "This Paprika file does not contain any recipes."
        case .invalidRecipe(let reason): "A recipe in this Paprika file is invalid: \(reason)"
        case .imageWriteFailed: "A recipe photo could not be saved. No recipes were added."
        }
    }
}

enum PaprikaImportReader {
    private static let maximumArchiveBytes = 100 * 1024 * 1024
    private static let maximumEntries = 2_500
    private static let maximumEntryBytes = 24 * 1024 * 1024
    private static let maximumTotalRecipeBytes = 80 * 1024 * 1024

    static func parse(data: Data) throws -> [PaprikaImportDraft] {
        guard data.count <= maximumArchiveBytes else { throw PaprikaImportError.archiveTooLarge }
        let payloads: [(String, Data)]
        if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) {
            payloads = try zipEntries(data)
        } else if data.starts(with: [0x1f, 0x8b]) {
            payloads = [("recipe.paprikarecipe", data)]
        } else {
            throw PaprikaImportError.unsupportedFile
        }
        guard !payloads.isEmpty else { throw PaprikaImportError.noRecipes }
        var drafts: [PaprikaImportDraft] = []
        var seenUIDs = Set<String>()
        var totalBytes = 0
        for (name, compressed) in payloads {
            guard compressed.count <= maximumEntryBytes else { throw PaprikaImportError.archiveTooLarge }
            totalBytes += compressed.count
            guard totalBytes <= maximumTotalRecipeBytes else { throw PaprikaImportError.archiveTooLarge }
            let json: Data
            do { json = try inflate(compressed, windowBits: 15 + 16, expectedSize: gzipSize(compressed)) }
            catch { throw PaprikaImportError.invalidRecipe("\(name) is not a valid gzip-compressed recipe.") }
            guard json.count <= maximumEntryBytes else { throw PaprikaImportError.archiveTooLarge }
            let draft = try decodeRecipe(json, filename: name)
            guard seenUIDs.insert(draft.uid.lowercased()).inserted else {
                throw PaprikaImportError.invalidRecipe("the Paprika UID \(draft.uid) appears more than once.")
            }
            drafts.append(draft)
        }
        return drafts
    }

    private static func decodeRecipe(_ data: Data, filename: String) throws -> PaprikaImportDraft {
        guard let object = try? JSONSerialization.jsonObject(with: data), let fields = object as? [String: Any] else {
            throw PaprikaImportError.invalidRecipe("\(filename) does not contain a JSON recipe.")
        }
        func string(_ key: String) -> String { (fields[key] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        let uid = string("uid")
        let title = string("name")
        guard !uid.isEmpty else { throw PaprikaImportError.invalidRecipe("\(filename) has no Paprika UID.") }
        guard !title.isEmpty else { throw PaprikaImportError.invalidRecipe("\(filename) has no usable title.") }

        let categoryValues = (fields["categories"] as? [String] ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let category = categoryValues.first ?? ""
        let ingredientLines = string("ingredients").components(separatedBy: .newlines).map(cleanLine).filter { !$0.isEmpty }
        let directionLines = string("directions").components(separatedBy: #"\n\s*\n"#).map(cleanLine).filter { !$0.isEmpty }
        let notes = string("notes").components(separatedBy: #"\n\s*\n"#).map(cleanLine).filter { !$0.isEmpty }
        let ingredients = ingredientLines.enumerated().map { index, line in
            RecipeIngredient(id: "paprika-ingredient-\(index + 1)", quantity: "", name: line, groceryName: line, staple: false, excludeFromGroceries: false)
        }
        let steps = directionLines.enumerated().map { index, line in
            RecipeStep(id: "paprika-step-\(index + 1)", sectionTitle: "", instruction: line, originalInstruction: line, ingredientIDs: [], durationMinutes: nil, active: true)
        }
        let reference = string("source_url")
        let recipe = Recipe(
            id: "paprika:\(uid.lowercased())",
            title: title,
            category: category,
            collectionTitle: nil,
            sourceFile: "Paprika import",
            sourceSection: category,
            introduction: string("description"),
            ingredients: ingredients,
            ingredientGroups: nil,
            steps: steps,
            contentOrder: nil,
            tips: notes,
            healthierOptions: [],
            thumbnailAsset: nil,
            labelIDs: ["paprika-import"],
            provenance: RecipeProvenance(type: .paprikaImport, name: string("source").isEmpty ? "Paprika" : string("source"), reference: reference.isEmpty ? nil : reference),
            menuDescription: nil,
            menuPairings: nil,
            servings: string("servings").isEmpty ? nil : string("servings")
        )
        let photo = imageData(string("photo_data")) ?? imageData(string("photo_large"))
        return PaprikaImportDraft(uid: uid, recipe: recipe, sourceCategories: categoryValues, photoData: photo)
    }

    private static func cleanLine(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func imageData(_ encoded: String) -> Data? {
        guard !encoded.isEmpty, let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters), data.count <= maximumEntryBytes else { return nil }
        let isJPEG = data.starts(with: [0xff, 0xd8, 0xff])
        let isPNG = data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
        let isGIF = data.starts(with: Array("GIF8".utf8))
        return (isJPEG || isPNG || isGIF) ? data : nil
    }

    private struct Entry {
        let name: String
        let method: UInt16
        let flags: UInt16
        let crc32: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localOffset: Int
    }

    private static func zipEntries(_ data: Data) throws -> [(String, Data)] {
        guard let eocd = (max(0, data.count - 65_557)..<data.count).reversed().first(where: { read32(data, $0) == 0x06054b50 }) else {
            throw PaprikaImportError.invalidArchive("the ZIP directory is missing.")
        }
        let count = Int(read16(data, eocd + 10))
        let directorySize = Int(read32(data, eocd + 12))
        let directoryOffset = Int(read32(data, eocd + 16))
        guard count > 0, count <= maximumEntries, directoryOffset >= 0, directorySize >= 0,
              directoryOffset + directorySize <= eocd, read16(data, eocd + 4) == 0, read16(data, eocd + 6) == 0,
              read16(data, eocd + 8) == UInt16(count) else {
            throw PaprikaImportError.invalidArchive("the ZIP directory is invalid or uses an unsupported ZIP64 layout.")
        }
        var offset = directoryOffset
        var entries: [Entry] = []
        for _ in 0..<count {
            guard read32(data, offset) == 0x02014b50 else { throw PaprikaImportError.invalidArchive("a ZIP directory entry is malformed.") }
            let flags = read16(data, offset + 8)
            let method = read16(data, offset + 10)
            let crc = read32(data, offset + 16)
            let compressed = Int(read32(data, offset + 20))
            let uncompressed = Int(read32(data, offset + 24))
            let nameLength = Int(read16(data, offset + 28))
            let extraLength = Int(read16(data, offset + 30))
            let commentLength = Int(read16(data, offset + 32))
            let localOffset = Int(read32(data, offset + 42))
            let end = offset + 46 + nameLength + extraLength + commentLength
            guard end <= directoryOffset + directorySize, compressed != Int(UInt32.max), uncompressed != Int(UInt32.max), localOffset != Int(UInt32.max), compressed <= maximumEntryBytes, uncompressed <= maximumEntryBytes else {
                throw PaprikaImportError.archiveTooLarge
            }
            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            if name.lowercased().hasSuffix(".paprikarecipe") && !name.hasSuffix("/") {
                guard flags & 0x0001 == 0, method == 0 || method == 8 else { throw PaprikaImportError.invalidArchive("\(name) is encrypted or uses an unsupported ZIP method.") }
                entries.append(Entry(name: name, method: method, flags: flags, crc32: crc, compressedSize: compressed, uncompressedSize: uncompressed, localOffset: localOffset))
            }
            offset = end
        }
        guard offset == directoryOffset + directorySize else { throw PaprikaImportError.invalidArchive("the ZIP directory size does not match its entries.") }
        guard !entries.isEmpty else { throw PaprikaImportError.noRecipes }
        return try entries.map { entry in
            let start = entry.localOffset
            guard read32(data, start) == 0x04034b50 else { throw PaprikaImportError.invalidArchive("\(entry.name) has a malformed local header.") }
            let nameLength = Int(read16(data, start + 26))
            let extraLength = Int(read16(data, start + 28))
            let body = start + 30 + nameLength + extraLength
            guard body >= 0, body + entry.compressedSize <= data.count else { throw PaprikaImportError.invalidArchive("\(entry.name) is truncated.") }
            let compressed = data.subdata(in: body..<(body + entry.compressedSize))
            let output = entry.method == 0 ? compressed : try inflate(compressed, windowBits: -15, expectedSize: entry.uncompressedSize)
            guard output.count == entry.uncompressedSize, crc32(output) == entry.crc32 else { throw PaprikaImportError.invalidArchive("\(entry.name) failed its size or checksum check.") }
            return (entry.name, output)
        }
    }

    private static func inflate(_ input: Data, windowBits: Int32, expectedSize: Int?) throws -> Data {
        let size = expectedSize ?? maximumEntryBytes
        guard size > 0, size <= maximumEntryBytes, input.count <= maximumEntryBytes else { throw PaprikaImportError.archiveTooLarge }
        var output = Data(count: size)
        let outputCapacity = size
        var outputLength = 0
        let success = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                cookbook_inflate(inputBytes.bindMemory(to: UInt8.self).baseAddress, input.count,
                                 outputBytes.bindMemory(to: UInt8.self).baseAddress, outputCapacity,
                                 &outputLength, windowBits)
            }
        }
        guard success != 0, outputLength <= size else { throw PaprikaImportError.invalidArchive("compressed data could not be decompressed.") }
        output.count = outputLength
        return output
    }

    private static func gzipSize(_ data: Data) -> Int? {
        guard data.count >= 18 else { return nil }
        let value = UInt32(data[data.count - 4]) | UInt32(data[data.count - 3]) << 8 | UInt32(data[data.count - 2]) << 16 | UInt32(data[data.count - 1]) << 24
        return value == 0 ? nil : Int(value)
    }

    private static func read16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private static func read32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2]) << 16 | UInt32(data[offset + 3]) << 24
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return crc ^ UInt32.max
    }
}

private extension String {
    func components(separatedBy pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [self] }
        let range = NSRange(startIndex..., in: self)
        let pieces = regex.matches(in: self, range: range)
        var result: [String] = []
        var cursor = startIndex
        for piece in pieces {
            guard let matchRange = Range(piece.range, in: self) else { continue }
            result.append(String(self[cursor..<matchRange.lowerBound]))
            cursor = matchRange.upperBound
        }
        result.append(String(self[cursor...]))
        return result
    }
}

enum PaprikaExportError: LocalizedError {
    case noRecipes
    case invalidRecipe(String)
    case unsupportedPhoto(String)
    case compressionFailed
    case archiveTooLarge
    case archiveFailed

    var errorDescription: String? {
        switch self {
        case .noRecipes: "There are no recipes to export."
        case .invalidRecipe(let title): "Could not encode \(title) as a Paprika recipe."
        case .unsupportedPhoto(let title): "The cover photo for \(title) is unreadable or is not a supported JPEG, PNG, or GIF image."
        case .compressionFailed: "Could not compress a Paprika recipe."
        case .archiveTooLarge: "The Paprika export exceeds the supported file size."
        case .archiveFailed: "Could not create the Paprika collection archive."
        }
    }
}

struct PaprikaExportItem: Sendable {
    let recipe: Recipe
    let uid: String
    let photoData: Data?

    init(recipe: Recipe, uid: String? = nil, photoData: Data? = nil) {
        self.recipe = recipe
        self.uid = uid ?? Self.stableUID(for: recipe.id)
        self.photoData = photoData
    }

    private static func stableUID(for recipeID: String) -> String {
        var bytes = Array(SHA256.hash(data: Data("cookbook-paprika:\(recipeID)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02X", $0) }
        return "\(hex[0...3].joined())-\(hex[4...5].joined())-\(hex[6...7].joined())-\(hex[8...9].joined())-\(hex[10...15].joined())"
    }
}

enum PaprikaExporter {
    private static let maximumRecipeBytes = 24 * 1024 * 1024
    private static let maximumCollectionBytes = 100 * 1024 * 1024

    static func writeRecipe(_ item: PaprikaExportItem, to url: URL) throws {
        let compressed = try compressedRecipe(item)
        try compressed.write(to: url, options: .atomic)
    }

    static func writeCollection(_ items: [PaprikaExportItem], to url: URL) throws {
        guard !items.isEmpty else { throw PaprikaExportError.noRecipes }
        let uids = items.map { $0.uid.lowercased() }
        guard Set(uids).count == uids.count else { throw PaprikaExportError.archiveFailed }

        var entries: [(name: String, data: Data, crc: UInt32, offset: UInt32)] = []
        var archive = Data()
        var usedNames = Set<String>()
        for item in items {
            let recipe = try compressedRecipe(item)
            guard recipe.count <= maximumRecipeBytes, archive.count + recipe.count <= maximumCollectionBytes else { throw PaprikaExportError.archiveTooLarge }
            let name = filename(for: item, usedNames: &usedNames)
            guard let nameData = name.data(using: .utf8), nameData.count <= Int(UInt16.max), archive.count <= Int(UInt32.max) else { throw PaprikaExportError.archiveTooLarge }
            let offset = UInt32(archive.count)
            let crc = crc32(recipe)
            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0x0021))
            archive.appendLE(crc)
            archive.appendLE(UInt32(recipe.count))
            archive.appendLE(UInt32(recipe.count))
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))
            archive.append(nameData)
            archive.append(recipe)
            entries.append((name, recipe, crc, offset))
        }

        let directoryOffset = archive.count
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            archive.appendLE(UInt32(0x02014b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0x0021))
            archive.appendLE(entry.crc)
            archive.appendLE(UInt32(entry.data.count))
            archive.appendLE(UInt32(entry.data.count))
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt32(0))
            archive.appendLE(entry.offset)
            archive.append(nameData)
        }
        let directorySize = archive.count - directoryOffset
        guard entries.count <= Int(UInt16.max), archive.count <= maximumCollectionBytes,
              directoryOffset <= Int(UInt32.max), directorySize <= Int(UInt32.max) else { throw PaprikaExportError.archiveTooLarge }
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(directorySize))
        archive.appendLE(UInt32(directoryOffset))
        archive.appendLE(UInt16(0))
        try archive.write(to: url, options: .atomic)
    }

    static func temporaryURL(extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Cookbook-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    @MainActor static func item(for recipe: Recipe, importedRecords: [ImportedPaprikaRecipe], photos: [RecipePhoto]) throws -> PaprikaExportItem {
        let uid = importedRecords.first(where: { $0.id == recipe.id })?.paprikaUID
        var photoData: Data?
        if let cover = photos.first(where: { $0.recipeID == recipe.id && $0.isCover }) {
            let source = UserFiles.url(for: cover.relativePath)
            guard let raw = try? Data(contentsOf: source), let image = UIImage(data: raw), let jpeg = image.jpegData(compressionQuality: 0.9) else {
                throw PaprikaExportError.unsupportedPhoto(recipe.title)
            }
            photoData = jpeg
        } else if let asset = recipe.thumbnailAsset,
                  let url = Bundle.main.url(forResource: asset, withExtension: nil, subdirectory: "Thumbnails"),
                  let image = UIImage(contentsOfFile: url.path),
                  let jpeg = image.jpegData(compressionQuality: 0.9) {
            photoData = jpeg
        }
        return PaprikaExportItem(recipe: recipe, uid: uid, photoData: photoData)
    }

    private static func compressedRecipe(_ item: PaprikaExportItem) throws -> Data {
        if let photo = item.photoData, !isSupportedImage(photo) { throw PaprikaExportError.unsupportedPhoto(item.recipe.title) }
        let directions = item.recipe.steps.map { step in
            [step.sectionTitle.isEmpty ? nil : step.sectionTitle, step.originalInstruction]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        let ingredients = item.recipe.ingredients.map { ingredient in
            [ingredient.quantity, ingredient.name].filter { !$0.isEmpty }.joined(separator: " ")
        }.joined(separator: "\n")
        let provenance = item.recipe.provenance
        let object: [String: Any] = [
            "uid": item.uid,
            "name": item.recipe.title,
            "ingredients": ingredients,
            "directions": directions,
            "description": item.recipe.introduction,
            "notes": item.recipe.tips.joined(separator: "\n\n"),
            "servings": item.recipe.servings ?? "",
            "categories": [item.recipe.category],
            "source": provenance?.name ?? "",
            "source_url": provenance?.reference ?? "",
            "photo_data": item.photoData?.base64EncodedString() ?? ""
        ]
        let json: Data
        do { json = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .fragmentsAllowed]) }
        catch { throw PaprikaExportError.invalidRecipe(item.recipe.title) }
        guard json.count <= maximumRecipeBytes else { throw PaprikaExportError.archiveTooLarge }
        let capacity = json.count + max(1024, json.count / 1000 + 128)
        var compressed = Data(count: capacity)
        var outputLength = 0
        let success = json.withUnsafeBytes { input in
            compressed.withUnsafeMutableBytes { output in
                cookbook_gzip(input.bindMemory(to: UInt8.self).baseAddress, json.count,
                              output.bindMemory(to: UInt8.self).baseAddress, capacity, &outputLength)
            }
        }
        guard success != 0, outputLength <= capacity else { throw PaprikaExportError.compressionFailed }
        compressed.count = outputLength
        return compressed
    }

    private static func isSupportedImage(_ data: Data) -> Bool {
        data.starts(with: [0xff, 0xd8, 0xff]) || data.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) || data.starts(with: Array("GIF8".utf8))
    }

    private static func filename(for item: PaprikaExportItem, usedNames: inout Set<String>) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(item.recipe.title.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = String((cleaned.isEmpty ? "Recipe" : cleaned).prefix(72))
        let uidPart = String(item.uid.replacingOccurrences(of: "-", with: "").prefix(8))
        var candidate = "\(base)-\(uidPart).paprikarecipe"
        var counter = 2
        while !usedNames.insert(candidate.lowercased()).inserted {
            candidate = "\(base)-\(uidPart)-\(counter).paprikarecipe"
            counter += 1
        }
        return candidate
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return crc ^ UInt32.max
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}

enum RecipeDocumentExportError: LocalizedError {
    case noRecipes
    case archiveTooLarge
    case archiveFailed

    var errorDescription: String? {
        switch self {
        case .noRecipes: "There are no active recipes to export."
        case .archiveTooLarge: "The Markdown export is too large to package."
        case .archiveFailed: "Could not create the Markdown archive."
        }
    }
}

enum RecipeDocumentExporter {
    private struct ArchiveEntry {
        let name: String
        let data: Data
        let crc: UInt32
        let offset: UInt32
    }

    static func temporaryURL(extension fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Cookbook-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    static func temporaryURL(for recipe: Recipe, extension fileExtension: String) -> URL {
        var usedNames = Set<String>()
        let archiveFilename = filename(for: recipe, usedNames: &usedNames)
        let baseName = URL(fileURLWithPath: archiveFilename).deletingPathExtension().lastPathComponent
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    static func writeMarkdown(_ recipe: Recipe, to url: URL) throws {
        try Data(markdown(for: recipe).utf8).write(to: url, options: .atomic)
    }

    static func writeHTML(_ recipe: Recipe, to url: URL) throws {
        try Data(html(for: recipe).utf8).write(to: url, options: .atomic)
    }

    static func writeMarkdownArchive(_ recipes: [Recipe], to url: URL) throws {
        guard !recipes.isEmpty else { throw RecipeDocumentExportError.noRecipes }
        guard recipes.count <= Int(UInt16.max) else { throw RecipeDocumentExportError.archiveTooLarge }

        var archive = Data()
        var entries: [ArchiveEntry] = []
        var usedNames = Set<String>()
        for recipe in recipes {
            let contents = Data(markdown(for: recipe).utf8)
            let name = filename(for: recipe, usedNames: &usedNames)
            let nameData = Data(name.utf8)
            guard nameData.count <= Int(UInt16.max), contents.count <= Int(UInt32.max), archive.count <= Int(UInt32.max) else {
                throw RecipeDocumentExportError.archiveTooLarge
            }
            let offset = UInt32(archive.count)
            let crc = crc32(contents)
            archive.appendLE(UInt32(0x04034b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0x0021))
            archive.appendLE(crc)
            archive.appendLE(UInt32(contents.count))
            archive.appendLE(UInt32(contents.count))
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))
            archive.append(nameData)
            archive.append(contents)
            entries.append(ArchiveEntry(name: name, data: contents, crc: crc, offset: offset))
        }

        let directoryOffset = archive.count
        for entry in entries {
            let nameData = Data(entry.name.utf8)
            archive.appendLE(UInt32(0x02014b50))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(20))
            archive.appendLE(UInt16(0x0800))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0x0021))
            archive.appendLE(entry.crc)
            archive.appendLE(UInt32(entry.data.count))
            archive.appendLE(UInt32(entry.data.count))
            archive.appendLE(UInt16(nameData.count))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt16(0))
            archive.appendLE(UInt32(0))
            archive.appendLE(entry.offset)
            archive.append(nameData)
        }
        let directorySize = archive.count - directoryOffset
        guard archive.count <= Int(UInt32.max), directoryOffset <= Int(UInt32.max), directorySize <= Int(UInt32.max) else {
            throw RecipeDocumentExportError.archiveTooLarge
        }
        archive.appendLE(UInt32(0x06054b50))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(0))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt16(entries.count))
        archive.appendLE(UInt32(directorySize))
        archive.appendLE(UInt32(directoryOffset))
        archive.appendLE(UInt16(0))
        do { try archive.write(to: url, options: .atomic) }
        catch { throw RecipeDocumentExportError.archiveFailed }
    }

    static func writeHTMLCookbook(_ recipes: [Recipe], to url: URL) throws {
        guard !recipes.isEmpty else { throw RecipeDocumentExportError.noRecipes }
        let links = recipes.map { recipe in
            "<li><a href=\"#\(htmlAttribute(recipe.id))\">\(htmlText(recipe.title))</a></li>"
        }.joined(separator: "\n")
        let documents = recipes.map { htmlArticle(for: $0, includeDocument: false) }.joined(separator: "\n")
        let document = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>Cookbook</title>
          <style>
            :root { color-scheme: light dark; font: 16px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; }
            body { max-width: 48rem; margin: 0 auto; padding: 2rem 1.25rem; }
            nav { border-bottom: 1px solid #8886; padding-bottom: 1.5rem; margin-bottom: 2rem; }
            article { padding: 1rem 0 2rem; border-bottom: 1px solid #8886; scroll-margin-top: 1rem; }
            li { margin: .25rem 0; } .quantity { white-space: nowrap; margin-right: .5rem; color: #888; }
          </style>
        </head>
        <body>
          <h1>Cookbook</h1>
          <nav aria-label="Recipes"><h2>Recipes</h2><ol>\(links)</ol></nav>
          \(documents)
        </body>
        </html>
        """
        try Data(document.utf8).write(to: url, options: .atomic)
    }

    static func markdown(for recipe: Recipe) -> String {
        var sections = ["---", "format: cookbook-recipe/v1", "id: \(yamlScalar(recipe.id))", "---", "", "# \(markdownText(recipe.title))"]
        let introduction = recipe.introduction.trimmingCharacters(in: .whitespacesAndNewlines)
        let servings = recipe.servings?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !introduction.isEmpty || !servings.isEmpty {
            let paragraphs = [introduction, servings.isEmpty ? "" : "Servings: \(servings)"]
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            sections += ["", blockquote(label: "Introduction", text: paragraphs)]
        }
        if !recipe.ingredients.isEmpty {
            sections += ["", "## Ingredients", "", "| Quantity | Ingredient |", "|---|---|"]
            sections += recipe.ingredients.map {
                let columns = NormalizedRecipeColumns(quantity: $0.quantity, ingredient: $0.name)
                return RecipeIngredientTextNormalizer.markdownRow(for: columns)
            }
        }
        var currentSection: String?
        for (index, step) in recipe.steps.enumerated() where !step.originalInstruction.isEmpty {
            let title = step.sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, title != currentSection {
                sections += ["", "## \(markdownText(title))"]
            } else if index == 0 || currentSection == nil {
                sections += ["", "## Instructions"]
            }
            sections += ["", markdownText(step.originalInstruction)]
            currentSection = title.isEmpty ? currentSection : title
        }
        for tip in recipe.tips where !tip.isEmpty { sections += ["", blockquote(label: "Tip", text: tip)] }
        for note in recipe.healthierOptions where !note.isEmpty { sections += ["", blockquote(label: "Healthier option", text: note)] }
        return sections.joined(separator: "\n") + "\n"
    }

    static func html(for recipe: Recipe) -> String { htmlArticle(for: recipe, includeDocument: true) }

    private static func htmlArticle(for recipe: Recipe, includeDocument: Bool) -> String {
        let ingredientList = recipe.ingredients.map { ingredient in
            "<li>\(ingredient.quantity.isEmpty ? "" : "<span class=\"quantity\">\(htmlText(ingredient.quantity))</span>")\(htmlText(ingredient.name))</li>"
        }.joined(separator: "\n")
        var steps = ""
        var currentSection: String?
        for step in recipe.steps where !step.originalInstruction.isEmpty {
            let title = step.sectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, title != currentSection { steps += "<h3>\(htmlText(title))</h3>\n" }
            steps += "<p>\(htmlText(step.originalInstruction).replacingOccurrences(of: "\n", with: "<br>"))</p>\n"
            currentSection = title.isEmpty ? currentSection : title
        }
        let notes = recipe.tips.map { "<p><strong>Tip:</strong> \(htmlText($0))</p>" }
            + recipe.healthierOptions.map { "<p><strong>Healthier option:</strong> \(htmlText($0))</p>" }
        let article = """
        <article id="\(htmlAttribute(recipe.id))">
          <h2>\(htmlText(recipe.title))</h2>
          \(recipe.introduction.isEmpty ? "" : "<p class=\"introduction\">\(htmlText(recipe.introduction))</p>")
          \(recipe.servings.map { "<p><strong>Servings:</strong> \(htmlText($0))</p>" } ?? "")
          \(recipe.ingredients.isEmpty ? "" : "<h3>Ingredients</h3><ul>\(ingredientList)</ul>")
          \(steps.isEmpty ? "" : "<h3>Instructions</h3>\(steps)")
          \(notes.joined(separator: "\n"))
        </article>
        """
        guard includeDocument else { return article }
        return """
        <!doctype html>
        <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>\(htmlText(recipe.title))</title>
        <style>:root { color-scheme: light dark; font: 16px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; } body { max-width: 48rem; margin: 0 auto; padding: 2rem 1.25rem; } .quantity { white-space: nowrap; margin-right: .5rem; color: #888; }</style>
        </head><body><main>\(article.replacingOccurrences(of: "<h2>", with: "<h1>").replacingOccurrences(of: "</h2>", with: "</h1>"))</main></body></html>
        """
    }

    private static func filename(for recipe: Recipe, usedNames: inout Set<String>) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let normalized = recipe.title.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        let slug = String(normalized.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .split(separator: "-").joined(separator: "-").prefix(64)
        let idSlug = recipe.id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }.map(String.init).joined()
        let base = slug.isEmpty ? "Recipe" : String(slug)
        let suffix = String(idSlug.trimmingCharacters(in: CharacterSet(charactersIn: "-" )).prefix(40))
        var candidate = "\(base)-\(suffix).md"
        var counter = 2
        while !usedNames.insert(candidate.lowercased()).inserted {
            candidate = "\(base)-\(suffix)-\(counter).md"
            counter += 1
        }
        return candidate
    }

    private static func yamlScalar(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"").replacingOccurrences(of: "\n", with: "\\n") + "\""
    }

    private static func markdownText(_ value: String) -> String {
        let escapable = "\\`*_{}[]()#+-.!>|~"
        var result = ""
        for scalar in value.unicodeScalars {
            if scalar.isASCII, escapable.unicodeScalars.contains(scalar) { result.append("\\") }
            result.append(String(scalar))
        }
        return result
    }

    private static func blockquote(label: String, text: String) -> String {
        let lines = text.components(separatedBy: "\n").enumerated().map { index, line in
            index == 0 ? "> **\(label):** \(markdownText(line))" : "> \(markdownText(line))"
        }
        return lines.joined(separator: "\n")
    }

    private static func htmlText(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func htmlAttribute(_ value: String) -> String { htmlText(value) }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc = UInt32.max
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = (crc & 1) == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
        }
        return crc ^ UInt32.max
    }
}

enum PaprikaImportStore {
    static let fileImportLabelID = "paprika-file-import"

    static func normalizedTitle(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    @MainActor static func add(_ drafts: [PaprikaImportDraft], selectedUIDs: Set<String>, duplicateUIDs: Set<String>, to container: ModelContainer) throws -> PaprikaImportSummary {
        let context = ModelContext(container)
        try RecipeCategoryStore.seedIfNeeded(in: context)
        let categories = try context.fetch(FetchDescriptor<RecipeCategory>()).sorted { $0.order < $1.order }
        let settings = try context.fetch(FetchDescriptor<RecipeCategorySettings>()).first
        guard let defaultCategory = categories.first(where: { $0.id == settings?.defaultCategoryID }) ?? categories.first else {
            throw RecipeCategoryError.lastCategory
        }
        let existing = try context.fetch(FetchDescriptor<ImportedPaprikaRecipe>())
        let runs = try context.fetch(FetchDescriptor<PaprikaImportRun>())
        let now = Date()
        let dayKey = localDayKey(for: now)
        let runNumber = runs.filter { $0.dayKey == dayKey }.map(\.runNumber).max().map { $0 + 1 } ?? 1
        let runID = UUID().uuidString
        let runLabelID = String(format: "paprika-run-%@-%02d", dayKey, runNumber)
        var knownUIDs = Set(existing.map { $0.paprikaUID.lowercased() })
        var knownTitles = Set(CookbookCatalog.bundled.recipes.map { normalizedTitle($0.title) })
        knownTitles.formUnion(existing.compactMap(\.recipe).map { normalizedTitle($0.title) })
        var additions: [(draft: PaprikaImportDraft, duplicate: Bool)] = []
        var skipped: [PaprikaSkippedRecipe] = []
        for draft in drafts {
            let uid = draft.uid.lowercased()
            let title = normalizedTitle(draft.recipe.title)
            let sameID = knownUIDs.contains(uid)
            let sameTitle = knownTitles.contains(title)
            let isDuplicate = sameID || sameTitle
            guard selectedUIDs.contains(draft.uid) else {
                if isDuplicate || duplicateUIDs.contains(draft.uid) {
                    let reason = sameID && sameTitle ? "Matching Paprika ID and recipe name" : (sameID ? "Matching Paprika ID" : (sameTitle ? "Matching recipe name" : "Duplicate in this import"))
                    skipped.append(PaprikaSkippedRecipe(uid: draft.uid, title: draft.recipe.title, reason: reason))
                }
                continue
            }
            guard !isDuplicate || duplicateUIDs.contains(draft.uid) else {
                let reason = sameID && sameTitle ? "Matching Paprika ID and recipe name" : (sameID ? "Matching Paprika ID" : "Matching recipe name")
                skipped.append(PaprikaSkippedRecipe(uid: draft.uid, title: draft.recipe.title, reason: reason))
                continue
            }
            knownUIDs.insert(uid)
            knownTitles.insert(title)
            additions.append((draft, isDuplicate))
        }
        if !additions.isEmpty {
            let filesDirectory = UserFiles.directory.appendingPathComponent("PaprikaImports", isDirectory: true)
            try FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        }
        var writtenFiles: [URL] = []
        var importedIDs: [String] = []
        do {
            try context.transaction {
                for addition in additions {
                    let draft = addition.draft
                    let id = addition.duplicate && existing.contains(where: { $0.paprikaUID.lowercased() == draft.uid.lowercased() })
                        ? "\(draft.recipe.id):copy:\(UUID().uuidString)"
                        : draft.recipe.id
                    let matchedCategory = RecipeCategoryStore.match(sourceNames: draft.sourceCategories, categories: categories) ?? defaultCategory
                    guard categories.contains(where: { $0.id == matchedCategory.id }) else { throw RecipeCategoryError.missingCategory }
                    let recipe = draft.recipe.replacingCategory(matchedCategory.name).addingBrowseLabels([fileImportLabelID, runLabelID], id: id)
                    let encoded = try JSONEncoder().encode(recipe)
                    context.insert(ImportedPaprikaRecipe(id: recipe.id, paprikaUID: draft.uid, recipeData: encoded, importedAt: now, paprikaImportRunID: runID))
                    context.insert(RecipeCategoryAssignment(recipeID: recipe.id, categoryID: matchedCategory.id))
                    importedIDs.append(recipe.id)
                    if let photo = draft.photoData {
                        let ext = photo.starts(with: [0xff, 0xd8, 0xff]) ? "jpg" : (photo.starts(with: [0x89, 0x50, 0x4e, 0x47]) ? "png" : "gif")
                        let relativePath = "PaprikaImports/\(UUID().uuidString).\(ext)"
                        let url = UserFiles.url(for: relativePath)
                        do { try photo.write(to: url, options: .atomic) }
                        catch { throw PaprikaImportError.imageWriteFailed }
                        writtenFiles.append(url)
                        context.insert(RecipePhoto(recipeID: recipe.id, relativePath: relativePath, isCover: true))
                    }
                }
                let importedIDsData = try JSONEncoder().encode(importedIDs)
                let skippedData = try JSONEncoder().encode(skipped)
                context.insert(PaprikaImportRun(id: runID, dayKey: dayKey, runNumber: runNumber, labelID: runLabelID, createdAt: now, importedRecipeIDsData: importedIDsData, skippedRecipesData: skippedData, importedCount: importedIDs.count, skippedCount: skipped.count))
            }
            return PaprikaImportSummary(runID: runID, labelID: runLabelID, displayName: "Paprika file · \(now.formatted(date: .abbreviated, time: .shortened)) · run \(runNumber)", importedTitles: additions.map { $0.draft.recipe.title }, skippedRecipes: skipped)
        } catch {
            writtenFiles.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
    }

    @MainActor static func undo(_ run: PaprikaImportRun, in context: ModelContext) throws {
        guard run.undoneAt == nil else { return }
        let runID = run.id
        let descriptor = FetchDescriptor<ImportedPaprikaRecipe>(predicate: #Predicate { $0.paprikaImportRunID == runID && $0.deletedAt == nil })
        let records = try context.fetch(descriptor)
        let now = Date()
        try context.transaction {
            records.forEach { $0.deletedAt = now }
            run.undoneAt = now
        }
    }

    @MainActor static func undo(runID: String, in context: ModelContext) throws {
        guard let run = try context.fetch(FetchDescriptor<PaprikaImportRun>()).first(where: { $0.id == runID }) else { return }
        try undo(run, in: context)
    }

    private static func localDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }
}

private extension Recipe {
    func replacingCategory(_ value: String) -> Recipe {
        Recipe(id: id, title: title, category: value, collectionTitle: collectionTitle, sourceFile: sourceFile, sourceSection: sourceSection, introduction: introduction, ingredients: ingredients, ingredientGroups: ingredientGroups, steps: steps, contentOrder: contentOrder, tips: tips, healthierOptions: healthierOptions, thumbnailAsset: thumbnailAsset, labelIDs: labelIDs, provenance: provenance, menuDescription: menuDescription, menuPairings: menuPairings, servings: servings)
    }
}

struct PaprikaImportSummary: Hashable, Identifiable, Sendable {
    let runID: String
    let labelID: String
    let displayName: String
    let wasUndone: Bool
    let importedTitles: [String]
    let skippedRecipes: [PaprikaSkippedRecipe]
    var runLabelName: String {
        let components = labelID.split(separator: "-")
        guard components.count >= 4 else { return labelID }
        return "Paprika import · \(components[2]) · run \(components[3])"
    }
    init(runID: String, labelID: String, displayName: String, importedTitles: [String], skippedRecipes: [PaprikaSkippedRecipe], wasUndone: Bool = false) {
        self.runID = runID
        self.labelID = labelID
        self.displayName = displayName
        self.wasUndone = wasUndone
        self.importedTitles = importedTitles
        self.skippedRecipes = skippedRecipes
    }
    var id: String { runID }
}

private extension Recipe {
    func addingBrowseLabels(_ labels: [String], id: String? = nil) -> Recipe {
        var labelIDs = browseLabelIDs
        for label in labels where !labelIDs.contains(label) { labelIDs.append(label) }
        return Recipe(id: id ?? self.id, title: title, category: category, collectionTitle: collectionTitle, sourceFile: sourceFile, sourceSection: sourceSection, introduction: introduction, ingredients: ingredients, ingredientGroups: ingredientGroups, steps: steps, contentOrder: contentOrder, tips: tips, healthierOptions: healthierOptions, thumbnailAsset: thumbnailAsset, labelIDs: labelIDs, provenance: provenance, menuDescription: menuDescription, menuPairings: menuPairings, servings: servings)
    }
}

struct PaprikaImportReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: PaprikaImportReviewSession
    @Query private var importedRecords: [ImportedPaprikaRecipe]
    @Query(sort: \RecipeCategory.order) private var categories: [RecipeCategory]
    @Query private var categorySettings: [RecipeCategorySettings]
    @State private var selectedUIDs: Set<String>
    @State private var previewDraft: PaprikaImportDraft?
    @State private var alertMessage: String?
    @State private var completedSummary: PaprikaImportSummary?
    @State private var didInitializeSelection = false

    init(session: PaprikaImportReviewSession) {
        self.session = session
        _selectedUIDs = State(initialValue: Set(session.drafts.map(\.uid)))
    }

    private var existingUIDs: Set<String> { Set(importedRecords.map { $0.paprikaUID.lowercased() }) }
    private var existingTitles: Set<String> {
        Set(CookbookCatalog.bundled.recipes.map { PaprikaImportStore.normalizedTitle($0.title) })
            .union(importedRecords.compactMap(\.recipe).map { PaprikaImportStore.normalizedTitle($0.title) })
    }
    private var duplicateUIDs: Set<String> {
        var knownUIDs = existingUIDs
        var knownTitles = existingTitles
        var duplicates = Set<String>()
        for draft in session.drafts {
            let title = PaprikaImportStore.normalizedTitle(draft.recipe.title)
            guard !knownUIDs.contains(draft.uid.lowercased()), !knownTitles.contains(title) else {
                duplicates.insert(draft.uid)
                continue
            }
            knownUIDs.insert(draft.uid.lowercased())
            knownTitles.insert(title)
        }
        return duplicates
    }
    private var selectedCandidates: [PaprikaImportDraft] { session.drafts.filter { selectedUIDs.contains($0.uid) } }
    private var defaultCategory: RecipeCategory? {
        categories.first(where: { $0.id == categorySettings.first?.defaultCategoryID }) ?? categories.sorted { $0.order < $1.order }.first
    }
    private func destinationCategory(for draft: PaprikaImportDraft) -> RecipeCategory? {
        RecipeCategoryStore.match(sourceNames: draft.sourceCategories, categories: categories) ?? defaultCategory
    }
    private func destinationText(for draft: PaprikaImportDraft) -> String {
        let destination = destinationCategory(for: draft)?.name ?? "No category available"
        if let source = draft.sourceCategories.first { return "Paprika: \(source) → \(destination)" }
        return "No Paprika category → \(destination)"
    }
    private var isSingle: Bool { session.drafts.count == 1 }
    private var primaryActionTitle: String {
        guard isSingle, let draft = session.drafts.first, duplicateUIDs.contains(draft.uid) else { return isSingle ? "Import Recipe" : "Import Selected" }
        return selectedUIDs.contains(draft.uid) ? "Import Anyway" : "Skip Duplicate"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let completedSummary {
                    PaprikaImportSummaryContent(summary: completedSummary)
                } else if isSingle, let draft = session.drafts.first {
                    VStack(spacing: 12) {
                        if duplicateUIDs.contains(draft.uid) {
                            Label("This recipe matches one in your library. It will be skipped unless you select Import Anyway.", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                        }
                        Label(destinationText(for: draft), systemImage: "folder")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal)
                        PaprikaRecipePreview(draft: draft)
                        selectionRow(for: draft)
                    }
                } else {
                    List {
                        Section {
                            HStack {
                                Text("\(selectedUIDs.count) selected").font(.subheadline.weight(.medium))
                                Spacer()
                                Button("Select All") { selectedUIDs = Set(session.drafts.map(\.uid)) }
                                Button("Deselect All") { selectedUIDs.removeAll() }
                            }
                        }
                        let ready = session.drafts.filter { !duplicateUIDs.contains($0.uid) }
                        let duplicates = session.drafts.filter { duplicateUIDs.contains($0.uid) }
                        Section("Ready to Import (\(ready.count))") {
                            ForEach(ready) { draft in recipeRow(draft) }
                        }
                        if !duplicates.isEmpty {
                            Section {
                                Label("These match recipes already in your library and will be skipped unless you select them to import anyway.", systemImage: "exclamationmark.triangle.fill")
                                    .font(.subheadline.weight(.medium)).foregroundStyle(.orange)
                                ForEach(duplicates) { draft in recipeRow(draft) }
                            } header: {
                                Text("Duplicates (\(duplicates.count))")
                            }
                        }
                    }
                }
            }
            .navigationTitle(completedSummary == nil ? (isSingle ? "Review Recipe" : "Review Recipes") : "Import Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(completedSummary == nil ? "Cancel" : "Done") { dismiss() } }
                if completedSummary == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(primaryActionTitle) { addSelected() }
                            .disabled(selectedCandidates.isEmpty && duplicateUIDs.isEmpty)
                    }
                }
            }
            .sheet(item: $previewDraft) { draft in NavigationStack { PaprikaRecipePreview(draft: draft).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { previewDraft = nil } } } } }
            .onAppear {
                if !didInitializeSelection {
                    selectedUIDs.subtract(duplicateUIDs)
                    didInitializeSelection = true
                }
            }
            .alert("Paprika import", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("OK") { alertMessage = nil; if alertMessage == nil { dismiss() } }
            } message: { Text(alertMessage ?? "") }
        }
    }

    private func recipeRow(_ draft: PaprikaImportDraft) -> some View {
        HStack(spacing: 8) {
            Button { previewDraft = draft } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.recipe.title).font(.headline).foregroundStyle(.primary)
                        Text("\(destinationText(for: draft)) · \(draft.recipe.ingredients.count) ingredients").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            selectionRow(for: draft)
        }
    }

    private func selectionRow(for draft: PaprikaImportDraft) -> some View {
        Button { toggle(draft) } label: {
            Label(selectedUIDs.contains(draft.uid) ? "Selected" : "Select", systemImage: checkboxSymbol(for: draft))
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(checkboxLabel(for: draft))
    }

    private func toggle(_ draft: PaprikaImportDraft) {
        if selectedUIDs.contains(draft.uid) { selectedUIDs.remove(draft.uid) } else { selectedUIDs.insert(draft.uid) }
    }

    private func checkboxSymbol(for draft: PaprikaImportDraft) -> String {
        selectedUIDs.contains(draft.uid) ? "checkmark.circle.fill" : "circle"
    }

    private func checkboxLabel(for draft: PaprikaImportDraft) -> String {
        selectedUIDs.contains(draft.uid) ? "Deselect \(draft.recipe.title)" : (duplicateUIDs.contains(draft.uid) ? "Import duplicate \(draft.recipe.title) anyway" : "Select \(draft.recipe.title)")
    }

    private func addSelected() {
        do {
            completedSummary = try PaprikaImportStore.add(session.drafts, selectedUIDs: selectedUIDs, duplicateUIDs: duplicateUIDs, to: modelContext.container)
        } catch { alertMessage = "Could not add the selected recipes. No recipes were added. \(error.localizedDescription)" }
    }
}

struct PaprikaImportSummaryContent: View {
    @Environment(\.modelContext) private var modelContext
    let summary: PaprikaImportSummary
    @State private var confirmingUndo = false
    @State private var undoError: String?
    @State private var wasUndone: Bool

    init(summary: PaprikaImportSummary) {
        self.summary = summary
        _wasUndone = State(initialValue: summary.wasUndone)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(summary.displayName).font(.headline).foregroundStyle(.secondary)
                Text("\(summary.importedTitles.count) imported · \(summary.skippedRecipes.count) skipped")
                    .font(.title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Labels applied").font(.headline)
                    Text("Paprika file · \(summary.runLabelName)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !summary.importedTitles.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Imported").font(.headline)
                        ForEach(Array(summary.importedTitles.enumerated()), id: \.offset) { _, title in
                            Label(title, systemImage: "checkmark.circle.fill").font(.subheadline)
                        }
                    }
                }
                if !summary.skippedRecipes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Skipped").font(.headline)
                        ForEach(summary.skippedRecipes) { skipped in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skipped.title).font(.subheadline.weight(.medium))
                                Text(skipped.reason).font(.caption).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if summary.importedTitles.count > 0 {
                    NavigationLink {
                        RecipeBrowserView(importRunLabelID: summary.labelID, showingDeletedRecipes: wasUndone, managesNavigationStack: false, screenTitle: wasUndone ? "Deleted recipes" : "Imported recipes")
                    } label: {
                        Label(wasUndone ? "View deleted recipes from this import" : "View recipes from this import", systemImage: "line.3.horizontal.decrease.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if !wasUndone && !summary.importedTitles.isEmpty {
                    Button("Undo this import", systemImage: "arrow.uturn.backward", role: .destructive) { confirmingUndo = true }
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if wasUndone {
                    Label("This import has been undone", systemImage: "checkmark.circle").foregroundStyle(.secondary)
                }
            }.padding()
        }
        .confirmationDialog("Undo this Paprika import?", isPresented: $confirmingUndo, titleVisibility: .visible) {
            Button("Undo import", role: .destructive) {
                do {
                    try PaprikaImportStore.undo(runID: summary.runID, in: modelContext)
                    wasUndone = true
                } catch { undoError = "Could not undo this import: \(error.localizedDescription)" }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The \(summary.importedTitles.count) recipes from this run will move to Deleted recipes. You can restore them individually.")
        }
        .alert("Paprika import", isPresented: Binding(get: { undoError != nil }, set: { if !$0 { undoError = nil } })) {
            Button("OK") { undoError = nil }
        } message: { Text(undoError ?? "") }
    }
}

private struct PaprikaRecipePreview: View {
    let draft: PaprikaImportDraft

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(draft.recipe.title).font(.system(size: 30, weight: .semibold, design: .serif))
                if let imageData = draft.photoData, let image = UIImage(data: imageData) {
                    Image(uiImage: image).resizable().scaledToFill().frame(maxHeight: 250).clipped().clipShape(RoundedRectangle(cornerRadius: 16))
                }
                if !draft.recipe.introduction.isEmpty { Text(draft.recipe.introduction).foregroundStyle(.secondary) }
                if let servings = draft.recipe.servings, !servings.isEmpty { LabeledContent("Servings", value: servings) }
                Text("Ingredients").font(.title3.weight(.semibold))
                ForEach(draft.recipe.ingredients) { ingredient in Text(ingredient.name).frame(maxWidth: .infinity, alignment: .leading) }
                Text("Instructions").font(.title3.weight(.semibold)).padding(.top, 6)
                ForEach(Array(draft.recipe.steps.enumerated()), id: \.element.id) { index, step in
                    HStack(alignment: .top, spacing: 10) { Text("\(index + 1).").foregroundStyle(.secondary); Text(step.originalInstruction) }
                }
                if !draft.recipe.tips.isEmpty {
                    Text("Notes").font(.title3.weight(.semibold)).padding(.top, 6)
                    ForEach(draft.recipe.tips, id: \.self) { Text($0) }
                }
            }.padding()
        }
    }
}
