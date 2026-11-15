# Contacts

One launcher command, **Contacts** (internally `.searchContacts`, found by "search contacts" and "people" too), that opens a palette screen over the Mac's address book:
a search field, a list, and a detail pane (photo, quick actions, phones, emails, addresses, birthday). Actions copy a
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
- **One in-memory index of everyone, names only, built at launch.** `applyEnabled` (launch, and right
  after a grant) calls `ContactsSession.warm`, which loads every contact once with `listKeys`
  (identifier, names, nickname, company, title, phones, emails; no photo, postal address or birthday),
  sorts it once with `Contact.sorted` and wraps it in `ContactIndex`. There is no result cap. The
  index is the only list state that outlives the screen; it holds no photos.
- **Its lifetime is the feature's.** `purge` drops it, and stops the change observer, when the setting
  turns off or access is lost (`warm` and `start` re-check the live TCC status). While the first load
  runs the screen shows "Loading…" and fills in when it lands.
- **`CNContactStoreDidChange` is the reload signal.** It stays registered while the index is held; a
  burst is debounced (600 ms) and the index is rebuilt in the background while the old one keeps
  serving. A reload is superseded by a newer one or a purge through `generation`.
- **Photos and the rest of a card are lazy.** A row's thumbnail is fetched when it scrolls into view
  (`thumbnail(for:)`), the open card's addresses and birthday by `card(for:)`; `details`, `thumbnails`
  (capped at 300) and `photos` are dropped by `end`, so no photo outlives the screen. The list is a
  `LazyVStack`, so thousands of rows cost only the visible ones.
- **A load is validated before it lands.** The fetch is `@concurrent` and returns `Sendable` values,
  never `CNContact`; its result is applied only if its generation is still current.
- **Search is local and synchronous.** `ContactIndex.matching` folds case and diacritics, needs every
  query word to match, and ranks name-word prefixes, then company-word prefixes, then name substrings,
  then email, phone digits and other company text; ties keep alphabetical order. No keystroke calls
  `CNContactStore`, so nothing needs cancelling.
- **`Model/` is pure.** `Contact`, `ContactQuery`, `ContactIndex`, `ContactCard` and `ContactFormat` import only Foundation. Labels
  arrive already localised from the system; URL building, phone cleanup, address and birthday text
  live in `ContactFormat` with a harness (`Tests/contacts-test.swift`).

- **Photos come from two keys, and only the open card loads the big one.** The list fetches
  `thumbnailImageData` for every row; the detail pane asks `ContactStore.photo(for:maxPixel:)` for the
  selected card's `imageData` (gated on `imageDataAvailable`), shrunk with ImageIO before it leaves the
  service. `ContactsSession.photos` keeps a few; until one arrives the thumbnail
  stands in at the same size, so nothing moves. A card with no photo gets a monogram in a hue from
  `ContactMonogram.hue` (FNV-1a of the display name, so it is stable across launches), with
  fixed saturation and brightness under white ink; list rows and the card use the same logic.
- **The card is a keyboard set, and `ContactCardFocus` is its whole model.** Stops are the quick-action
  row (one stop, buttons inside it) then one per field in the order phones, emails, addresses,
  birthday (`ContactCard`). Focus lives on `ContactsSession` and is reset by a selection change, a new
  query or `end`; the palette's search field keeps real focus throughout, so typing still searches.
- **A row never changes size or text position between states.** The focus border is always drawn
  (clear when unfocused), and the hover buttons and "Copied" share one fixed trailing slot and only
  fade.
- **What ↵ and ⌘↵ do is a setting, resolved in `Model/`.** `ContactTarget` (phone, email, address,
  birthday, the contact row) offers a fixed list of `ContactAction`s and a default for each key;
  `ContactActionChoices` stores only the differences (JSON under `AppSettingsKey.contactActions`) and
  falls back to the default for anything the target no longer offers. The footer pill, the key hints,
  the hover buttons and the ⌘K shortcut labels all read the resolved action. ⌘K still lists every
  action for the target, whatever is bound.
- **Hand-offs can name an app, and a missing app falls back.** `ContactAppChoices` (mail, messages,
  maps) holds a bundle identifier and a path; `ContactAppLauncher.open` finds the app by identifier,
  then path, and opens the URL with it, else uses the system default (the picker shows a note when the
  app is gone). Nothing changes system defaults. Both settings keys are in
  `SettingsBackupCoverage.deliberatelyExcluded` (machine-specific paths; action choices stay local
  until backup supports them) and have no `settings.json` key yet.
- **Focus is drawn symmetrically**: a tint plus a full-perimeter border, never an edge accent.
  Animation is opacity only and is dropped under Reduce Motion.

## Actions

Keyboard in the card (the footer pill and the key hints under the card follow the focused stop; the ↵ and ⌘↵ actions below are the defaults, configurable in Settings ▸ Contacts ▸ Actions):

| Key        | In the list                              | On the card                                          |
| ---------- | ---------------------------------------- | ---------------------------------------------------- |
| ⇥ or →     | Enter the card (→ only on an empty query) | ⇥ next stop, past the last back to the list; → next quick action |
| ↑ ↓        | Move the selection                       | Previous or next stop (clamped)                      |
| ← or Esc   | Caret / palette back                     | Back to the list (← steps left inside the quick row first) |
| ↵          | Open in Contacts                         | Phone: Message. Email: compose. Address: Open in Maps. Birthday: copy. Quick row: that button |
| ⌘↵         | Copy name (closes)                       | Copy the value and show "Copied" inline (palette stays open) |
| ⌘K         | The contact's actions                    | That field's actions                                 |


| Key  | Action                              |
| ---- | ----------------------------------- |
| ↵    | Open in Contacts (`addressbook://`) |
| ⌘↵   | Copy name                           |
| ⌘K   | Message, FaceTime and Copy Phone Number per number; Send Email and Copy Email per address; Copy Address per address (with a field focused: Message, FaceTime, Call, Copy for a number; Send Email, Copy; Open in Maps, Copy) |

A card with several values gets one row per value, each stating its label and the value. The palette
menu has no submenus, so the choice is made by picking the row rather than a second level.

## Where things are

| Piece                  | File                                         |
| ---------------------- | -------------------------------------------- |
| Consent, command, row actions | `UI/ContactsCoordinator.swift`        |
| Index, screen state    | `UI/ContactsSession.swift`                   |
| In-memory index and filter | `Model/ContactIndex.swift`               |
| Screen, keyboard, ⌘K menu | `UI/ContactsScreen.swift`                 |
| Field and button actions, labels | `UI/ContactCardLabels.swift`       |
| List and detail pane   | `UI/ContactsView.swift`                      |
| Card stops, focus, monogram hue | `Model/ContactCard.swift`           |
| `CNContactStore` wrapper | `Service/ContactStore.swift`               |
| Settings pane, app picker | `Settings/ContactsSettingsView.swift`, `Settings/ContactAppPicker.swift` |
| Action and app choices | `Model/ContactAction.swift`                  |
| Opening with a chosen app | `Service/ContactAppLauncher.swift`        |
| Permission shim        | `Platform/Permissions.swift` (`contactsAccess`) |
