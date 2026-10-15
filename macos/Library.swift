import Foundation

struct Game: Codable, Equatable {
    let id: UUID
    var name: String
    var executable: String
    let prefix: String
    let addedAt: Date
    var lastPlayedAt: Date?
    var lastExitCode: Int32?
    var lastLog: String?
    var folderBookmark: Data?
    var engine: String?
}

struct LibraryDocument: Codable {
    var version = 1
    var games: [Game] = []
    var sources: [GameSource] = GameSource.defaults
    enum CodingKeys: String, CodingKey { case version, games, sources }
    init() {}
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        games = try values.decode([Game].self, forKey: .games)
        sources = try values.decodeIfPresent([GameSource].self, forKey: .sources) ?? GameSource.defaults
    }
}

struct GameSource: Codable, Equatable {
    var id: UUID = UUID()
    var name: String
    var url: String
    static var defaults: [GameSource] {
        [GameSource(name: "Steam", url: "https://store.steampowered.com/"),
         GameSource(name: "SteamRIP", url: "https://steamrip.com/"),
         GameSource(name: "Xbox / Game Pass", url: "https://www.xbox.com/xbox-game-pass"),
         GameSource(name: "Xbox Cloud Gaming", url: "https://www.xbox.com/play"),
         GameSource(name: "GOG", url: "https://www.gog.com/"),
         GameSource(name: "Epic Games", url: "https://store.epicgames.com/")]
    }
    static func validURL(_ text: String) -> URL? {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

enum LibraryError: LocalizedError {
    case invalidExecutable, unsupportedArchitecture, invalidLibrary
    var errorDescription: String? {
        switch self {
        case .invalidExecutable: return "Scegli un vero eseguibile Windows con estensione .exe."
        case .unsupportedArchitecture: return "Questo eseguibile non è per Windows x86 o x64."
        case .invalidLibrary: return "La libreria non è valida. Il file originale è stato conservato."
        }
    }
}

final class GameLibrary {
    let root: URL
    private(set) var document: LibraryDocument
    var games: [Game] { document.games }
    var file: URL { root.appendingPathComponent("library.json") }

    init(root: URL = GameLibrary.defaultRoot) throws {
        self.root = root
        let file = root.appendingPathComponent("library.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                let decoded = try JSONDecoder().decode(LibraryDocument.self, from: Data(contentsOf: file))
                guard decoded.version == 1, Set(decoded.games.map(\.id)).count == decoded.games.count,
                      Set(decoded.games.map(\.executable)).count == decoded.games.count,
                      decoded.games.allSatisfy({ $0.prefix.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil }) else {
                    throw LibraryError.invalidLibrary
                }
                self.document = decoded
            } catch { throw LibraryError.invalidLibrary }
        } else { self.document = LibraryDocument() }
    }

    static var defaultRoot: URL {
        if let override = ProcessInfo.processInfo.environment["PROTON4MAC_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Proton4Mac", isDirectory: true)
    }

    static func validate(_ url: URL) throws -> URL {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        guard canonical.pathExtension.lowercased() == "exe" else { throw LibraryError.invalidExecutable }
        let stream = try FileHandle(forReadingFrom: canonical)
        defer { try? stream.close() }
        let header = try stream.read(upToCount: 64) ?? Data()
        guard header.count == 64, header[0] == 0x4d, header[1] == 0x5a else { throw LibraryError.invalidExecutable }
        let offset = header[60..<64].enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * $1.offset) }
        try stream.seek(toOffset: offset)
        let pe = try stream.read(upToCount: 6) ?? Data()
        guard pe.count == 6, pe.prefix(4) == Data([0x50, 0x45, 0, 0]) else { throw LibraryError.invalidExecutable }
        let machine = UInt16(pe[4]) | UInt16(pe[5]) << 8
        guard machine == 0x14c || machine == 0x8664 else { throw LibraryError.unsupportedArchitecture }
        return canonical
    }

    @discardableResult
    func add(_ url: URL) throws -> Game {
        let canonical = try Self.validate(url)
        return try addValidated(canonical)
    }

    // The UI validates on a worker queue before serializing persistence on the
    // main queue. Don't reopen an iCloud-backed executable on the main thread.
    @discardableResult
    func addValidated(_ canonical: URL) throws -> Game {
        if let existing = document.games.first(where: { $0.executable == canonical.path }) { return existing }
        let id = UUID()
        let name = canonical.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
        let metal = root.appendingPathComponent("runtimes/dxmt-v0.80/bin/wine")
        let game = Game(id: id, name: name, executable: canonical.path,
                        prefix: "game-" + id.uuidString.lowercased(), addedAt: Date(),
                        engine: FileManager.default.isExecutableFile(atPath: metal.path) ? "dxmt" : nil)
        var updated = document
        updated.games.append(game)
        try save(updated)
        return game
    }

    func remove(_ id: UUID) throws {
        var updated = document
        updated.games.removeAll { $0.id == id }
        try save(updated)
    }

    func update(_ id: UUID, change: (inout Game) -> Void) throws {
        var updated = document
        guard let index = updated.games.firstIndex(where: { $0.id == id }) else { return }
        change(&updated.games[index])
        try save(updated)
    }

    func setSources(_ sources: [GameSource]) throws {
        guard sources.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && GameSource.validURL($0.url) != nil }) else { throw LibraryError.invalidLibrary }
        var updated = document; updated.sources = sources; try save(updated)
    }

    private func save(_ updated: LibraryDocument) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(updated).write(to: file, options: .atomic)
        document = updated
    }
}
