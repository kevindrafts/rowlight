import Foundation
public enum OpenOptions {
    public static func validate(_ url: URL) throws {
        guard url.isFileURL else { throw CSVError.invalid("Only local CSV text files are supported.") }
        guard !["xlsx", "xls", "xlsm", "xlsb"].contains(url.pathExtension.lowercased()) else {
            throw CSVError.invalid("Excel workbooks are not implemented yet. Export the sheet as UTF-8 CSV.")
        }
    }
}
