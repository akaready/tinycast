# Contacts

One launcher command, **Search Contacts**, that opens a palette screen over the Mac's address book:
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
- **Rows are names only, and photos arrive lazily.** The list fetch uses `listKeys` (names, company,
  title, phones, emails): no thumbnail, postal address or birthday. The open card's rest comes from
  `ContactStore.card(for:)` and a row's avatar from `thumbnail(for:)` when the row scrolls into view;
  `ContactsSession.details`, `thumbnails` and `photos` are dropped by `end`, so no photo outlives the screen.
- **One warm list outlives the screen, names only.** The empty-query list is kept in `browseCache` so
  the next open shows at once with no refetch. The `CNContactStoreDidChange` observer stays registered
  while it is held and discards it on any edit; `purge` (feature off, or access gone) drops both.
  A query is never cached. `end` drops everything else.
- **A fetch is validated before it lands.** Each reload cancels the last and bumps a generation; a
  result is applied only if its generation is still current and the task was not cancelled.
  The fetch itself is `@concurrent` and returns `Sendable` values, never `CNContact`.
- **Search is the system's name predicate** (`predicateForContacts(matchingName:)`); an empty query
  lists everyone, capped at 200 cards. The enumeration is ordered by given name (`sortOrder`) and stops
  at the cap, so the 200 are the first alphabetically, not an arbitrary slice; `Contact.sorted` then
  fixes the display order (it sorts by display name, so a company-only card can sit differently from
  the framework's order near the cut).
- **`Model/` is pure.** `Contact`, `ContactQuery` and `ContactFormat` import only Foundation. Labels
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
- **Focus is drawn symmetrically**: a tint plus a full-perimeter border, never an edge accent.
  Animation is opacity only and is dropped under Reduce Motion.

## Actions

Keyboard in the card (the footer pill and the key hints under the card follow the focused stop):

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
| Open-screen list state | `UI/ContactsSession.swift`                   |
| Screen, keyboard, ⌘K menu | `UI/ContactsScreen.swift`                 |
| Field and button actions, labels | `UI/ContactCardLabels.swift`       |
| List and detail pane   | `UI/ContactsView.swift`                      |
| Card stops, focus, monogram hue | `Model/ContactCard.swift`           |
| `CNContactStore` wrapper | `Service/ContactStore.swift`               |
| Settings pane          | `Settings/ContactsSettingsView.swift`        |
| Permission shim        | `Platform/Permissions.swift` (`contactsAccess`) |
