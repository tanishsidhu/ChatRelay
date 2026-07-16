import AppKit
import Foundation

public enum Clipboard {
    public struct Snapshot: Sendable {
        let items: [[String: Data]]
    }

    public static func snapshot() -> Snapshot {
        var items: [[String: Data]] = []
        for item in NSPasteboard.general.pasteboardItems ?? [] {
            var values: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type.rawValue] = data
                }
            }
            items.append(values)
        }
        return Snapshot(items: items)
    }

    public static func setString(_ string: String) throws {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(string, forType: .string) else {
            throw ComposerWriteError.clipboardUnavailable
        }
    }

    public static func restore(_ snapshot: Snapshot) {
        NSPasteboard.general.clearContents()
        guard !snapshot.items.isEmpty else { return }

        let items = snapshot.items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        NSPasteboard.general.writeObjects(items)
    }
}
