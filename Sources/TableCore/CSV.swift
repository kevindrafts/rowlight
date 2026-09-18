import Foundation

public struct CSVLimits: Sendable {
    public var maxBytes: Int = 256 * 1024 * 1024
    public var maxRows: Int = 2_000_000
    public var maxColumns: Int = 4096
    public var maxRecordBytes: Int = 8 * 1024 * 1024
    public init() {}
}

public enum CSVError: Error, CustomStringConvertible {
    case invalid(String), cancelled, bounds
    public var description: String {
        switch self {
        case .invalid(let message): return message
        case .cancelled: return "Operation cancelled."
        case .bounds: return "The requested cell or record is out of range."
        }
    }
}

/// Immutable byte snapshot and record offsets; field strings are decoded on demand.
public final class CSVDocument: Sendable {
    private let data: Data
    private let records: [Range<Int>]
    public let delimiter: UInt8
    public let columnCount: Int
    public var rowCount: Int { records.count }
    public var byteCount: Int { data.count }

    public init(data: Data, delimiter: UInt8? = nil, limits: CSVLimits = CSVLimits(), cancelled: () -> Bool = { false }) throws {
        if cancelled() { throw CSVError.cancelled }
        guard limits.maxBytes > 0, limits.maxRows > 0, limits.maxColumns > 0, limits.maxRecordBytes > 0 else { throw CSVError.invalid("Resource limits must be positive.") }
        guard data.count <= limits.maxBytes else { throw CSVError.invalid("File exceeds the \(limits.maxBytes)-byte limit.") }
        let separator = delimiter ?? Self.detect(data)
        guard [44, 59, 9, 124].contains(separator) else { throw CSVError.invalid("Choose comma, semicolon, tab, or pipe.") }
        var offsets: [Range<Int>] = []
        var maxColumns = 0
        try data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var i = bytes.starts(with: [239, 187, 191]) ? 3 : 0
            var start = i, state = 0, columns = 1
            var continuation = 0, lower: UInt8 = 128, upper: UInt8 = 191
            while i < bytes.count {
                if i & 0x3fff == 0, cancelled() { throw CSVError.cancelled }
                guard i - start <= limits.maxRecordBytes else { throw CSVError.invalid("Record \(offsets.count + 1) exceeds the \(limits.maxRecordBytes)-byte limit.") }
                let b = bytes[i]
                if continuation > 0 {
                    guard b >= lower && b <= upper else { throw CSVError.invalid("Invalid UTF-8 at byte \(i + 1). Export as UTF-8 CSV.") }
                    continuation -= 1; lower = 128; upper = 191
                } else if b >= 128 {
                    switch b {
                    case 194...223: continuation = 1
                    case 224: continuation = 2; lower = 160
                    case 225...236, 238...239: continuation = 2
                    case 237: continuation = 2; upper = 159
                    case 240: continuation = 3; lower = 144
                    case 241...243: continuation = 3
                    case 244: continuation = 3; upper = 143
                    default: throw CSVError.invalid("Invalid UTF-8 at byte \(i + 1). Export as UTF-8 CSV.")
                    }
                } else if b == 0 { throw CSVError.invalid("NUL byte at byte \(i + 1). Binary and UTF-16 files are unsupported.") }
                if state == 2 {
                    if b == 34 { state = 3 }
                } else if b == separator {
                    columns += 1; state = 0
                    guard columns <= limits.maxColumns else { throw CSVError.invalid("Record \(offsets.count + 1) exceeds the \(limits.maxColumns)-column limit.") }
                } else if b == 10 || b == 13 {
                    guard offsets.count < limits.maxRows else { throw CSVError.invalid("File exceeds the \(limits.maxRows)-record limit.") }
                    offsets.append(start..<i); maxColumns = max(maxColumns, columns)
                    if b == 13 && i + 1 < bytes.count && bytes[i + 1] == 10 { i += 1 }
                    start = i + 1; columns = 1; state = 0
                } else if b == 34 {
                    if state == 0 || state == 3 { state = 2 }
                    else { throw CSVError.invalid("Unexpected quote in record \(offsets.count + 1), byte \(i + 1).") }
                } else {
                    if state == 3 { throw CSVError.invalid("Unexpected text after closing quote in record \(offsets.count + 1), byte \(i + 1).") }
                    if state == 0 { state = 1 }
                }
                i += 1
            }
            guard continuation == 0 else { throw CSVError.invalid("Incomplete UTF-8 sequence at end of file.") }
            guard state != 2 else { throw CSVError.invalid("Unclosed quote in record \(offsets.count + 1).") }
            if start < bytes.count {
                guard offsets.count < limits.maxRows else { throw CSVError.invalid("File exceeds the \(limits.maxRows)-record limit.") }
                guard bytes.count - start <= limits.maxRecordBytes else { throw CSVError.invalid("Record exceeds the \(limits.maxRecordBytes)-byte limit.") }
                offsets.append(start..<bytes.count); maxColumns = max(maxColumns, columns)
            }
            if cancelled() { throw CSVError.cancelled }
        }
        self.data = data; self.records = offsets; self.delimiter = separator; self.columnCount = maxColumns
    }

    public convenience init(url: URL, delimiter: UInt8? = nil, limits: CSVLimits = CSVLimits(), cancelled: () -> Bool = { false }) throws {
        try self.init(data: Self.readSnapshot(url: url, limits: limits, cancelled: cancelled), delimiter: delimiter, limits: limits, cancelled: cancelled)
    }

    public static func readSnapshot(url: URL, limits: CSVLimits = CSVLimits(), cancelled: () -> Bool = { false }) throws -> Data {
        if cancelled() { throw CSVError.cancelled }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw CSVError.invalid("Open a regular CSV text file.") }
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= limits.maxBytes else { throw CSVError.invalid("File exceeds the \(limits.maxBytes)-byte limit.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var snapshot = Data()
        snapshot.reserveCapacity((attributes[.size] as? NSNumber)?.intValue ?? 0)
        while true {
            if cancelled() { throw CSVError.cancelled }
            let chunk = try autoreleasepool { try handle.read(upToCount: 1024 * 1024) ?? Data() }
            if chunk.isEmpty { break }
            guard chunk.count <= limits.maxBytes - snapshot.count else { throw CSVError.invalid("File exceeds the \(limits.maxBytes)-byte limit.") }
            snapshot.append(chunk)
        }
        return snapshot
    }

    private static func detect(_ data: Data) -> UInt8 {
        var counts: [UInt8: Int] = [44: 0, 59: 0, 9: 0, 124: 0]
        var quoted = false
        for b in data.prefix(65_536) {
            if b == 34 { quoted.toggle() }
            if !quoted {
                if b == 10 || b == 13 { break }
                if counts[b] != nil { counts[b, default: 0] += 1 }
            }
        }
        var best: UInt8 = 44
        for candidate: UInt8 in [59, 9, 124] where counts[candidate]! > counts[best]! { best = candidate }
        return best
    }

    public func row(_ index: Int) throws -> [String] {
        guard records.indices.contains(index) else { throw CSVError.bounds }
        return data.withUnsafeBytes { raw in
            let bytes = raw.bindMemory(to: UInt8.self)
            var values: [String] = [], field: [UInt8] = [], quoted = false
            var i = records[index].lowerBound
            let end = records[index].upperBound
            while i < end {
                let b = bytes[i]
                if b == 34 {
                    if quoted && i + 1 < end && bytes[i + 1] == 34 { field.append(34); i += 1 }
                    else { quoted.toggle() }
                } else if b == delimiter && !quoted {
                    values.append(String(decoding: field, as: UTF8.self)); field.removeAll(keepingCapacity: true)
                } else { field.append(b) }
                i += 1
            }
            values.append(String(decoding: field, as: UTF8.self))
            return values
        }
    }
}
