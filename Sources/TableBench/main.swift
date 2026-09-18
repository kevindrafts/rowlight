import Foundation
import CryptoKit
import Darwin
import TableCore

func hash(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hash = SHA256()
    while try autoreleasepool(invoking: { () throws -> Bool in
        guard let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty else { return false }
        hash.update(data: data)
        return true
    }) {}
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
func now() -> Double { ProcessInfo.processInfo.systemUptime }
do {
    guard CommandLine.arguments.count == 2 else { throw CSVError.invalid("Usage: TableBench /path/to/file.csv") }
    let url = URL(fileURLWithPath: CommandLine.arguments[1])
    try OpenOptions.validate(url)
    let before = try hash(url)
    let start = now()
    let data = try CSVDocument.readSnapshot(url: url)
    let readEnd = now()
    let document = try CSVDocument(data: data)
    let indexEnd = now()
    let cache = RowCache(document: document)
    var firstCell = ""
    let previewRows = min(50, document.rowCount)
    for row in 0..<previewRows {
        let values = try cache.row(row)
        if row == 0 { firstCell = values.first ?? "" }
    }
    let previewEnd = now()
    let after = try hash(url)
    guard before == after else { throw CSVError.invalid("Source hash changed during benchmark.") }
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { throw CSVError.invalid("Could not measure peak RSS.") }
    let result: [String: Any] = [
        "file": url.lastPathComponent, "bytes": document.byteCount,
        "records": document.rowCount, "columns": document.columnCount,
        "readSeconds": readEnd - start, "indexSeconds": indexEnd - readEnd,
        "previewDecodeSeconds": previewEnd - indexEnd, "firstPreviewSeconds": previewEnd - start,
        "previewRows": previewRows, "firstCell": firstCell,
        "peakRSSBytes": usage.ru_maxrss, "cacheRows": cache.count, "cacheAccountedBytes": cache.cost,
        "sourceSHA256Before": before, "sourceSHA256After": after
    ]
    let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: json, as: UTF8.self))
} catch {
    FileHandle.standardError.write(Data("TableBench: \(error)\n".utf8))
    exit(1)
}
