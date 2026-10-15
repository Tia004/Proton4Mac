import AppKit
import UniformTypeIdentifiers
import CoreServices

final class DropView: NSView {
    var receive: (([URL]) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        let executables = urls.filter { $0.pathExtension.lowercased() == "exe" }
        guard !executables.isEmpty else { return false }
        receive?(executables)
        return true
    }
}

final class GameCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        let icon = NSImageView(image: NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = .controlAccentColor
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        for item in [icon, title, subtitle] { item.translatesAutoresizingMaskIntoConstraints = false; addSubview(item) }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 30), icon.heightAnchor.constraint(equalToConstant: 30),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12), title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12), title.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor), subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor), subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}

final class Launcher: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    var window: NSWindow!
    var library: GameLibrary?
    var filtered: [Game] = []
    var selected: UUID?
    let table = NSTableView()
    let search = NSSearchField()
    let titleLabel = NSTextField(labelWithString: "La tua prossima partita")
    let subtitle = NSTextField(labelWithString: "Aggiungi un gioco Windows per iniziare.")
    let pathLabel = NSTextField(wrappingLabelWithString: "Seleziona direttamente il file .exe del gioco. Proton4Mac conserva il percorso e prepara automaticamente un ambiente dedicato.")
    let status = NSTextField(wrappingLabelWithString: "")
    let count = NSTextField(labelWithString: "LIBRERIA")
    let runButton = NSButton(title: "Avvia gioco", target: nil, action: nil)
    let stopButton = NSButton(title: "Ferma", target: nil, action: nil)
    let logButton = NSButton(title: "Mostra log", target: nil, action: nil)
    let removeButton = NSButton(title: "Rimuovi dalla libreria", target: nil, action: nil)
    let enginePicker = NSPopUpButton(frame: .zero, pullsDown: false)
    var running: [UUID: Process] = [:]
    var folderAccess: [UUID: URL] = [:]
    var authorizing: Set<UUID> = []
    var pending: [URL] = []
    var ready = false
    var positioning = false
    var sourceWindows: [SourcesController] = []
    var registerOnLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = DisplayPolicy.preferred else {
            fputs("Proton4Mac: display Retina del MacBook non disponibile; nessuna finestra aperta.\n", stderr)
            NSApp.terminate(nil)
            return
        }
        do { library = try GameLibrary() } catch { status.stringValue = error.localizedDescription }
        window = NSWindow(contentRect: NSRect(x: screen.visibleFrame.minX + 20, y: screen.visibleFrame.minY + 20, width: 980, height: 650),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false, screen: screen)
        window.title = "Proton4Mac"
        window.isRestorable = false
        window.minSize = NSSize(width: 800, height: 560)
        window.collectionBehavior = [.fullScreenNone]
        window.delegate = self
        buildInterface()
        setupMenu()
        reload()
        DisplayPolicy.place(window, centered: true)
        window.makeKeyAndOrderFront(nil)
        writeWindowState()
        ready = true
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            if let self = self { DisplayPolicy.place(self.window) }
        }
        let urls = pending; pending.removeAll()
        if !urls.isEmpty { importGames(urls, launch: true) }
        if registerOnLaunch { DispatchQueue.main.async { self.associateExecutables() } }
    }

    func buildInterface() {
        let root = DropView(frame: .zero)
        root.receive = { [weak self] urls in self?.importGames(urls, launch: false) }
        window.contentView = root
        let heading = NSTextField(labelWithString: "Proton4Mac")
        heading.font = .systemFont(ofSize: 25, weight: .bold)
        let tagline = NSTextField(labelWithString: "I tuoi giochi Windows. Una libreria sul Mac.")
        tagline.textColor = .secondaryLabelColor
        let add = NSButton(title: "Aggiungi giochi…", target: self, action: #selector(chooseGames))
        add.bezelStyle = .rounded
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        add.imagePosition = .imageLeading
        let headerText = NSStackView(views: [heading, tagline]); headerText.orientation = .vertical; headerText.alignment = .leading; headerText.spacing = 6
        let sources = NSButton(title: "Sorgenti", target: self, action: #selector(showSources))
        sources.bezelStyle = .rounded
        sources.image = NSImage(systemSymbolName: "globe", accessibilityDescription: nil); sources.imagePosition = .imageLeading
        sources.widthAnchor.constraint(equalToConstant: 110).isActive = true
        sources.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let header = NSStackView(views: [headerText, NSView(), sources, add]); header.orientation = .horizontal; header.spacing = 12
        add.widthAnchor.constraint(equalToConstant: 170).isActive = true
        add.heightAnchor.constraint(equalToConstant: 40).isActive = true
        let line = NSBox(); line.boxType = .separator
        let sidebar = NSStackView(); sidebar.orientation = .vertical; sidebar.alignment = .leading; sidebar.spacing = 14
        sidebar.widthAnchor.constraint(equalToConstant: 270).isActive = true
        count.font = .systemFont(ofSize: 11, weight: .semibold); count.textColor = .secondaryLabelColor
        search.placeholderString = "Cerca un gioco"; search.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("game")); table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 65; table.intercellSpacing = NSSize(width: 0, height: 3)
        table.delegate = self; table.dataSource = self; table.style = .fullWidth
        table.target = self; table.doubleAction = #selector(launchSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        sidebar.addArrangedSubview(count); sidebar.addArrangedSubview(search); sidebar.addArrangedSubview(scroll)
        search.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        scroll.widthAnchor.constraint(equalTo: sidebar.widthAnchor).isActive = true
        let divider = NSBox(); divider.boxType = .separator; divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let detail = NSStackView(); detail.orientation = .vertical; detail.alignment = .leading; detail.spacing = 18
        let art = NSView(); art.wantsLayer = true; art.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.08).cgColor; art.layer?.cornerRadius = 18
        let icon = NSImageView(image: NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "Gioco Windows")!)
        icon.contentTintColor = .controlAccentColor; icon.imageScaling = .scaleProportionallyUpOrDown
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 70, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false; art.addSubview(icon)
        NSLayoutConstraint.activate([icon.centerXAnchor.constraint(equalTo: art.centerXAnchor), icon.centerYAnchor.constraint(equalTo: art.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 100), icon.heightAnchor.constraint(equalToConstant: 80)])
        art.heightAnchor.constraint(equalToConstant: 160).isActive = true
        titleLabel.font = .systemFont(ofSize: 27, weight: .bold); titleLabel.lineBreakMode = .byTruncatingTail
        subtitle.font = .systemFont(ofSize: 13); subtitle.textColor = .secondaryLabelColor
        pathLabel.font = .systemFont(ofSize: 12); pathLabel.textColor = .secondaryLabelColor; pathLabel.maximumNumberOfLines = 3
        status.font = .systemFont(ofSize: 12); status.maximumNumberOfLines = 3
        runButton.target = self; runButton.action = #selector(launchSelected); runButton.bezelStyle = .rounded
        runButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil); runButton.imagePosition = .imageLeading
        runButton.keyEquivalent = "\r"; runButton.bezelColor = .controlAccentColor
        runButton.widthAnchor.constraint(equalToConstant: 160).isActive = true; runButton.heightAnchor.constraint(equalToConstant: 42).isActive = true
        stopButton.target = self; stopButton.action = #selector(stopSelected); stopButton.bezelStyle = .rounded
        logButton.target = self; logButton.action = #selector(showLog); logButton.bezelStyle = .rounded
        removeButton.target = self; removeButton.action = #selector(removeSelected); removeButton.bezelStyle = .rounded
        let controls = NSStackView(views: [runButton, stopButton, logButton]); controls.spacing = 10
        let changeExecutable = NSButton(title: "Cambia file .exe…", target: self, action: #selector(changeExecutable))
        changeExecutable.bezelStyle = .rounded
        let manage = NSStackView(views: [changeExecutable, removeButton]); manage.spacing = 8
        enginePicker.addItems(withTitles: ["Grafica: Wine", "Grafica: DXMT · DirectX 11 su Metal", "Grafica: Valve 11 + Metal · sperimentale"])
        enginePicker.target = self; enginePicker.action = #selector(changeEngine)
        enginePicker.toolTip = "Scegli prima del primo avvio. Ogni ambiente conserva il proprio motore."
        for view in [art, titleLabel, subtitle, pathLabel, enginePicker, controls, status, NSView(), manage] { detail.addArrangedSubview(view) }
        for view in [art, titleLabel, subtitle, pathLabel, status] { view.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true }
        let body = NSStackView(views: [sidebar, divider, detail]); body.orientation = .horizontal; body.alignment = .top; body.spacing = 24
        detail.widthAnchor.constraint(equalTo: body.widthAnchor, constant: -319).isActive = true
        sidebar.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
        detail.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
        divider.heightAnchor.constraint(equalTo: body.heightAnchor).isActive = true
        let foot = NSTextField(labelWithString: "Retina del MacBook  ·  Doppio clic su un .exe: aggiunta e avvio automatici")
        foot.font = .systemFont(ofSize: 11); foot.textColor = .secondaryLabelColor
        let layout = NSStackView(views: [header, line, body, foot]); layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 22
        layout.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(layout)
        for view in [header, line, body, foot] { view.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([layout.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24), layout.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24), layout.topAnchor.constraint(equalTo: root.topAnchor, constant: 24), layout.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18)])
    }

    func setupMenu() {
        let main = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Associa i file .exe a Proton4Mac", action: #selector(associateExecutables), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Esci da Proton4Mac", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; main.addItem(item); NSApp.mainMenu = main
    }

    @objc func chooseGames() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .executable]
        panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.prompt = "Aggiungi alla libreria"; panel.message = "Scegli uno o più file .exe. Non serve spostare o copiare il gioco."
        panel.beginSheetModal(for: window) { [weak self] response in
            if response == .OK { self?.importGames(panel.urls, launch: false) }
        }
    }

    @objc func showSources() {
        guard let library = library, DisplayPolicy.preferred != nil else { return }
        let controller = SourcesController(library: library); sourceWindows.append(controller); controller.showWindow(nil)
        controller.onClose = { [weak self, weak controller] in self?.sourceWindows.removeAll { $0 === controller } }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if ready { importGames(urls, launch: true) } else { pending += urls }
    }

    func importGames(_ urls: [URL], launch: Bool) {
        guard let library = library else { return }
        // Serialize imports and writes on the main queue; file validation runs off it.
        for url in urls {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let validation = Result { try GameLibrary.validate(url) }
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    do {
                        let canonical = try validation.get()
                        let game = try library.addValidated(canonical)
                        self.selected = game.id; self.search.stringValue = ""; self.reload()
                        self.status.stringValue = "Gioco aggiunto. Premi Avvia gioco quando vuoi."
                        DisplayPolicy.place(self.window); self.window.makeKeyAndOrderFront(nil)
                        if launch { self.launch(game) }
                    } catch { self.status.stringValue = error.localizedDescription }
                }
            }
        }
    }

    func reload() {
        filtered = library?.games.filter { search.stringValue.isEmpty || $0.name.localizedCaseInsensitiveContains(search.stringValue) } ?? []
        count.stringValue = "LIBRERIA  ·  \(library?.games.count ?? 0)"
        table.reloadData()
        if let selected = selected, let row = filtered.firstIndex(where: { $0.id == selected }) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        else if !filtered.isEmpty { selected = filtered[0].id; table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false) }
        else { selected = nil; table.deselectAll(nil) }
        refreshDetail()
    }
    func controlTextDidChange(_ obj: Notification) { reload() }
    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = GameCell(frame: .zero); let game = filtered[row]; cell.title.stringValue = game.name
        cell.subtitle.stringValue = running[game.id] == nil ? "Windows · pronto all’avvio" : "Sessione aperta"
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0 && table.selectedRow < filtered.count { selected = filtered[table.selectedRow].id }
        refreshDetail()
    }
    var current: Game? { library?.games.first { $0.id == selected } }
    func refreshDetail() {
        let game = current
        titleLabel.stringValue = game?.name ?? "La tua prossima partita"
        subtitle.stringValue = game == nil ? "Aggiungi un .exe o trascinalo in questa finestra." : "Windows  ·  Ambiente dedicato  ·  Display Retina"
        pathLabel.stringValue = game?.executable ?? "Puoi aggiungere più giochi, ritrovarli qui e avviarli con un clic. Anche il doppio clic nel Finder li aggiunge automaticamente."
        let busy = game.map { running[$0.id] != nil } ?? false
        runButton.isEnabled = game != nil && !busy; stopButton.isEnabled = busy
        runButton.title = busy ? "Sessione aperta" : "Avvia gioco"
        logButton.isEnabled = game?.lastLog != nil; removeButton.isEnabled = game != nil && !busy
        enginePicker.selectItem(at: game?.engine == "valve11" ? 2 : (game?.engine == "dxmt" ? 1 : 0))
        let initialized = game.map { entry in library.map { FileManager.default.fileExists(atPath: $0.root.appendingPathComponent("prefixes/" + entry.prefix).path) } ?? false } ?? false
        // A launcher executable can exit while its Windows child keeps running.
        // Keep the prefix-scoped stop action available for those sessions too.
        stopButton.isEnabled = busy || initialized
        enginePicker.isEnabled = game != nil && !busy && !initialized
        enginePicker.item(at: 1)?.isEnabled = dxmtWine.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
        enginePicker.item(at: 2)?.isEnabled = valveWine.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false
    }

    var dxmtWine: URL? { library?.root.appendingPathComponent("runtimes/dxmt-v0.80/bin/wine") }
    var valveWine: URL? { library?.root.appendingPathComponent("runtimes/valve11-dxmt-v0.80/bin/wine") }
    @objc func changeEngine() {
        guard let game = current else { return }
        do { try library?.update(game.id) { $0.engine = enginePicker.indexOfSelectedItem == 2 ? "valve11" : (enginePicker.indexOfSelectedItem == 1 ? "dxmt" : nil) }; status.stringValue = "Motore selezionato per il primo avvio." }
        catch { status.stringValue = error.localizedDescription }
    }

    @objc func launchSelected() { if let game = current { launch(game) } }
    func launch(_ game: Game) {
        guard running[game.id] == nil, !authorizing.contains(game.id), let library = library else { return }
        guard DisplayPolicy.preferred != nil else { status.stringValue = "Riapri il display Retina del MacBook per avviare il gioco."; return }
        let folder = URL(fileURLWithPath: game.executable).deletingLastPathComponent()
        let home = FileManager.default.homeDirectoryForCurrentUser
        let protected = ["Downloads", "Documents", "Desktop"].contains { folder.path.hasPrefix(home.appendingPathComponent($0).path + "/") || folder.path == home.appendingPathComponent($0).path }
        if protected && folderAccess[game.id] == nil {
            if let bookmark = game.folderBookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], bookmarkDataIsStale: &stale), !stale, url.startAccessingSecurityScopedResource() {
                    folderAccess[game.id] = url
                }
            }
            if folderAccess[game.id] == nil { authorizeFolder(game, folder: folder); return }
        }
        let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let executable = python, let script = Bundle.main.url(forResource: "proton4mac", withExtension: "py") else { folderAccess.removeValue(forKey: game.id)?.stopAccessingSecurityScopedResource(); status.stringValue = "Python 3 non trovato."; return }
        do {
            guard FileManager.default.fileExists(atPath: game.executable) else { throw CocoaError(.fileNoSuchFile) }
            let logs = library.root.appendingPathComponent("logs"); try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("\(game.id.uuidString)-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log)
            let task = Process(); task.executableURL = URL(fileURLWithPath: executable)
            task.standardInput = FileHandle.nullDevice
            var arguments = [script.path, "--root", library.root.path]
            if game.engine == "dxmt", let wine = dxmtWine { arguments += ["--wine", wine.path] }
            if game.engine == "valve11", let wine = valveWine { arguments += ["--wine", wine.path] }
            task.arguments = arguments + ["run", "--prefix", game.prefix, "--display", "builtin", game.executable]
            task.standardOutput = output; task.standardError = output
            task.terminationHandler = { [weak self] finished in
                try? output.close()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.running.removeValue(forKey: game.id)
                    self.folderAccess.removeValue(forKey: game.id)?.stopAccessingSecurityScopedResource()
                    do { try self.library?.update(game.id) { $0.lastExitCode = finished.terminationStatus } }
                    catch { self.status.stringValue = error.localizedDescription }
                    if self.selected == game.id {
                        self.status.stringValue = finished.terminationStatus == 0 ? "Sessione terminata." : "Il gioco si è chiuso con un errore. Mostra log per i dettagli."
                    }
                    self.reload()
                }
            }
            try library.update(game.id) { $0.lastPlayedAt = Date(); $0.lastLog = log.path; $0.lastExitCode = nil }
            try task.run(); running[game.id] = task
            status.stringValue = "Avvio di \(game.name)… La prima volta viene preparato l’ambiente Windows."
            reload()
        } catch { folderAccess.removeValue(forKey: game.id)?.stopAccessingSecurityScopedResource(); status.stringValue = "Avvio non riuscito: \(error.localizedDescription)" }
    }

    func authorizeFolder(_ game: Game, folder: URL) {
        authorizing.insert(game.id)
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = folder; panel.prompt = "Consenti questa cartella"
        panel.message = "macOS richiede l’accesso alla cartella del gioco e ai suoi file. Seleziona la cartella \(folder.lastPathComponent). La scelta viene ricordata."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }; self.authorizing.remove(game.id)
            guard response == .OK, let url = panel.url?.standardizedFileURL.resolvingSymlinksInPath() else { self.status.stringValue = "Avvio annullato: accesso alla cartella non concesso."; return }
            guard folder.path == url.path || folder.path.hasPrefix(url.path + "/") else { self.status.stringValue = "Scegli la cartella che contiene il gioco."; return }
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                try self.library?.update(game.id) { $0.folderBookmark = bookmark }
                _ = url.startAccessingSecurityScopedResource(); self.folderAccess[game.id] = url
                if let updated = self.library?.games.first(where: { $0.id == game.id }) { self.launch(updated) }
            } catch { self.status.stringValue = "Accesso alla cartella non salvato: \(error.localizedDescription)" }
        }
    }

    @objc func stopSelected() {
        guard let game = current, let library = library,
              let script = Bundle.main.url(forResource: "proton4mac", withExtension: "py") else { return }
        let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"].first { FileManager.default.isExecutableFile(atPath: $0) }
        guard let python = python else { return }
        let task = Process(); task.executableURL = URL(fileURLWithPath: python)
        task.arguments = [script.path, "--root", library.root.path, "stop", "--prefix", game.prefix]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        task.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self = self, self.selected == game.id else { return }
                self.status.stringValue = finished.terminationStatus == 0 ? "Sessione chiusa." : "Chiusura non riuscita. Controlla il log del gioco."
            }
        }
        do { try task.run(); status.stringValue = "Chiusura della sessione…" } catch { status.stringValue = error.localizedDescription }
    }

    @objc func removeSelected() {
        guard let game = current, running[game.id] == nil else { return }
        do { try library?.remove(game.id); selected = nil; reload(); status.stringValue = "Rimosso dalla libreria. File del gioco e salvataggi conservati." }
        catch { status.stringValue = error.localizedDescription }
    }

    @objc func changeExecutable() {
        guard let game = current, running[game.id] == nil else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .executable]
        panel.prompt = "Usa questo .exe"
        panel.message = "Scegli l’eseguibile installato. L’ambiente Windows e i salvataggi vengono conservati."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self = self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let validation = Result { try GameLibrary.validate(url) }
                DispatchQueue.main.async {
                    do {
                        let canonical = try validation.get()
                        guard self.library?.games.contains(where: { $0.id != game.id && $0.executable == canonical.path }) != true else {
                            self.status.stringValue = "Questo eseguibile è già presente nella libreria."; return
                        }
                        try self.library?.update(game.id) { $0.executable = canonical.path; $0.folderBookmark = nil; $0.name = canonical.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ") }
                        self.reload(); self.status.stringValue = "Eseguibile aggiornato. Ambiente e salvataggi conservati."
                    } catch { self.status.stringValue = error.localizedDescription }
                }
            }
        }
    }

    @objc func showLog() {
        guard let log = current?.lastLog else { return }
        let data = (try? Data(contentsOf: URL(fileURLWithPath: log))) ?? Data()
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Log di avvio"
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 60, width: 688, height: 350)); scroll.hasVerticalScroller = true
        let text = NSTextView(frame: scroll.bounds); text.isEditable = false; text.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        text.string = String(decoding: data.suffix(128000), as: UTF8.self); scroll.documentView = text
        panel.contentView?.addSubview(scroll)
        let close = NSButton(title: "Chiudi", target: self, action: #selector(closeLog(_:))); close.frame = NSRect(x: 604, y: 14, width: 100, height: 32)
        panel.contentView?.addSubview(close); window.beginSheet(panel)
    }
    @objc func closeLog(_ sender: NSButton) { if let sheet = sender.window { window.endSheet(sheet) } }

    @objc func associateExecutables() {
        DisplayPolicy.place(window); window.makeKeyAndOrderFront(nil)
        registerExecutableHandler { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let handler = NSWorkspace.shared.urlForApplication(toOpen: UTType(filenameExtension: "exe")!)
                let registered = handler.flatMap { Bundle(url: $0)?.bundleIdentifier } == "org.proton4mac.launcher"
                self.status.stringValue = registered ? "Doppio clic .exe associato a Proton4Mac." : "Associazione non riuscita: \(error?.localizedDescription ?? "macOS non ha applicato la modifica")"
                if self.registerOnLaunch { printJSON(["registered": registered, "handler": handler?.path ?? "", "error": error?.localizedDescription ?? ""]); exit(registered ? 0 : 1) }
            }
        }
    }
    func windowDidMove(_ notification: Notification) { constrainWindow() }
    func windowDidResize(_ notification: Notification) { constrainWindow() }
    func constrainWindow() {
        guard !positioning else { return }; positioning = true; DisplayPolicy.place(window); positioning = false
        writeWindowState()
    }
    func writeWindowState() {
        guard let window = window, let library = library else { return }
        let screen = window.screen
        let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
        let state: [String: Any] = ["display_id": id, "display_name": screen?.localizedName ?? "",
                                    "builtin": CGDisplayIsBuiltin(id) != 0, "x": window.frame.minX,
                                    "y": window.frame.minY, "width": window.frame.width, "height": window.frame.height]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: .prettyPrinted) {
            try? FileManager.default.createDirectory(at: library.root, withIntermediateDirectories: true)
            try? data.write(to: library.root.appendingPathComponent("window-state.json"), options: .atomic)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { running.isEmpty }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag, DisplayPolicy.preferred != nil { DisplayPolicy.place(window); window.makeKeyAndOrderFront(nil) }
        return true
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if running.isEmpty { return .terminateNow }
        status.stringValue = "Chiudi i giochi o premi Ferma prima di uscire."
        DisplayPolicy.place(window); window.makeKeyAndOrderFront(nil)
        return .terminateCancel
    }
}

