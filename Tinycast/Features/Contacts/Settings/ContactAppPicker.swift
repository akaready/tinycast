import SwiftUI

/// Picks the app that opens one kind of hand-off: the system default, an installed handler, or any app.
struct ContactAppPicker<Label: View>: View {
    let role: ContactAppRole
    @Binding var choice: ContactAppChoice?
    @ViewBuilder var label: Label
    @State private var installed: [ContactAppLauncher.App] = []

    private static var chooseTag: String { "\u{0}choose" }

    /// Installed handlers, plus a picked app that is not among them, so the menu can show it.
    private var listed: [ContactAppLauncher.App] {
        guard let choice, !installed.contains(where: { $0.id == choice.bundleID }) else {
            return installed
        }
        let name = ContactAppLauncher.location(of: choice).map(ContactAppLauncher.displayName)
            ?? URL(fileURLWithPath: choice.path).deletingPathExtension().lastPathComponent
        return installed + [ContactAppLauncher.App(id: choice.bundleID, name: name, path: choice.path)]
    }

    private var selection: Binding<String> {
        Binding(
            get: { choice?.bundleID ?? "" },
            set: { tag in
                if tag == Self.chooseTag {
                    if let picked = ContactAppLauncher.chooseApp() { choice = picked }
                } else if tag.isEmpty {
                    choice = nil
                } else if let app = listed.first(where: { $0.id == tag }) {
                    choice = ContactAppLauncher.choice(for: app)
                }
            })
    }

    var body: some View {
        Picker(selection: selection) {
            Text("System Default").tag("")
            if !listed.isEmpty { Divider() }
            ForEach(listed) { app in Text(app.name).tag(app.id) }
            Divider()
            Text("Choose…").tag(Self.chooseTag)
        } label: {
            label
        }
        .onAppear { installed = ContactAppLauncher.handlers(for: role) }
        if let choice { detail(choice) }
    }

    /// The app's icon and path, or the note that it is gone and the default is used.
    @ViewBuilder
    private func detail(_ choice: ContactAppChoice) -> some View {
        if ContactAppLauncher.location(of: choice) != nil {
            HStack(spacing: Theme.Spacing.sm) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: choice.path))
                    .resizable()
                    .frame(width: Theme.Size.settingsSidebarGlyph, height: Theme.Size.settingsSidebarGlyph)
                Text(choice.path)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("App not found. Using the system default.")
                .foregroundStyle(.secondary)
        }
    }
}
