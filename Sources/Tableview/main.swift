import AppKit
import TableCore
import UniformTypeIdentifiers

@MainActor
final class FileDropView: NSView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        (NSApp.delegate as? AppDelegate)?.openURLs(urls)
        return true
    }
}

@MainActor
final class CSVTable: NSTableView {
    weak var owner: ViewerWindow?
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point), column = column(at: point)
        super.mouseDown(with: event)
        if row >= 0 && column >= 0 { owner?.select(row: row, column: column) }
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: owner?.move(rows: 0, columns: -1)
        case 124: owner?.move(rows: 0, columns: 1)
        case 125: owner?.move(rows: 1, columns: 0)
        case 126: owner?.move(rows: -1, columns: 0)
        case 48: owner?.move(rows: 0, columns: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 53: owner?.cancelWork(nil)
        default: super.keyDown(with: event)
        }
    }
    @objc func copy(_ sender: Any?) { owner?.copyValue(sender) }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        (NSApp.delegate as? AppDelegate)?.openURLs(urls)
        return true
    }
}

@MainActor
final class ViewerWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate, NSSearchFieldDelegate {
    private let table = CSVTable()
    private let status = NSTextField(labelWithString: "Open or drop a CSV file to begin.")
    private let inspector = NSTextView()
    private let search = NSSearchField()
    private let header = NSButton(checkboxWithTitle: "First record is header", target: nil, action: nil)
    private let delimiter = NSPopUpButton()
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let loadGate = RequestGate(), searchGate = RequestGate()
    private var model: GridModel?
    private var cache: RowCache?
    private var url: URL?
    private var loading = false
    private var sourceTitle = "Tableview"

