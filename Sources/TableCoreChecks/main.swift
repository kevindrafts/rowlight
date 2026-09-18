import Foundation
import CryptoKit
import TableCore
struct CheckFailure: Error, CustomStringConvertible { let description: String }
func require(_ condition: @autoclosure () throws -> Bool, _ message: String = "assertion failed") throws {
    if try !condition() { throw CheckFailure(description: message) }
}
func equal<T: Equatable>(_ actual: @autoclosure () throws -> T, _ expected: T) throws {
    let value = try actual()
    try require(value == expected, "Expected \(expected), got \(value)")
}
func rejects(_ action: () throws -> Void) throws {
    do { try action() } catch { return }
    throw CheckFailure(description: "Expected an error")
}
var checks: [(String, () throws -> Void)] = []
checks.append(("harness", { try require(!CommandLine.arguments.contains("--prove-failure"), "deliberate harness failure") }))
 func parse(_ s: String, delimiter: UInt8? = nil) throws -> CSVDocument { try CSVDocument(data: Data(s.utf8), delimiter: delimiter) }
 func testQuotedAndMultiline() throws {
  let d = try parse("a,b,c\r\n\"x,y\",\"say \"\"hi\"\"\",\"line\r\n二\"\r\n")
  try equal(d.rowCount, 2)
  try equal(try d.row(1), ["x,y", "say \"hi\"", "line\r\n二"])
 }
 func testBOMEmptyAndIdentifiers() throws {
  let d = try parse("\u{feff}001,123456789012345678901,,\n,,,")
  try equal(d.rowCount, 2)
  try equal(try d.row(0), ["001", "123456789012345678901", "", ""])
  try equal(try d.row(1), ["", "", "", ""])
 }
 func testEmptyAndBlankRecords() throws {
  try equal(try parse("").rowCount, 0)
  try equal(try parse("\n\n").rowCount, 2)
  try equal(try parse("x\n").rowCount, 1)
 }
 func testDetectionAndOverride() throws {
  try equal(try parse("a;b\n\"x,y\";z").delimiter, 59)
  try equal(try parse("a\tb\nc\td").delimiter, 9)
  try equal(try parse("a;b", delimiter: 44).row(0), ["a;b"])
 }
 func testMalformed() throws {
  for s in ["\"unclosed", "a\"b,c", "\"a\"x,b"] { try rejects { _ = try parse(s) } }
 }
 func testEncoding() throws {
  try rejects { _ = try CSVDocument(data: Data([0xff,0xfe,65,0])) }
  try rejects { _ = try CSVDocument(data: Data([0xc3,0x28])) }
  try rejects { _ = try CSVDocument(data: Data([0])) }
 }
 func testCancellation() throws { try rejects { _ = try CSVDocument(data: Data("a,b".utf8), cancelled: { true }) } }
 func testSourceUnchanged() throws {
  let data = Data("001,\"你好\"\r\n".utf8), copy = data
  let d = try CSVDocument(data: data)
  _ = try d.row(0)
  try equal(data, copy)
 }
