import AppKit

/// Hands a URL to a chosen app instead of the system default; one path for mail, messages and maps.
@MainActor
enum ContactAppLauncher {
    struct App: Identifiable, Hashable {
        let id: String
        let name: String
        let path: String
    }

    /// A URL of the role's scheme, only to ask which apps open it.
    private static func probe(_ role: ContactAppRole) -> URL? {
        switch role {
        case .mail: URL(string: "mailto:someone@example.com")
        case .messages: URL(string: "sms:5551234")
        case .maps: URL(string: "maps://?q=example")
        }
    }

    /// Every app that opens the role's scheme, one per bundle ID, sorted by name.
    static func handlers(for role: ContactAppRole) -> [App] {
        guard let probe = probe(role) else { return [] }
        var seen = Set<String>()
        return NSWorkspace.shared.urlsForApplications(toOpen: probe)
            .compactMap { url -> App? in
                guard let id = Bundle(url: url)?.bundleIdentifier, seen.insert(id).inserted
                else { return nil }
                return App(id: id, name: displayName(url), path: url.path)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The bundle ID finds a moved app; the path is tried next; nil means the app is gone.
    static func location(of choice: ContactAppChoice) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: choice.bundleID) {
            return url
        }
        let url = URL(fileURLWithPath: choice.path)
        return FileManager.default.fileExists(atPath: choice.path) ? url : nil
    }

    static func displayName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func choice(for app: App) -> ContactAppChoice {
        ContactAppChoice(bundleID: app.id, path: app.path)
    }

    /// Any app, picked in an open panel; nil if cancelled or the pick has no bundle identifier.
    static func chooseApp() -> ContactAppChoice? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
            let id = Bundle(url: url)?.bundleIdentifier
        else { return nil }
        return ContactAppChoice(bundleID: id, path: url.path)
    }

    /// Opens `url` with the chosen app; a missing app or a refusal falls back to the system default.
    static func open(_ url: URL, with choice: ContactAppChoice?) {
        let workspace = NSWorkspace.shared
        guard let choice, let app = location(of: choice) else {
            workspace.open(url)
            return
        }
        Task {
            do {
                _ = try await workspace.open(
                    [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                workspace.open(url)
            }
        }
    }
}
