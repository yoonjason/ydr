final class MockPasteboard: PasteboardWriting {
    var writtenStrings: [String] = []

    func write(_ string: String) {
        writtenStrings.append(string)
    }
}
