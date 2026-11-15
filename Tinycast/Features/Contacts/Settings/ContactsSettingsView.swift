import SwiftUI

struct ContactsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsRowTitle(.contactsContacts, "Contacts in Tinycast")
                    Text("Reads your contacts and never changes them.")
                }
            }
            .settingsAnchor(.contactsContacts)

            if settings.contactsEnabled, core.contactsCoordinator.access == .notDetermined {
                Section {
                    SettingsRow(
                        title: String(localized: "Contacts access is needed"),
                        subtitle: String(localized: "Needed to search your contacts.")
                    ) {
                        Button("Allow Contacts Access…") {
                            core.contactsCoordinator.setContactsEnabled(true)
                        }
                    }
                }
            } else if core.contactsCoordinator.access == .denied {
                Section {
                    SettingsRow(
                        title: String(localized: "Contacts access is off"),
                        subtitle: String(localized: "Allow it in Privacy & Security ▸ Contacts.")
                    ) {
                        Button("Open System Settings…") { Permissions.openContactsSettings() }
                    }
                }
            }

            Section {
                ContactAppPicker(role: .mail, choice: appBinding(.mail)) {
                    SettingsRowTitle(.contactsApps, "Mail App")
                    Text("Opens when you write to an email address.")
                }
                ContactAppPicker(role: .messages, choice: appBinding(.messages)) {
                    SettingsRowTitle(.contactsApps, "Messages App")
                    Text("Opens when you message a phone number.")
                }
                ContactAppPicker(role: .maps, choice: appBinding(.maps)) {
                    SettingsRowTitle(.contactsApps, "Maps App")
                    Text("Opens when you look up an address.")
                }
            } header: {
                SettingsSectionHeader(.contactsApps)
            }
            .settingsEnabled(settings.contactsEnabled)

            Section {
                actionRow(.phone) { SettingsRowTitle(.contactsActions, "Phone Number") }
                actionRow(.email) { SettingsRowTitle(.contactsActions, "Email Address") }
                actionRow(.address) { SettingsRowTitle(.contactsActions, "Postal Address") }
                actionRow(.contact) { SettingsRowTitle(.contactsActions, "Contact") }
                Button("Reset to Defaults") { settings.contactActions = .standard }
                    .disabled(settings.contactActions.isStandard)
            } header: {
                SettingsSectionHeader(.contactsActions)
            } footer: {
                Text("What ↵ and ⌘↵ do. ⌘K always offers every action.")
            }
            .settingsEnabled(settings.contactsEnabled)

            FeatureCommandsSection(owner: .contacts, anchor: .contactsCommands)
                .settingsEnabled(settings.contactsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.contacts)
        .onAppear { core.contactsCoordinator.refreshAccess() }
    }

    private func appBinding(_ role: ContactAppRole) -> Binding<ContactAppChoice?> {
        Binding(
            get: { settings.contactApps[role] },
            set: { settings.contactApps[role] = $0 })
    }

    private func actionRow<Title: View>(
        _ target: ContactTarget, @ViewBuilder title: () -> Title
    ) -> some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.lg) {
                actionPicker(target, command: false)
                actionPicker(target, command: true)
            }
        } label: {
            title()
        }
    }

    private func actionPicker(_ target: ContactTarget, command: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(verbatim: command ? "⌘↵" : "↵").foregroundStyle(.secondary)
            Picker(
                selection: Binding(
                    get: { settings.contactActions.action(for: target, command: command) },
                    set: { settings.contactActions.set($0, for: target, command: command) })
            ) {
                ForEach(target.actions, id: \.self) { action in
                    Text(action.title(for: target == .contact ? nil : Self.kind(target))).tag(action)
                }
            } label: {
                EmptyView()
            }
            .labelsHidden()
            .fixedSize()
        }
    }

    private static func kind(_ target: ContactTarget) -> ContactField.Kind? {
        switch target {
        case .phone: .phone
        case .email: .email
        case .address: .address
        case .birthday: .birthday
        case .contact: nil
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.contactsEnabled },
            set: { core.contactsCoordinator.setContactsEnabled($0) })
    }
}
