import SwiftUI

struct ContactsSettingsView: View {
    @Environment(AppCore.self) private var core
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: enabledBinding) {
                    SettingsRowTitle(.contactsContacts, "Search contacts from Tinycast")
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

            FeatureCommandsSection(owner: .contacts, anchor: .contactsCommands)
                .settingsEnabled(settings.contactsEnabled)
        }
        .formStyle(.grouped)
        .settingsScrollTarget(.contacts)
        .onAppear { core.contactsCoordinator.refreshAccess() }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { settings.contactsEnabled },
            set: { core.contactsCoordinator.setContactsEnabled($0) })
    }
}
