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
final class PaddedTextCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var result = super.drawingRect(forBounds: rect.insetBy(dx: 7, dy: 0))
        let height = min(result.height, cellSize.height)
        result.origin.y += (result.height - height) / 2
        result.size.height = height
        return result
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
        // The ruler follows vertical scrolling only; horizontal content offsets
        // must never clip its labels away.
        let visibleBand = NSRect(x: bounds.minX, y: viewport.minY, width: bounds.width, height: viewport.height)
        NSBezierPath(rect: visibleBand.intersection(bounds)).addClip()
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
    override func drawBackground(inClipRect clipRect: NSRect) {
        backgroundColor.setFill(); clipRect.fill()
        guard numberOfRows > 0 else { return }
        let populated = NSRect(x: 0, y: 0, width: bounds.width, height: rect(ofRow: numberOfRows - 1).maxY)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: populated).addClip()
        super.drawBackground(inClipRect: clipRect.intersection(populated))
        NSGraphicsContext.restoreGraphicsState()
    }
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
        case 49: owner?.toggleInspector(nil)
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
    private let welcome = NSStackView()
    private let documentName = NSTextField(labelWithString: "Rowlight")
    private let documentDetail = NSTextField(labelWithString: "A clear view of your data")
    private let inspectorToggle = NSButton(title: "Expand ↗", target: nil, action: nil)
    private var inspectorHeight: NSLayoutConstraint!
    private var inspectorExpanded = false
    private let importPopover = NSPopover()
    private let density = NSPopUpButton()
    private let mono = NSButton(checkboxWithTitle: "Monospaced text", target: nil, action: nil)
    private let inspectorScroll = NSScrollView()
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
    private var sourceTitle = "Rowlight"

    init(url: URL? = nil) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Rowlight — Read Only"
        window.minSize = NSSize(width: 850, height: 480)
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("CSVViewer")
        window.center()
        let root = FileDropView(); root.registerForDraggedTypes([.fileURL]); window.contentView = root
        let open = NSButton(title: "Open…", target: NSApp.delegate, action: #selector(AppDelegate.openDocument(_:)))
        header.state = .on; header.target = self; header.action = #selector(optionsChanged(_:))
        delimiter.addItems(withTitles: ["Auto delimiter", "Comma", "Semicolon", "Tab", "Pipe"])
        delimiter.target = self; delimiter.action = #selector(optionsChanged(_:))
        search.placeholderString = "Search this file   ⌘F"; search.delegate = self
        search.target = self; search.action = #selector(findNext(_:))
        search.sendsSearchStringImmediately = false
        search.sendsWholeSearchString = true
        let next = NSButton(title: "Next", target: self, action: #selector(findNext(_:)))
        cancel.target = self; cancel.action = #selector(cancelWork(_:)); cancel.isEnabled = false; cancel.isHidden = true
        let brand = NSImageView(image: NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Rowlight")!)
        brand.contentTintColor = .systemTeal
        open.bezelStyle = .rounded; next.bezelStyle = .rounded; cancel.bezelStyle = .rounded
        let options = NSButton(title: "Import Options", target: self, action: #selector(showImportOptions(_:)))
        options.bezelStyle = .rounded
        density.addItems(withTitles: ["Comfortable", "Compact"])
        density.target = self; density.action = #selector(changeDensity(_:))
        density.setAccessibilityLabel("Row density")
        mono.target = self; mono.action = #selector(changeTypography(_:))
        let optionsTitle = NSTextField(labelWithString: "File interpretation")
        optionsTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        let optionsHint = NSTextField(labelWithString: "Values are always preserved as written.")
        optionsHint.font = .systemFont(ofSize: 11); optionsHint.textColor = .secondaryLabelColor
        let optionsStack = NSStackView(views: [optionsTitle, header, delimiter, mono, optionsHint])
        optionsStack.orientation = .vertical; optionsStack.alignment = .leading; optionsStack.spacing = 16
        optionsStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        let optionsController = NSViewController(); optionsController.view = optionsStack
        importPopover.contentViewController = optionsController; importPopover.behavior = .transient
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let bar = NSStackView(views: [open, options, density, spacer, search, next, cancel])
        bar.orientation = .horizontal; bar.spacing = 10
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.wantsLayer = true; scroll.layer?.cornerRadius = 8
        scroll.layer?.masksToBounds = true
        table.owner = self; table.dataSource = self; table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.selectionHighlightStyle = .none
        table.focusRingType = .none
        table.gridColor = .separatorColor.withAlphaComponent(0.35)
        table.setAccessibilityLabel("CSV data grid")
        table.rowHeight = 32; table.intercellSpacing = NSSize(width: 1, height: 1)
        table.gridStyleMask = []
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
        inspectorScroll.hasVerticalScroller = true; inspectorScroll.borderType = .noBorder
        inspectorScroll.wantsLayer = true; inspectorScroll.layer?.cornerRadius = 6
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
        documentName.font = .systemFont(ofSize: 21, weight: .semibold)
        documentName.lineBreakMode = .byTruncatingMiddle
        documentDetail.font = .systemFont(ofSize: 12); documentDetail.textColor = .secondaryLabelColor
        let identity = NSStackView(views: [documentName, documentDetail])
        identity.orientation = .vertical; identity.alignment = .leading; identity.spacing = 5
        let badge = NSTextField(labelWithString: "READ ONLY")
        badge.font = .systemFont(ofSize: 10, weight: .semibold); badge.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [brand, identity, badge]); heading.spacing = 12
        brand.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 25, weight: .regular)
        inspectorToggle.bezelStyle = .rounded; inspectorToggle.controlSize = .small
        inspectorToggle.target = self; inspectorToggle.action = #selector(toggleInspector(_:))
        inspectorToggle.toolTip = "Expand or collapse the full value. Space from the grid."
        inspectorHeight = inspectorScroll.heightAnchor.constraint(equalToConstant: 36)
        for view in [heading, bar, scroll, inspectorLabel, inspectorScroll, inspectorToggle, status] {
            view.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(view)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 18), heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22), heading.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -22),
            bar.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 20), bar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), bar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            search.widthAnchor.constraint(equalToConstant: 245),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 16), scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20), scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            inspectorLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 14), inspectorLabel.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            inspectorScroll.topAnchor.constraint(equalTo: inspectorLabel.bottomAnchor, constant: 9), inspectorScroll.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), inspectorScroll.trailingAnchor.constraint(equalTo: scroll.trailingAnchor), inspectorHeight,
            inspectorToggle.centerYAnchor.constraint(equalTo: inspectorLabel.centerYAnchor), inspectorToggle.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            inspectorLabel.trailingAnchor.constraint(lessThanOrEqualTo: inspectorToggle.leadingAnchor, constant: -12),
            status.topAnchor.constraint(equalTo: inspectorScroll.bottomAnchor, constant: 8), status.leadingAnchor.constraint(equalTo: scroll.leadingAnchor), status.trailingAnchor.constraint(equalTo: scroll.trailingAnchor), status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
        let welcomeIcon = NSImageView(image: NSImage(systemSymbolName: "tablecells", accessibilityDescription: "Rowlight")!)
        welcomeIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 44, weight: .light)
        welcomeIcon.contentTintColor = .systemTeal
        let welcomeTitle = NSTextField(labelWithString: "A clear view of your data")
        welcomeTitle.font = .systemFont(ofSize: 24, weight: .semibold)
        let welcomeDetail = NSTextField(labelWithString: "Drop a CSV or TSV file here to get started.")
        welcomeDetail.textColor = .secondaryLabelColor
        let welcomeOpen = NSButton(title: "Open File…", target: NSApp.delegate, action: #selector(AppDelegate.openDocument(_:)))
        welcomeOpen.bezelStyle = .rounded
        let welcomeHint = NSTextField(labelWithString: "⌘O to open · Read only · Your original file stays unchanged")
        welcomeHint.font = .systemFont(ofSize: 11)
        welcomeHint.textColor = .secondaryLabelColor
        welcome.orientation = .vertical; welcome.alignment = .centerX; welcome.spacing = 14
        for view in [welcomeIcon, welcomeTitle, welcomeDetail, welcomeOpen, welcomeHint] { welcome.addArrangedSubview(view) }
        welcome.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(welcome)
        NSLayoutConstraint.activate([
            welcome.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            welcome.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            welcome.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: 24),
            welcome.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24)
        ])
        showWelcome(true)
        window.initialFirstResponder = welcomeOpen
        if let url { load(url) }
    }
    required init?(coder: NSCoder) { fatalError("Not used") }

    private func showWelcome(_ visible: Bool) {
        welcome.isHidden = !visible
        for view in [scroll, inspectorLabel, inspectorScroll, inspectorToggle] { view.isHidden = visible }
    }

    @objc func showImportOptions(_ sender: NSButton) {
        importPopover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
    @objc func changeDensity(_ sender: Any?) {
        table.rowHeight = density.indexOfSelectedItem == 1 ? 23 : 32
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows))
        gutter.needsDisplay = true
    }
    @objc func changeTypography(_ sender: Any?) { table.reloadData() }
    @objc func toggleInspector(_ sender: Any?) {
        inspectorExpanded.toggle()
        inspectorHeight.constant = inspectorExpanded ? 150 : 36
        inspectorToggle.title = inspectorExpanded ? "Collapse ↙" : "Expand ↗"
        window?.contentView?.layoutSubtreeIfNeeded()
        gutter.needsDisplay = true
    }
    func runUISelfChecks() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else {
                throw NSError(domain: "Rowlight.UI", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
        }
        try check(table.selectionHighlightStyle == .none, "Whole-row selection must be disabled")
        try check(table.numberOfRows == 0 && inspector.string.isEmpty, "Empty window selection")
        try check(!welcome.isHidden && scroll.isHidden, "Welcome hides unused grid")
        toggleInspector(nil)
        try check(inspectorHeight.constant == 150, "Inspector expands")
        toggleInspector(nil)
        try check(inspectorHeight.constant == 36, "Inspector returns to compact height")
        let records = (0..<120).map { row in (0..<16).map { "r\(row)c\($0)" }.joined(separator: ",") }.joined(separator: "\n")
        let document = try CSVDocument(data: Data(records.utf8))
        model = GridModel(document: document); cache = RowCache(document: document)
        rebuildColumns()
        window?.contentView?.layoutSubtreeIfNeeded(); scroll.tile(); table.layoutSubtreeIfNeeded()
        try check(table.numberOfColumns == 16 && table.numberOfRows == 119, "Gutter must not be a data column")
        try check(welcome.isHidden && !scroll.isHidden, "Loaded grid replaces welcome")
        try check(table.tableColumns.allSatisfy { (110...360).contains($0.width) }, "Initial column widths bounded")
        density.selectItem(at: 1); changeDensity(nil)
        try check(table.rowHeight == 23, "Compact density")
        density.selectItem(at: 0); changeDensity(nil)
        try check(table.rowHeight == 32, "Comfortable density")
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
        documentName.stringValue = sourceTitle
        documentDetail.stringValue = "Reading your file…"
        searchGate.cancel()
        let ticket = loadGate.begin(), gate = loadGate
        let separator: UInt8? = [nil, 44, 59, 9, 124][delimiter.indexOfSelectedItem]
        loading = true; cancel.isEnabled = true; cancel.isHidden = false
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
            self.loading = false; self.cancel.isEnabled = false; self.cancel.isHidden = true
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
                self.documentDetail.stringValue = "Could not open this file"
                self.status.stringValue = String(describing: error)
                self.inspector.string = String(describing: error)
            }
        }
    }

    private func rebuildColumns() {
        showWelcome(model == nil && url == nil)
        table.deselectAll(nil)
        for column in table.tableColumns { table.removeTableColumn(column) }
        if let model {
            // Decode the header once, even for very wide files.
            let titles = model.hasHeader && model.document.rowCount > 0 ? (try? model.document.row(0)) ?? [] : []
            // Bound width sampling independently of file size and column count.
            let samples = (0..<min(model.rowCount, 24)).compactMap { try? model.document.row(model.sourceRow($0)) }
            for i in 0..<model.document.columnCount {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(String(i)))
                let title = titles.indices.contains(i) && !titles[i].isEmpty ? titles[i] : "Column \(i + 1)"
                column.title = String(title.prefix(200)).replacingOccurrences(of: "\n", with: " ⏎ ")
                column.headerToolTip = title
                let lengths = samples.map { $0.indices.contains(i) ? $0[i].prefix(48).count : 0 }
                let characters = max(title.prefix(48).count, lengths.max() ?? 0)
                column.width = CGFloat(min(360, max(110, characters * 7 + 30)))
                column.minWidth = 65; column.maxWidth = 1800
                column.headerCell.font = .systemFont(ofSize: 12, weight: .semibold)
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
        documentDetail.stringValue = "\(model.rowCount.formatted()) rows  ·  \(model.document.columnCount) columns  ·  \(ByteCountFormatter.string(fromByteCount: Int64(model.document.byteCount), countStyle: .file))"
        status.stringValue = "\(model.rowCount.formatted()) data rows × \(model.document.columnCount) columns · \(model.document.byteCount.formatted()) bytes · delimiter \(model.document.delimiter == 9 ? "Tab" : String(UnicodeScalar(model.document.delimiter))) · Read Only"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { model?.rowCount ?? 0 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let model, let tableColumn, let column = Int(tableColumn.identifier.rawValue) else { return nil }
        let id = NSUserInterfaceItemIdentifier("Cell")
        let field = (tableView.makeView(withIdentifier: id, owner: self) as? GridCell) ?? GridCell(labelWithString: "")
        if !(field.cell is PaddedTextCell) {
            let cell = PaddedTextCell(textCell: "")
            cell.isEditable = false; cell.isSelectable = false; cell.isBordered = false
            field.cell = cell
        }
        field.identifier = id; field.font = mono.state == .on ? .monospacedSystemFont(ofSize: 13, weight: .regular) : .systemFont(ofSize: 13)
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
        inspectorLabel.stringValue = "Row \(selected.row + 1) · Column \(selected.column + 1) ·  ⌘C to copy  ·  Space to expand"
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
        searchGate.cancel(); cancel.isEnabled = loading; cancel.isHidden = !loading
        if !loading { showDimensions() }
    }
    @objc func findNext(_ sender: Any?) {
        guard let model, !search.stringValue.isEmpty else { searchGate.cancel(); return }
        let query = search.stringValue, document = model.document
        let after = model.selection.map { Cell(row: model.sourceRow($0.row), column: $0.column) }
        let firstRow = model.hasHeader ? 1 : 0
        let gate = searchGate, ticket = gate.begin()
        status.stringValue = "Finding \(query)…"; cancel.isEnabled = true; cancel.isHidden = false
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Cell?, Error> in
                Result { try document.find(query, after: after, firstRow: firstRow, cancelled: { !gate.isCurrent(ticket) }) }
            }.value
            guard let self, gate.isCurrent(ticket) else { return }
            self.cancel.isEnabled = false; self.cancel.isHidden = true
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
            cancel.isEnabled = loading; cancel.isHidden = !loading
        }
    }
    @objc func cancelWork(_ sender: Any?) {
        let wasLoading = loading
        loadGate.cancel(); searchGate.cancel(); loading = false; cancel.isEnabled = false; cancel.isHidden = true
        if wasLoading { window?.title = "\(sourceTitle) — Cancelled"; documentDetail.stringValue = "Loading cancelled" }
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
        let app = submenu("Rowlight")
        app.addItem(withTitle: "About Rowlight", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Rowlight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("File")
        let open = file.addItem(withTitle: "Open…", action: #selector(openDocument(_:)), keyEquivalent: "o"); open.target = self
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let edit = submenu("Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
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
