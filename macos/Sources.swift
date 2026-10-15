import AppKit
import WebKit

class RetinaWindowController: NSWindowController, NSWindowDelegate {
    var adjusting = false
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
    init(title: String, size: NSSize) {
        guard let screen = DisplayPolicy.preferred else { fatalError("Display Retina non disponibile") }
        let frame = NSRect(origin: screen.visibleFrame.origin, size: size)
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false, screen: screen)
        window.title = title; window.isRestorable = false; window.collectionBehavior = [.fullScreenNone]
        super.init(window: window)
        window.delegate = self; DisplayPolicy.place(window, centered: true)
    }
    required init?(coder: NSCoder) { fatalError() }
    func windowDidMove(_ notification: Notification) { constrain() }
    func windowDidResize(_ notification: Notification) { constrain() }
    func constrain() {
        guard !adjusting, let window = window else { return }; adjusting = true
        DisplayPolicy.place(window); adjusting = false
    }
}

final class SourcesController: RetinaWindowController, NSTableViewDataSource, NSTableViewDelegate {
    let library: GameLibrary
    let table = NSTableView()
    let name = NSTextField(string: "")
    let address = NSTextField(string: "https://")
    let note = NSTextField(wrappingLabelWithString: "Scegli una sorgente o aggiungi un indirizzo. I collegamenti aprono il sito; installazione, account e compatibilità dipendono dal servizio.")
    var browsers: [BrowserController] = []
    init(library: GameLibrary) {
        self.library = library
        super.init(title: "Sorgenti · Proton4Mac", size: NSSize(width: 740, height: 570))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("source")); table.addTableColumn(column)
        table.headerView = nil; table.rowHeight = 54; table.dataSource = self; table.delegate = self
        table.target = self; table.doubleAction = #selector(openSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true
        name.placeholderString = "Nome della sorgente"; address.placeholderString = "https://sito.example"
        let add = NSButton(title: "Aggiungi sorgente", target: self, action: #selector(addSource)); add.bezelStyle = .rounded
        let open = NSButton(title: "Apri sorgente", target: self, action: #selector(openSelected)); open.bezelStyle = .rounded
        let remove = NSButton(title: "Rimuovi collegamento", target: self, action: #selector(removeSource)); remove.bezelStyle = .rounded
        let buttons = NSStackView(views: [open, remove, NSView()]); buttons.spacing = 10
        let heading = NSTextField(labelWithString: "Le tue sorgenti di giochi"); heading.font = .systemFont(ofSize: 23, weight: .bold)
        note.font = .systemFont(ofSize: 12); note.textColor = .secondaryLabelColor; note.maximumNumberOfLines = 3
        let layout = NSStackView(views: [heading, note, scroll, buttons, name, address, add])
        layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 14
        layout.translatesAutoresizingMaskIntoConstraints = false; window!.contentView!.addSubview(layout)
        for item in [note, scroll, buttons, name, address] { item.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([layout.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 24), layout.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -24), layout.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 24), layout.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor, constant: -24)])
        table.reloadData()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func windowWillClose(_ notification: Notification) {
        browsers.forEach { $0.close() }; browsers.removeAll()
        super.windowWillClose(notification)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { library.document.sources.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let source = library.document.sources[row]
        let label = NSTextField(wrappingLabelWithString: source.name + "\n" + source.url)
        label.font = .systemFont(ofSize: 13); label.maximumNumberOfLines = 2
        return label
    }
    @objc func addSource() {
        guard let url = GameSource.validURL(address.stringValue), !name.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else { note.stringValue = "Inserisci un nome e un indirizzo web http o https valido."; return }
        do {
            var sources = library.document.sources
            sources.append(GameSource(name: name.stringValue.trimmingCharacters(in: .whitespaces), url: url.absoluteString))
            try library.setSources(sources); table.reloadData(); name.stringValue = ""; address.stringValue = "https://"
            note.stringValue = "Sorgente salvata. Selezionala e premi Apri sorgente."
        } catch { note.stringValue = error.localizedDescription }
    }
    @objc func removeSource() {
        guard table.selectedRow >= 0, table.selectedRow < library.document.sources.count else { return }
        do { var sources = library.document.sources; sources.remove(at: table.selectedRow); try library.setSources(sources); table.reloadData() }
        catch { note.stringValue = error.localizedDescription }
    }
    @objc func openSelected() {
        guard table.selectedRow >= 0, table.selectedRow < library.document.sources.count, DisplayPolicy.preferred != nil else { return }
        let source = library.document.sources[table.selectedRow]
        guard let url = GameSource.validURL(source.url) else { return }
        let browser = BrowserController(title: source.name)
        browser.onClose = { [weak self, weak browser] in self?.browsers.removeAll { $0 === browser } }
        browsers.append(browser); browser.showWindow(nil); browser.load(url)
    }
}

final class BrowserController: RetinaWindowController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let web: WKWebView
    let location = NSTextField(string: "")
    let message = NSTextField(labelWithString: "")
    var children: [BrowserController] = []
    var downloads: [WKDownload] = []
    init(title: String, configuration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        web = WKWebView(frame: .zero, configuration: configuration)
        super.init(title: title + " · Proton4Mac", size: NSSize(width: 1120, height: 800))
        web.navigationDelegate = self; web.uiDelegate = self
        location.target = self; location.action = #selector(go)
        let back = NSButton(title: "←", target: self, action: #selector(back)); back.bezelStyle = .rounded
        let forward = NSButton(title: "→", target: self, action: #selector(forward)); forward.bezelStyle = .rounded
        let reload = NSButton(title: "Ricarica", target: self, action: #selector(reloadPage)); reload.bezelStyle = .rounded
        let bar = NSStackView(views: [back, forward, location, reload]); bar.spacing = 8
        message.font = .systemFont(ofSize: 11); message.textColor = .secondaryLabelColor
        let layout = NSStackView(views: [bar, web, message]); layout.orientation = .vertical; layout.alignment = .leading; layout.spacing = 8
        layout.translatesAutoresizingMaskIntoConstraints = false; window!.contentView!.addSubview(layout)
        for item in [bar, web, message] { item.widthAnchor.constraint(equalTo: layout.widthAnchor).isActive = true }
        NSLayoutConstraint.activate([layout.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 12), layout.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -12), layout.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 12), layout.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor, constant: -12)])
    }
    required init?(coder: NSCoder) { fatalError() }
    override func windowWillClose(_ notification: Notification) {
        web.stopLoading()
        children.forEach { $0.close() }; children.removeAll()
        downloads.forEach { $0.cancel { _ in } }; downloads.removeAll()
        super.windowWillClose(notification)
    }
    func load(_ url: URL) { location.stringValue = url.absoluteString; web.load(URLRequest(url: url)) }
    @objc func go() { if let url = GameSource.validURL(location.stringValue) { load(url) } }
    @objc func back() { web.goBack() }
    @objc func forward() { web.goForward() }
    @objc func reloadPage() { web.reload() }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { location.stringValue = webView.url?.absoluteString ?? location.stringValue; message.stringValue = "Navigazione sul Retina · I download non vengono eseguiti automaticamente." }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { message.stringValue = error.localizedDescription }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        guard ["http", "https", "about"].contains(scheme) else { message.stringValue = "Questo collegamento richiede un’app esterna e non viene aperto sul Samsung."; decisionHandler(.cancel); return }
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) { decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download) }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self; downloads.append(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self; downloads.append(download) }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let window = window else { completionHandler(nil); return }
        let save = NSSavePanel(); save.nameFieldStringValue = (suggestedFilename as NSString).lastPathComponent
        save.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        save.beginSheetModal(for: window) { [weak self] result in
            completionHandler(result == .OK ? save.url : nil)
            self?.message.stringValue = result == .OK ? "Download in corso…" : "Download annullato."
        }
    }
    func downloadDidFinish(_ download: WKDownload) { downloads.removeAll { $0 === download }; message.stringValue = "Download completato. Estrai eventuali archivi mantenendo tutti i file del gioco, poi apri il suo .exe." }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) { downloads.removeAll { $0 === download }; message.stringValue = "Download non riuscito: " + error.localizedDescription }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard DisplayPolicy.preferred != nil else { return nil }
        let child = BrowserController(title: "Sorgente", configuration: configuration); children.append(child); child.showWindow(nil)
        child.onClose = { [weak self, weak child] in self?.children.removeAll { $0 === child } }
        return child.web
    }
    func webViewDidClose(_ webView: WKWebView) { close() }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage text: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window = window else { completionHandler(); return }
        let alert = NSAlert(); alert.messageText = text; alert.beginSheetModal(for: window) { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage text: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window = window else { completionHandler(false); return }
        let alert = NSAlert(); alert.messageText = text; alert.addButton(withTitle: "Continua"); alert.addButton(withTitle: "Annulla")
        alert.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }
}
