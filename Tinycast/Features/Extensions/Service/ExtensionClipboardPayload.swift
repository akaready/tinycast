import AppKit

/// What `Clipboard.read()` hands an extension, shaped like Raycast's.
enum ExtensionClipboardPayload {
    static func read(from pasteboard: NSPasteboard) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let text = pasteboard.string(forType: .string) { payload["text"] = text }
        // A Finder copy is `public.file-url`, which `string(forType: .URL)` never sees.
        let files = pasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
        if let file = files?.first { payload["file"] = file.absoluteString }
        return payload
    }
}
