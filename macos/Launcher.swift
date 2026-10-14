import AppKit
import UniformTypeIdentifiers

final class Launcher: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var path = NSTextField(string: "")
    var prefix = NSTextField(string: "default")
    var status = NSTextField(labelWithString: "Seleziona un gioco o un installer Windows (.exe).")
    var runButton = NSButton(title: "Avvia", target: nil, action: nil)
    var chooseButton = NSButton(title: "Scegli file…", target: nil, action: nil)
    var process: Process?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 630, height: 310),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Proton4Mac — versione sperimentale"
        let content = window.contentView!
        func label(_ text: String, _ frame: NSRect, _ size: CGFloat = 13) {
            let view = NSTextField(labelWithString: text)
            view.frame = frame
            view.font = .systemFont(ofSize: size)
            content.addSubview(view)
        }
        label("Proton4Mac", NSRect(x: 24, y: 260, width: 580, height: 30), 24)
        label("Wine gratuito · ambienti separati per gioco", NSRect(x: 24, y: 230, width: 580, height: 24))
        path.frame = NSRect(x: 24, y: 184, width: 450, height: 26)
        path.isEditable = false
        path.placeholderString = "Nessun file selezionato"
        content.addSubview(path)
        chooseButton.frame = NSRect(x: 484, y: 182, width: 122, height: 30)
        chooseButton.target = self; chooseButton.action = #selector(choose)
        content.addSubview(chooseButton)
        label("Ambiente del gioco", NSRect(x: 24, y: 145, width: 150, height: 24))
        prefix.frame = NSRect(x: 180, y: 143, width: 290, height: 26)
        content.addSubview(prefix)
        label("Usa lo stesso nome per installare e avviare un gioco.", NSRect(x: 24, y: 111, width: 580, height: 24))
        status.frame = NSRect(x: 24, y: 70, width: 580, height: 35)
        status.maximumNumberOfLines = 2
        content.addSubview(status)
        runButton.frame = NSRect(x: 480, y: 24, width: 126, height: 32)
        runButton.target = self; runButton.action = #selector(run)
        content.addSubview(runButton)
        label("Steam nativo e DirectX 12: ancora da portare e verificare.", NSRect(x: 24, y: 28, width: 450, height: 24), 11)
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if process?.isRunning == true {
            let alert = NSAlert()
            alert.messageText = "Il gioco è ancora in esecuzione"
            alert.informativeText = "Chiudi il gioco prima di uscire dal launcher."
            alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }

    @objc func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "exe") ?? .executable]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { path.stringValue = url.path }
    }

    @objc func run() {
        guard !path.stringValue.isEmpty else { status.stringValue = "Scegli prima un file .exe."; return }
        let fm = FileManager.default
        let python = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            .first { fm.isExecutableFile(atPath: $0) }
        guard let executable = python, let script = Bundle.main.url(forResource: "proton4mac", withExtension: "py") else {
            status.stringValue = "Python 3 non trovato. Installa Python 3 e riapri l’app."; return
        }
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Proton4Mac")
        let logs = root.appendingPathComponent("logs")
        do {
            try fm.createDirectory(at: logs, withIntermediateDirectories: true)
            let log = logs.appendingPathComponent("launch-\(UUID().uuidString).log")
            fm.createFile(atPath: log.path, contents: nil)
            let output = try FileHandle(forWritingTo: log)
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = [script.path, "run", "--prefix", prefix.stringValue, path.stringValue]
            task.standardOutput = output; task.standardError = output
            task.terminationHandler = { [weak self] finished in
                try? output.close()
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.runButton.isEnabled = true
                    self.chooseButton.isEnabled = true
                    self.prefix.isEnabled = true
                    self.process = nil
                    self.status.stringValue = finished.terminationStatus == 0 ? "Esecuzione terminata." : "Avvio terminato con errore. Consulta il log."
                    if finished.terminationStatus != 0 { NSWorkspace.shared.open(log) }
                }
            }
            try task.run()
            process = task
            runButton.isEnabled = false; chooseButton.isEnabled = false; prefix.isEnabled = false
            status.stringValue = "Gioco in esecuzione. Al primo avvio Wine prepara l’ambiente."
        } catch { status.stringValue = "Avvio non riuscito: \(error.localizedDescription)" }
    }
}

let app = NSApplication.shared
let delegate = Launcher()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