    init(url: URL? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Tableview — Read Only"
        window.minSize = NSSize(width: 850, height: 430)
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CSVViewer")
        window.center()
        let root = FileDropView(); root.registerForDraggedTypes([.fileURL]); window.contentView = root
        let open = NSButton(title: "Open…", target: NSApp.delegate, action: #selector(AppDelegate.openDocument(_:)))
        header.state = .on; header.target = self; header.action = #selector(optionsChanged(_:))
        delimiter.addItems(withTitles: ["Auto delimiter", "Comma", "Semicolon", "Tab", "Pipe"])
        delimiter.target = self; delimiter.action = #selector(optionsChanged(_:))
        search.placeholderString = "Find literal text"; search.delegate = self
        search.target = self; search.action = #selector(findNext(_:))
        search.sendsSearchStringImmediately = false
        search.sendsWholeSearchString = true
        let next = NSButton(title: "Find Next", target: self, action: #selector(findNext(_:)))
        cancel.target = self; cancel.action = #selector(cancelWork(_:)); cancel.isEnabled = false
        let bar = NSStackView(views: [open, header, delimiter, search, next, cancel])
        bar.orientation = .horizontal; bar.spacing = 10
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false
        scroll.borderType = .bezelBorder
        table.owner = self; table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 25; table.intercellSpacing = NSSize(width: 1, height: 1)
        table.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false; table.allowsMultipleSelection = false
        table.registerForDraggedTypes([.fileURL])
        scroll.documentView = table
        let inspectorLabel = NSTextField(labelWithString: "Selected cell — full literal value (⌘C to copy from grid)")
        let inspectorScroll = NSScrollView()
        inspectorScroll.hasVerticalScroller = true; inspectorScroll.borderType = .bezelBorder
        inspector.isEditable = false; inspector.isSelectable = true; inspector.isRichText = false
        inspector.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        inspector.textContainerInset = NSSize(width: 8, height: 8)
        inspector.autoresizingMask = [.width]; inspector.isVerticallyResizable = true
        inspector.textContainer?.widthTracksTextView = true
        inspectorScroll.documentView = inspector
        status.lineBreakMode = .byTruncatingMiddle
        for view in [bar, scroll, inspectorLabel, inspectorScroll, status] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12), bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            search.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 10), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            inspectorLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8), inspectorLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            inspectorScroll.topAnchor.constraint(equalTo: inspectorLabel.bottomAnchor, constant: 4), inspectorScroll.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), inspectorScroll.trailingAnchor.constraint(equalTo: scroll.trailingAnchor), inspectorScroll.heightAnchor.constraint(equalToConstant: 115),
            status.topAnchor.constraint(equalTo: inspectorScroll.bottomAnchor, constant: 8), status.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), status.trailingAnchor.constraint(equalTo: scroll.trailingAnchor), status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
        if let url { load(url) }
    }
    required init?(coder: NSCoder) { fatalError("Not used") }

    func load(_ url: URL) {
        self.url = url; sourceTitle = url.lastPathComponent
        searchGate.cancel()
        let ticket = loadGate.begin(), gate = loadGate
        let separator: UInt8? = [nil, 44, 59, 9, 124][delimiter.indexOfSelectedItem]
        loading = true; cancel.isEnabled = true
        model = nil; cache = nil; inspector.string = ""; rebuildColumns()
        window?.title = "\(sourceTitle) — Loading…"
        status.stringValue = "Reading and indexing \(sourceTitle)…"
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CSVDocument, Error> in
                Result {
                    try OpenOptions.validate(url)
                    return try CSVDocument(url: url, delimiter: separator, cancelled: { !gate.isCurrent(ticket) })
                }
            }.value
            guard let self, gate.isCurrent(ticket) else { return }
            self.loading = false; self.cancel.isEnabled = false
            switch result {
            case .success(let document):
                var model = GridModel(document: document); model.hasHeader = self.header.state == .on
                self.model = model; self.cache = RowCache(document: document)
                self.window?.representedURL = url
                self.window?.title = "\(self.sourceTitle) — Read Only"
                self.rebuildColumns(); self.showDimensions()
                if model.rowCount > 0 { self.select(row: 0, column: 0) }
            case .failure(let error):
                self.window?.title = "\(self.sourceTitle) — Could Not Open"
                self.status.stringValue = String(describing: error)
                self.inspector.string = String(describing: error)
            }
        }
    }

    private func rebuildColumns() {
        table.deselectAll(nil)
        for column in table.tableColumns { table.removeTableColumn(column) }
        if let model {
            // Decode the header once, even for very wide files.
            let titles = model.hasHeader && model.document.rowCount > 0 ? (try? model.document.row(0)) ?? [] : []
            for i in 0..<model.document.columnCount {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(i)))
                let title = titles.indices.contains(i) && !titles[i].isEmpty ? titles[i] : "Column \(i + 1)"
                column.title = String(title.prefix(200)).replacingOccurrences(of: "\n", with: " ⏎ ")
                column.headerToolTip = title
                column.width = 160; column.minWidth = 45; column.maxWidth = 1800
                column.resizingMask = .userResizingMask
                table.addTableColumn(column)
            }
        }
        table.reloadData()
    }
    private func showDimensions() {
        guard let model else { return }
        status.stringValue = "\(model.rowCount.formatted()) data rows × \(model.document.columnCount) columns · \(model.document.byteCount.formatted()) bytes · delimiter \(model.document.delimiter == 9 ? "Tab" : String(UnicodeScalar(model.document.delimiter))) · Read Only"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { model?.rowCount ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let model, let tableColumn, let column = Int(tableColumn.identifier.rawValue) else { return nil }
        let id = NSUserInterfaceItemIdentifier("Cell")
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? NSTextField) ?? NSTextField(labelWithString: "")
        field.identifier = id; field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byTruncatingTail; field.maximumNumberOfLines = 1
        do {
            let values = try cache?.row(model.sourceRow(row)) ?? []
            let value = values.indices.contains(column) ? values[column] : ""
            field.stringValue = String(value.prefix(512)).replacingOccurrences(of: "\r", with: "⏎").replacingOccurrences(of: "\n", with: "⏎")
            field.toolTip = "Record \(model.sourceRow(row) + 1), column \(column + 1). Select for full value."
        } catch { field.stringValue = "Error"; status.stringValue = String(describing: error) }
        field.drawsBackground = model.selection == Cell(row: row, column: column)
        field.backgroundColor = .selectedContentBackgroundColor
        field.textColor = field.drawsBackground ? .white : .labelColor
        return field
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0 { select(row: table.selectedRow, column: model?.selection?.column ?? 0) }
    }
    func select(row: Int, column: Int) {
        guard model != nil else { return }
        let old = model?.selection
        model?.select(row: row, column: column)
        guard let selected = model?.selection else { return }
        if table.selectedRow != selected.row { table.selectRowIndexes(IndexSet(integer: selected.row), byExtendingSelection: false) }
        var rows = IndexSet(integer: selected.row)
        if let old, old.row < table.numberOfRows { rows.insert(old.row) }
        table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        table.scrollRowToVisible(selected.row); table.scrollColumnToVisible(selected.column)
        do { inspector.string = try model?.value() ?? "" }
        catch { status.stringValue = String(describing: error) }
    }
    func move(rows: Int, columns: Int) {
        var destination = model
        destination?.move(rows: rows, columns: columns)
        if let cell = destination?.selection { select(row: cell.row, column: cell.column) }
    }
    @objc func copyValue(_ sender: Any?) {
        guard let model, model.selection != nil else { return }
        do {
            let value = try model.value()
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value, forType: .string)
        } catch { status.stringValue = String(describing: error) }
    }
    @objc func focusFind(_ sender: Any?) { window?.makeFirstResponder(search) }
    func controlTextDidChange(_ obj: Notification) {
        searchGate.cancel(); cancel.isEnabled = loading
        if !loading { showDimensions() }
    }
    @objc func findNext(_ sender: Any?) {
        guard let model, !search.stringValue.isEmpty else { searchGate.cancel(); return }
        let query = search.stringValue, document = model.document
        let after = model.selection.map { Cell(row: model.sourceRow($0.row), column: $0.column) }
        let firstRow = model.hasHeader ? 1 : 0
        let gate = searchGate, ticket = gate.begin()
        status.stringValue = "Finding \(query)…"; cancel.isEnabled = true
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Cell?, Error> in
                Result { try document.find(query, after: after, firstRow: firstRow, cancelled: { !gate.isCurrent(ticket) }) }
            }.value
            guard let self, gate.isCurrent(ticket) else { return }
            self.cancel.isEnabled = false
            switch result {
            case .success(let cell):
                if let cell { self.select(row: cell.row - firstRow, column: cell.column); self.status.stringValue = "Found at record \(cell.row + 1), column \(cell.column + 1). Find Next wraps at the end." }
                else { self.status.stringValue = "No match for “\(query)”." }
            case .failure(let error): self.status.stringValue = String(describing: error)
            }
        }
    }
    @objc func optionsChanged(_ sender: Any?) {
        searchGate.cancel()
        if sender as? NSPopUpButton === delimiter {
            if let url { load(url) }
        } else {
            model?.hasHeader = header.state == .on; model?.selection = nil
            rebuildColumns(); inspector.string = ""; showDimensions()
            cancel.isEnabled = loading
        }
    }
    @objc func cancelWork(_ sender: Any?) {
        let wasLoading = loading
        loadGate.cancel(); searchGate.cancel(); loading = false; cancel.isEnabled = false
        if wasLoading { window?.title = "\(sourceTitle) — Cancelled" }
        status.stringValue = wasLoading ? "Load cancelled. Change delimiter or reopen the file to try again." : "Search cancelled."
    }
    func windowWillClose(_ notification: Notification) {
        loadGate.cancel(); searchGate.cancel()
        (NSApp.delegate as? AppDelegate)?.closed(self)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var viewers: [ViewerWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        makeMenus()
        if viewers.isEmpty {
            let paths = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
            if paths.isEmpty { show(ViewerWindow()) }
            else { openURLs(paths.map { URL(fileURLWithPath: $0) }) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    private func show(_ viewer: ViewerWindow) { viewers.append(viewer); viewer.showWindow(nil); viewer.window?.makeKeyAndOrderFront(nil) }
    func openURLs(_ urls: [URL]) { for url in urls { show(ViewerWindow(url: url)) } }
    func closed(_ viewer: ViewerWindow) { viewers.removeAll { $0 === viewer } }
    func application(_ sender: NSApplication, open urls: [URL]) { openURLs(urls) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { show(ViewerWindow()) }; return true
    }
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.title = "Open CSV or delimited UTF-8 text"
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .plainText, .data]
        if panel.runModal() == .OK { openURLs(panel.urls) }
    }
    @objc func find(_ sender: Any?) { viewers.first { $0.window === NSApp.keyWindow }?.focusFind(sender) }
    @objc func findNext(_ sender: Any?) { viewers.first { $0.window === NSApp.keyWindow }?.findNext(sender) }
    private func makeMenus() {
        let menu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(); menu.addItem(item)
            let child = NSMenu(title: title); item.submenu = child; return child
        }
        let app = submenu("Tableview")
        app.addItem(withTitle: "About Tableview", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Tableview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("File")
        let open = file.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o"); open.target = self
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = submenu("Edit")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let find = edit.addItem(withTitle: "Find…", action: #selector(self.find(_:)), keyEquivalent: "f"); find.target = self
        let next = edit.addItem(withTitle: "Find Next", action: #selector(findNext(_:)), keyEquivalent: "g"); next.target = self
        let window = submenu("Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = window; NSApp.mainMenu = menu
    }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