func registerExecutableHandler(completion: @escaping (Error?) -> Void) {
    let registration = LSRegisterURL(Bundle.main.bundleURL as CFURL, true)
    guard registration == noErr else { completion(NSError(domain: NSOSStatusErrorDomain, code: Int(registration))); return }
    guard let type = UTType(filenameExtension: "exe") else { completion(LibraryError.invalidExecutable); return }
    if let current = NSWorkspace.shared.urlForApplication(toOpen: type), Bundle(url: current)?.bundleIdentifier == "org.proton4mac.launcher" { completion(nil); return }
    NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in completion(error) }
}

func printJSON(_ value: Any) {
    if let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
}

@main
struct Proton4MacApplication {
static func main() {
let app = NSApplication.shared
let arguments = CommandLine.arguments
if arguments.contains("--list-displays") {
    printJSON(DisplayPolicy.inventory)
} else if arguments.contains("--registration-status") {
    let type = UTType(filenameExtension: "exe")?.identifier ?? "com.microsoft.windows-executable"
    let handler = LSCopyDefaultRoleHandlerForContentType(type as CFString, .all)?.takeRetainedValue() as String?
    printJSON(["type": type, "handler": handler ?? "", "bundle": Bundle.main.bundleURL.path,
               "application": NSWorkspace.shared.urlForApplication(toOpen: UTType(filenameExtension: "exe")!)?.path ?? ""])
} else if let index = arguments.firstIndex(of: "--library-add"), arguments.count > index + 1 {
    do { let library = try GameLibrary(); let game = try library.add(URL(fileURLWithPath: arguments[index + 1])); printJSON(["id": game.id.uuidString, "name": game.name, "count": library.games.count]) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if arguments.contains("--library-list") {
    do { let library = try GameLibrary(); printJSON(library.games.map { ["id": $0.id.uuidString, "name": $0.name, "path": $0.executable] }) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else if let index = arguments.firstIndex(of: "--library-remove"), arguments.count > index + 1, let id = UUID(uuidString: arguments[index + 1]) {
    do { let library = try GameLibrary(); try library.remove(id); printJSON(["removed": id.uuidString, "count": library.games.count]) }
    catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
} else {
    let delegate = Launcher(); app.delegate = delegate
    delegate.registerOnLaunch = arguments.contains("--register-exe-handler")
    app.setActivationPolicy(.regular)
    app.run()
}
}
}
