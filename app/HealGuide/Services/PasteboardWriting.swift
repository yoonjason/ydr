import AppKit

protocol PasteboardWriting {
    func write(_ string: String)
}

struct SystemPasteboard: PasteboardWriting {
    func write(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }
}
