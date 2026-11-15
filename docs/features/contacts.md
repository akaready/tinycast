# Contacts

One launcher command, **Search Contacts**, that opens a palette screen over the Mac's address book:
a search field, a list, and a detail pane (phones, emails, addresses, birthday, photo). Actions copy a
value, write an email, message or FaceTime a number, or open the card in Contacts.app. Fork-only:
upstream parked it ([not-planned.md](../not-planned.md)), so it lives on `local` and is never sent upstream.

## Invariants

- **Read-only, and notes are never requested.** `ContactStore` is the only file that imports
  `Contacts`, it only ever fetches, and its key list names every field it reads. Contact notes would
  need an extra entitlement and are not shown.
- **`contactsEnabled` is consent**, so only `ContactsCoordinator.setContactsEnabled` writes it: the
  Tinycast dialog first, the macOS prompt second, and the flag only once macOS has granted. It is in
  `SettingsBackupCoverage.deliberatelyExcluded`, so an import cannot grant access, and it has no
  `SettingsFileKey`.
- **Off means invisible.** `applyEnabled` hides `.searchContacts` from the launcher and ends the
  session, so with the setting off no contact is held anywhere. `showContacts` re-checks both the
  flag and the live TCC status, because Settings can revoke a grant without telling us.
- **The list lives only while the screen does.** `ContactsSession.start` runs on appear and `end`
  on disappear, dropping every card (and its photo). `CNContactStoreDidChange` reloads the open list
  through a `NotificationToken` that `end` releases.
- **A fetch is validated before it lands.** Each reload cancels the last and bumps a generation; a
  result is applied only if its generation is still current and the task was not cancelled.
  The fetch itself is `@concurrent` and returns `Sendable` values, never `CNContact`.
- **Search is the system's name predicate** (`predicateForContacts(matchingName:)`); an empty query
  lists everyone, capped at 200 cards so a large address book never loads every photo.
- **`Model/` is pure.** `Contact`, `ContactQuery` and `ContactFormat` import only Foundation. Labels
  arrive already localised from the system; URL building, phone cleanup, address and birthday text
  live in `ContactFormat` with a harness (`Tests/contacts-test.swift`).

## Actions

| Key  | Action                              |
| ---- | ----------------------------------- |
| ↵    | Open in Contacts (`addressbook://`) |
| ⌘↵   | Copy name                           |
| ⌘K   | Message, FaceTime and Copy Phone Number per number; Send Email and Copy Email per address; Copy Address per address |

A card with several values gets one row per value, each stating its label and the value. The palette
menu has no submenus, so the choice is made by picking the row rather than a second level.

## Where things are

| Piece                  | File                                         |
| ---------------------- | -------------------------------------------- |
| Consent, command, row actions | `UI/ContactsCoordinator.swift`        |
| Open-screen list state | `UI/ContactsSession.swift`                   |
| Screen, ⌘K menu        | `UI/ContactsScreen.swift`                    |
| List and detail pane   | `UI/ContactsView.swift`                      |
| `CNContactStore` wrapper | `Service/ContactStore.swift`               |
| Settings pane          | `Settings/ContactsSettingsView.swift`        |
| Permission shim        | `Platform/Permissions.swift` (`contactsAccess`) |
