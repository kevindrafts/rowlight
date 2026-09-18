import Foundation

public struct Cell: Equatable, Sendable {
    public let row: Int
    public let column: Int
    public init(row: Int, column: Int) { self.row = row; self.column = column }
}

/// Confine a cache to its owning UI thread. Search uses the immutable document directly.
public final class RowCache {
    public let document: CSVDocument
    private let maxRows: Int
    private let maxBytes: Int
    private var entries: [Int: (values: [String], cost: Int)] = [:]
    private var order: [Int] = []
    public var count: Int { entries.count }
    public private(set) var cost = 0
    public init(document: CSVDocument, maxRows: Int = 128, maxBytes: Int = 8 * 1024 * 1024) {
        self.document = document; self.maxRows = max(0, maxRows); self.maxBytes = max(0, maxBytes)
    }
    public func row(_ index: Int) throws -> [String] {
        if let entry = entries[index] {
            order.removeAll { $0 == index }; order.append(index)
            return entry.values
        }
        let values = try document.row(index)
        // Conservative accounting for string slots and dictionary/list bookkeeping.
        let bytes = values.reduce(128) { $0 + 32 + $1.utf8.count }
        guard maxRows > 0, bytes <= maxBytes else { return values }
        while count >= maxRows || cost + bytes > maxBytes {
            let oldest = order.removeFirst()
            cost -= entries.removeValue(forKey: oldest)!.cost
        }
        entries[index] = (values, bytes); order.append(index); cost += bytes
        return values
    }
}

public struct GridModel {
    public let document: CSVDocument
    public var hasHeader = true {
        didSet { if hasHeader != oldValue { selection = nil } }
    }
    public var selection: Cell?
    public init(document: CSVDocument) { self.document = document }
    public var rowCount: Int { max(0, document.rowCount - (hasHeader ? 1 : 0)) }
    public func sourceRow(_ row: Int) -> Int { row + (hasHeader ? 1 : 0) }
    /// Display-only gutter label; never a field in the document.
    public func rowNumber(at row: Int) -> Int? {
        (0..<rowCount).contains(row) ? row + 1 : nil
    }
    /// Cells whose selection presentation changed, independent of table width.
    public func selectionChanges(from previous: Cell?) -> [Cell] {
        guard previous != selection else { return [] }
        return [previous, selection].compactMap { $0 }
    }
    public func title(_ column: Int) throws -> String {
        if hasHeader && document.rowCount > 0 {
            let fields = try document.row(0)
            if fields.indices.contains(column), !fields[column].isEmpty { return fields[column] }
        }
        return "Column \(column + 1)"
    }
    public mutating func select(row: Int, column: Int) {
        guard rowCount > 0, document.columnCount > 0 else { selection = nil; return }
        selection = Cell(row: min(max(0, row), rowCount - 1), column: min(max(0, column), document.columnCount - 1))
    }
    public mutating func move(rows: Int, columns: Int) {
        guard let selection else { select(row: 0, column: 0); return }
        select(row: selection.row + rows, column: selection.column + columns)
    }
    public func value() throws -> String {
        guard let selection, selection.row >= 0, selection.row < rowCount else { return "" }
        let values = try document.row(sourceRow(selection.row))
        return values.indices.contains(selection.column) ? values[selection.column] : ""
    }
}

/// Each independent load/search stream owns a gate. Cancellation also invalidates completion.
public final class RequestGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    public init() {}
    @discardableResult public func begin() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        return generation
    }
    public func isCurrent(_ ticket: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return ticket == generation
    }
    public func cancel() { begin() }
}

extension CSVDocument {
    public func find(_ query: String, after: Cell? = nil, firstRow: Int = 0, cancelled: () -> Bool = { false }) throws -> Cell? {
        if cancelled() { throw CSVError.cancelled }
        let first = max(0, firstRow)
        guard !query.isEmpty, first < rowCount else { return nil }
        let start = min(max(first, after?.row ?? first), rowCount - 1)
        // Search the tail of the selected row, later records, then wrap through its prefix.
        for offset in 0...(rowCount - first) {
            if cancelled() { throw CSVError.cancelled }
            let rowIndex = first + (start - first + offset) % (rowCount - first)
            let values = try row(rowIndex)
            for (column, value) in values.enumerated() {
                if cancelled() { throw CSVError.cancelled }
                if offset == 0, let after, column <= after.column { continue }
                if offset == rowCount - first {
                    guard let after, column <= after.column else { continue }
                }
                if value.range(of: query, options: [.caseInsensitive]) != nil { return Cell(row: rowIndex, column: column) }
            }
        }
        return nil
    }
}
