import Foundation

@main
struct LibraryTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("p4m-library-test-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        var passed = 0
        func check(_ condition: Bool, _ description: String) {
            guard condition else { fputs("FAILED: \(description)\n", stderr); exit(1) }
            passed += 1
        }
        func executable(_ name: String, machine: UInt16 = 0x8664) throws -> URL {
            var bytes = Data(repeating: 0, count: 70)
            bytes[0] = 0x4d; bytes[1] = 0x5a; bytes[60] = 64
            bytes[64] = 0x50; bytes[65] = 0x45; bytes[68] = UInt8(machine & 255); bytes[69] = UInt8(machine >> 8)
            let url = root.appendingPathComponent(name); try bytes.write(to: url); return url
        }
        let storage = root.appendingPathComponent("data")
        let library = try GameLibrary(root: storage)
        let file = try executable("My_Game.exe")
        let game = try library.add(file)
        check(game.name == "My Game" && library.games.count == 1, "add and readable name")
        check(try library.add(file).id == game.id, "duplicate does not add an entry")
        let link = root.appendingPathComponent("Alias.exe"); try fm.createSymbolicLink(at: link, withDestinationURL: file)
        check(try library.add(link).id == game.id, "symlink canonicalization")
        let reloaded = try GameLibrary(root: storage)
        check(reloaded.games[0].id == game.id && reloaded.games[0].prefix == game.prefix, "persistence and stable prefix")
        let second = try library.add(executable("Second.exe"))
        check(second.prefix != game.prefix, "isolated environments")
        let invalid = root.appendingPathComponent("fake.exe"); try Data("not a PE".utf8).write(to: invalid)
        do { _ = try library.add(invalid); check(false, "reject malformed executable") } catch { passed += 1 }
        let arm = try executable("arm.exe", machine: 0xaa64)
        do { _ = try library.add(arm); check(false, "reject unsupported architecture") } catch { passed += 1 }
        try library.update(game.id) { $0.name = "Renamed"; $0.lastExitCode = 0 }
        check(library.games.first!.name == "Renamed" && library.games.first!.prefix == game.prefix, "metadata update preserves environment")
        try library.update(game.id) { $0.engine = "dxmt"; $0.folderBookmark = Data([1, 2, 3]) }
        let settings = try GameLibrary(root: storage).games.first!
        check(settings.engine == "dxmt" && settings.folderBookmark == Data([1, 2, 3]) && settings.prefix == game.prefix, "engine and folder grant survive reload without changing prefix")
        try library.remove(second.id)
        check(fm.fileExists(atPath: second.executable) && library.games.count == 1, "remove keeps game files")
        var sources = library.document.sources
        sources.append(GameSource(name: "Custom", url: "https://example.com/")); try library.setSources(sources)
        check(try GameLibrary(root: storage).document.sources.last!.name == "Custom", "custom sources persist")
        check(GameSource.validURL("javascript:alert(1)") == nil && GameSource.validURL("https://user:secret@example.com") == nil, "source URL policy")
        let engine = storage.appendingPathComponent("runtimes/dxmt-v0.80/bin/wine")
        try fm.createDirectory(at: engine.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("test engine".utf8).write(to: engine); try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: engine.path)
        let automatic = try library.add(executable("Automatic.exe"))
        check(automatic.engine == "dxmt" && library.games.first!.prefix == game.prefix, "new games select installed Metal engine without migrating existing environments")
        let bad = storage.appendingPathComponent("library.json")
        let corruption = Data("{broken".utf8); try corruption.write(to: bad)
        do { _ = try GameLibrary(root: storage); check(false, "corruption rejected") } catch { passed += 1 }
        check(try Data(contentsOf: bad) == corruption, "corrupted library left intact")
        print("Library tests: \(passed) passed")
    }
}
