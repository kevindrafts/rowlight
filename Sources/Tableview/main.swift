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

/// A reusable cell owns its selection drawing; NSTableRowView never draws selection.
@MainActor
final class GridCell: NSTextField {
    var selectCell: (() -> Void)?
    override func accessibilityPerformPress() -> Bool {
        guard let selectCell else { return false }
        selectCell(); return true
    }
    var isCellSelected = false { didSet { needsDisplay = true; setAccessibilitySelected(isCellSelected) } }
    override func draw(_ dirtyRect: NSRect) {
        if isCellSelected {
            NSColor.systemTeal.withAlphaComponent(0.16).setFill()
            bounds.fill()
        }
        super.draw(dirtyRect)
        if isCellSelected {
            let outline = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 2, yRadius: 2)
            NSColor.keyboardFocusIndicatorColor.setStroke()
            outline.lineWidth = 2
            outline.stroke()
            if window?.firstResponder === enclosingScrollView?.documentView {
                NSGraphicsContext.saveGraphicsState()
                NSFocusRingPlacement.only.set()
                NSBezierPath(rect: bounds.insetBy(dx: 3, dy: 3)).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
}

/// Native scroll-view ruler: fixed horizontally, painted only for visible rows.
@MainActor
final class RowNumberRuler: NSRulerView {
    weak var table: NSTableView?
    var rowNumber: (Int) -> Int? = { _ in nil }
    init(scrollView: NSScrollView, table: NSTableView) {
        self.table = table
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        ruleThickness = 52
        clientView = table
        setAccessibilityElement(false) // Each accessible data cell includes its row number.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
    }
    required init(coder: NSCoder) { fatalError("Not used") }
    deinit { NotificationCenter.default.removeObserver(self) }
    @objc private func scrolled() { needsDisplay = true }
    override func scrollWheel(with event: NSEvent) { scrollView?.scrollWheel(with: event) }
    func labelRect(for row: Int) -> NSRect {
        guard let table else { return .zero }
        let rect = convert(table.rect(ofRow: row), from: table)
        return NSRect(x: 0, y: rect.minY, width: bounds.width, height: rect.height)
    }
    override func drawHashMarksAndLabels(in rect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        guard let table, let scrollView else { return }
        // AppKit overlays the header and ruler using clip-view content insets.
        var dataBounds = scrollView.contentView.bounds
        let insets = scrollView.contentView.contentInsets
        dataBounds.origin.y += insets.top
        dataBounds.size.height -= insets.top + insets.bottom
        let viewport = convert(dataBounds, from: scrollView.contentView)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: viewport.intersection(bounds)).addClip()
        let visible = table.rows(in: table.visibleRect)
        if visible.location != NSNotFound {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
            for row in visible.location..<NSMaxRange(visible) {
                guard let number = rowNumber(row) else { continue }
                let cell = labelRect(for: row)
                let label = String(number) as NSString
                let size = label.size(withAttributes: attributes)
                label.draw(at: NSPoint(x: bounds.maxX - size.width - 9, y: cell.midY - size.height / 2), withAttributes: attributes)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        if let header = table.headerView {
            let headerRect = convert(header.bounds, from: header)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor
            ]
            let label = "#" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: bounds.maxX - size.width - 9, y: headerRect.midY - size.height / 2), withAttributes: attributes)
        }
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
    }
}