checks.append(("testQuotedAndMultiline", testQuotedAndMultiline))
checks.append(("testBOMEmptyAndIdentifiers", testBOMEmptyAndIdentifiers))
checks.append(("testEmptyAndBlankRecords", testEmptyAndBlankRecords))
checks.append(("testDetectionAndOverride", testDetectionAndOverride))
checks.append(("testMalformed", testMalformed))
checks.append(("testEncoding", testEncoding))
checks.append(("testCancellation", testCancellation))
checks.append(("testSourceUnchanged", testSourceUnchanged))
checks.append(("irregular and literal records", {
    let d = try parse("a,b,c\n1\n001, =SUM(A1),2026-01-01,extra\n")
    try equal(d.columnCount, 4)
    try equal(d.row(1), ["1"])
    try equal(d.row(2), ["001", " =SUM(A1)", "2026-01-01", "extra"])
    try rejects { _ = try d.row(-1) }
    try rejects { _ = try d.row(3) }
}))
checks.append(("resource caps", {
    var limits = CSVLimits()
    limits.maxBytes = 3
    try rejects { _ = try CSVDocument(data: Data("abcd".utf8), limits: limits) }
    limits = CSVLimits(); limits.maxRows = 1
    try rejects { _ = try CSVDocument(data: Data("a\nb".utf8), limits: limits) }
    limits = CSVLimits(); limits.maxColumns = 2
    try rejects { _ = try CSVDocument(data: Data("a,b,c".utf8), limits: limits) }
    limits = CSVLimits(); limits.maxRecordBytes = 3
    try rejects { _ = try CSVDocument(data: Data("\"a\nb\"".utf8), limits: limits) }
    _ = try CSVDocument(data: Data("abc".utf8), limits: limits)
}))
checks.append(("real file SHA256 invariance and file limits", {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".csv")
    let bytes = Data("\u{feff}id,note\r\n001,\"你好\nworld\"\r\n".utf8)
    try bytes.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let before = SHA256.hash(data: try Data(contentsOf: url))
    let d = try CSVDocument(url: url)
    try equal(d.row(1), ["001", "你好\nworld"])
    let cache = RowCache(document: d)
    _ = try cache.row(1)
    _ = try d.find("world")
    var grid = GridModel(document: d)
    grid.select(row: 0, column: 1)
    try equal(grid.value(), "你好\nworld")
    grid.hasHeader = false
    _ = try grid.value()
    try require(before == SHA256.hash(data: try Data(contentsOf: url)), "File hash changed")
    var limits = CSVLimits(); limits.maxBytes = 2
    try rejects { _ = try CSVDocument(url: url, limits: limits) }
    try rejects { _ = try CSVDocument(url: url, cancelled: { true }) }
}))
checks.append(("UTF8 scalar boundaries and delayed cancellation", {
    for bytes: [UInt8] in [[0xed,0xa0,0x80], [0xf4,0x90,0x80,0x80], [0xe0,0x80,0x80], [0xc2], [0x80]] {
        try rejects { _ = try CSVDocument(data: Data(bytes)) }
    }
    try equal(parse("é,😀,\u{10ffff}").row(0), ["é", "😀", "\u{10ffff}"])
    var calls = 0
    try rejects { _ = try CSVDocument(data: Data(repeating: 97, count: 100_000), cancelled: { calls += 1; return calls > 2 }) }
}))
checks.append(("bounded LRU cache", {
    let d = try parse("a,b\nc,d\ne,f\ng,h")
    let cache = RowCache(document: d, maxRows: 2, maxBytes: 1024)
    try equal(cache.row(0), ["a", "b"])
    try equal(cache.count, 1)
    _ = try cache.row(1); _ = try cache.row(0); _ = try cache.row(2)
    try equal(cache.count, 2)
    try require(cache.cost <= 1024)
    let tiny = RowCache(document: d, maxRows: 2, maxBytes: 1)
    try equal(tiny.row(0), ["a", "b"])
    try equal(tiny.count, 0)
}))
checks.append(("header selection keyboard and literal copy", {
    var grid = GridModel(document: try parse("id,note,extra\n001,\"line\n二\"\n2,z,last"))
    try equal(grid.rowCount, 2)
    try equal(grid.title(1), "note")
    grid.select(row: 0, column: 0)
    try equal(grid.value(), "001")
    grid.move(rows: 0, columns: 1)
    try equal(grid.value(), "line\n二")
    grid.move(rows: 0, columns: 1)
    try equal(grid.value(), "")
    grid.move(rows: 50, columns: 50)
    try equal(grid.selection, Cell(row: 1, column: 2))
    try equal(grid.value(), "last")
    grid.hasHeader = false
    try equal(grid.rowCount, 3)
    try equal(grid.title(1), "Column 2")
    grid.select(row: 0, column: 0)
    try equal(grid.value(), "id")
    var empty = GridModel(document: try parse(""))
    empty.move(rows: 1, columns: 1)
    try equal(empty.selection, nil)
}))
checks.append(("find wrap multiline and cancellation", {
    let d = try parse("name,note\nAlpha,\"line\n二\"\nBETA,alpha")
    try equal(d.find("alpha", firstRow: 1), Cell(row: 1, column: 0))
    try equal(d.find("ALPHA", after: Cell(row: 1, column: 0), firstRow: 1), Cell(row: 2, column: 1))
    try equal(d.find("alpha", after: Cell(row: 2, column: 1), firstRow: 1), Cell(row: 1, column: 0))
    try equal(d.find("line\n二"), Cell(row: 1, column: 1))
    try equal(d.find("missing"), nil)
    try equal(d.find(""), nil)
    try rejects { _ = try d.find("x", cancelled: { true }) }
}))
checks.append(("cancel and stale completion protection", {
    let gate = RequestGate()
    let old = gate.begin(), current = gate.begin()
    try require(!gate.isCurrent(old), "Old load/search can still publish")
    try require(gate.isCurrent(current))
    gate.cancel()
    try require(!gate.isCurrent(current), "Cancelled work can still publish")
    let next = gate.begin()
    try require(gate.isCurrent(next))
}))
checks.append(("local file opening policy", {
    try OpenOptions.validate(URL(fileURLWithPath: "/tmp/example.csv"))
    try OpenOptions.validate(URL(fileURLWithPath: "/tmp/example.tsv"))
    try rejects { try OpenOptions.validate(URL(string: "https://example.com/file.csv")!) }
    try rejects { try OpenOptions.validate(URL(fileURLWithPath: "/tmp/example.XLSX")) }
    try rejects { try OpenOptions.validate(URL(fileURLWithPath: "/tmp/example.xls")) }
}))
var failures = 0
for (name, check) in checks {
    do { try check(); print("PASS \(name)") }
    catch { failures += 1; print("FAIL \(name): \(error)") }
}
print("\(checks.count - failures)/\(checks.count) checks passed")
exit(failures == 0 ? 0 : 1)