@MainActor
final class CSVTable: NSTableView {
    weak var owner: ViewerWindow?
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point), column = column(at: point)
        window?.makeFirstResponder(self)
        if row >= 0 && column >= 0 { owner?.select(row: row, column: column) }
        else { owner?.clearSelection() }
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
    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder(); owner?.refreshSelectedCell(); return result
    }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder(); owner?.refreshSelectedCell(); return result
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
    private let scroll = NSScrollView()
    private var gutter: RowNumberRuler!
    private let inspectorLabel = NSTextField(labelWithString: "No cell selected")
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
        let brand = NSImageView(image: NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Tableview")!)
        brand.contentTintColor = .systemTeal
        open.bezelStyle = .rounded; next.bezelStyle = .rounded; cancel.bezelStyle = .rounded
        let bar = NSStackView(views: [brand, open, header, delimiter, search, next, cancel])
        bar.orientation = .horizontal; bar.spacing = 10
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = false
        scroll.borderType = .lineBorder
        table.owner = self; table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.gridColor = .separatorColor
        table.setAccessibilityLabel("CSV data grid")
        table.rowHeight = 25; table.intercellSpacing = NSSize(width: 1, height: 1)
        table.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false; table.allowsMultipleSelection = false
        table.registerForDraggedTypes([.fileURL])
        scroll.documentView = table
        gutter = RowNumberRuler(scrollView: scroll, table: table)
        gutter.rowNumber = { [weak self] row in self?.model?.rowNumber(at: row) }
        scroll.verticalRulerView = gutter
        scroll.hasVerticalRuler = true; scroll.hasHorizontalRuler = false; scroll.rulersVisible = true
        inspectorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        inspectorLabel.textColor = .secondaryLabelColor
        let inspectorScroll = NSScrollView()
        inspectorScroll.hasVerticalScroller = true; inspectorScroll.borderType = .lineBorder
        inspector.isEditable = false; inspector.isSelectable = true; inspector.isRichText = false
        inspector.textColor = .textColor; inspector.backgroundColor = .textBackgroundColor
        inspector.setAccessibilityLabel("Selected cell full literal value")
        inspector.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        inspector.textContainerInset = NSSize(width: 8, height: 8)
        inspector.autoresizingMask = [.width]; inspector.isVerticallyResizable = true
        inspector.textContainer?.widthTracksTextView = true
        inspectorScroll.documentView = inspector
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
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

    func runUISelfChecks() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(domain: "Tableview.UI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        try check(table.selectionHighlightStyle == .none, "Whole-row selection must be disabled")
        try check(table.numberOfRows == 0 && inspector.string.isEmpty, "Empty window selection")
        let records = (0..<120).map { row in (0..<16).map { "r\(row)c\($0)" }.joined(separator: ",") }.joined(separator: "\n")
        let document = try CSVDocument(data: Data(records.utf8))
        model = GridModel(document: document); cache = RowCache(document: document)
        rebuildColumns()
        window?.contentView?.layoutSubtreeIfNeeded(); scroll.tile(); table.layoutSubtreeIfNeeded()
        try check(table.numberOfColumns == 16 && table.numberOfRows == 119, "Gutter must not be a data column")
        try check(scroll.verticalRulerView === gutter && scroll.rulersVisible, "Fixed ruler installed")
        select(row: 0, column: 0)
        let first = table.view(atColumn: 0, row: 0, makeIfNecessary: true) as! GridCell
        move(rows: 0, columns: 1)
        let second = table.view(atColumn: 1, row: 0, makeIfNecessary: true) as! GridCell
        try check(!first.isCellSelected && second.isCellSelected, "Exact cell highlight follows keyboard")
        try check(second.isAccessibilitySelected(), "Selected cell accessibility")
        try check(table.selectedRow == -1 && inspector.string == "r1c1", "No native row selection; inspector follows cell")
        try check(table.view(atColumn: 0, row: 0, makeIfNecessary: false) === first, "Navigation keeps existing cell views")
        try check(first.accessibilityPerformPress(), "Accessible cell press selects the data cell")
        try check(model?.selection == Cell(row: 0, column: 0), "Accessible cell press coordinates")
        let rulerX = gutter.convert(gutter.bounds, to: nil).minX
        let beforeX = table.convert(table.rect(ofColumn: 0), to: nil).minX
        scroll.contentView.scroll(to: NSPoint(x: 200, y: 260))
        scroll.reflectScrolledClipView(scroll.contentView)
        table.layoutSubtreeIfNeeded()
        try check(gutter.convert(gutter.bounds, to: nil).minX == rulerX, "Horizontal scroll moved gutter")
        try check(table.convert(table.rect(ofColumn: 0), to: nil).minX < beforeX, "Grid did not scroll horizontally")
        let visibleRow = table.rows(in: table.visibleRect).location + 1
        let cell = table.view(atColumn: 2, row: visibleRow, makeIfNecessary: true)!
        let label = gutter.convert(gutter.labelRect(for: visibleRow), to: nil)
        try check(abs(label.midY - cell.convert(cell.bounds, to: nil).midY) <= 1, "Gutter/data row vertical alignment")
        let viewport = scroll.contentView.convert(scroll.contentView.bounds, to: nil)
        let columnHeader = table.headerView!.convert(table.headerView!.bounds, to: nil)
        try check(abs(viewport.maxY - scroll.contentView.contentInsets.top - columnHeader.minY) <= 1, "Header/data viewport alignment: viewport \(viewport), header \(columnHeader)")
        clearSelection()
        try check(model?.selection == nil && inspector.string.isEmpty, "Clear selection and inspector")
        header.state = .off; optionsChanged(header)
        try check(table.numberOfRows == 120 && model?.rowNumber(at: 0) == 1, "Header toggle row numbering")
        move(rows: 1, columns: 1)
        try check(model?.selection == Cell(row: 0, column: 0) && inspector.string == "r0c0", "Navigation from no selection targets first data cell")
        model = GridModel(document: try CSVDocument(data: Data("a,b,c\n001\n\n2,y,z".utf8)))
        cache = RowCache(document: model!.document); rebuildColumns()
        select(row: 1, column: 2)
        try check(inspector.string.isEmpty && model?.rowNumber(at: 1) == 2, "Blank/ragged cell remains selectable")
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window?.appearance = NSAppearance(named: name)
            window?.contentView?.layoutSubtreeIfNeeded()
            // Exercise native drawing in both appearances without claiming visual acceptance.
            let bitmap = scroll.bitmapImageRepForCachingDisplay(in: scroll.bounds)
            try check(bitmap != nil, "Appearance drawing surface unavailable")
            scroll.cacheDisplay(in: scroll.bounds, to: bitmap!)
        }
        print("PASS cell selection, accessibility state, inspector, fixed gutter, scroll/header alignment, header toggle, ragged rows, light/dark drawing")
    }

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
        gutter.ruleThickness = max(52, CGFloat(String(model?.rowCount ?? 0).count) * 8 + 20)
        gutter.needsDisplay = true
        inspectorLabel.stringValue = "No cell selected"
    }
    private func showDimensions() {
        guard let model else { return }
        status.stringValue = "\(model.rowCount.formatted()) data rows × \(model.document.columnCount) columns · \(model.document.byteCount.formatted()) bytes · delimiter \(model.document.delimiter == 9 ? "Tab" : String(UnicodeScalar(model.document.delimiter))) · Read Only"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { model?.rowCount ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let model, let tableColumn, let column = Int(tableColumn.identifier.rawValue) else { return nil }
        let id = NSUserInterfaceItemIdentifier("Cell")
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? GridCell) ?? GridCell(labelWithString: "")
        field.identifier = id; field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.lineBreakMode = .byTruncatingTail; field.maximumNumberOfLines = 1
        do {
            let values = try cache?.row(model.sourceRow(row)) ?? []
            let value = values.indices.contains(column) ? values[column] : ""
            field.stringValue = String(value.prefix(512)).replacingOccurrences(of: "\r", with: "⏎").replacingOccurrences(of: "\n", with: "⏎")
            field.toolTip = "Record \(model.sourceRow(row) + 1), column \(column + 1). Select for full value."
        } catch { field.stringValue = "Error"; status.stringValue = String(describing: error) }
        field.drawsBackground = false
        field.textColor = .labelColor
        field.isCellSelected = model.selection == Cell(row: row, column: column)
        field.selectCell = { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self.table)
            self.select(row: row, column: column)
        }
        field.setAccessibilityHelp("Press to select this cell. Use arrow keys to navigate and Command-C to copy its full literal value.")
        field.setAccessibilityLabel("Row \(row + 1), column \(column + 1), \(tableColumn.title)")
        return field
    }
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
    private func refreshCells(_ cells: [Cell]) {
        for cell in cells {
            guard cell.row >= 0, cell.row < table.numberOfRows,
                  cell.column >= 0, cell.column < table.numberOfColumns else { continue }
            // Do not instantiate offscreen cells or reload rows on keyboard navigation.
            if let view = table.view(atColumn: cell.column, row: cell.row, makeIfNecessary: false) as? GridCell {
                view.isCellSelected = model?.selection == cell
            }
        }
    }
    func refreshSelectedCell() { refreshCells([model?.selection].compactMap { $0 }) }
    func clearSelection() {
        let previous = model?.selection
        model?.selection = nil
        refreshCells(model?.selectionChanges(from: previous) ?? [])
        inspector.string = ""; inspectorLabel.stringValue = "No cell selected"
    }
    func select(row: Int, column: Int) {
        guard model != nil else { return }
        let old = model?.selection
        model?.select(row: row, column: column)
        refreshCells(model?.selectionChanges(from: old) ?? [])
        guard let selected = model?.selection else { clearSelection(); return }
        table.scrollRowToVisible(selected.row); table.scrollColumnToVisible(selected.column)
        inspectorLabel.stringValue = "Row \(selected.row + 1) · Column \(selected.column + 1) — full literal value (⌘C from grid)"
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
            model?.hasHeader = header.state == .on
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
if CommandLine.arguments.contains("--ui-self-check") {
    do {
        try ViewerWindow().runUISelfChecks()
        print("PASS AppKit UI self-checks")
        exit(0)
    } catch {
        print("FAIL AppKit UI self-checks: \(error.localizedDescription)")
        exit(1)
    }
}
app.run()
