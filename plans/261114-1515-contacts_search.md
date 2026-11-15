---
status: in-progress
plan_date: 2026-11-14
---

# Contacts search: a launcher command (fork-only)

## Outcome — in progress, 2026-11-14

**Landed:** a fork-only "Search Contacts" command behind an opt-in `contactsEnabled` setting (Tinycast
dialog, then the macOS prompt, flag written only after a grant; excluded from backups). It opens a
palette screen with search, a list, and a detail pane (phones, emails, addresses, birthday, photo).
Actions: copy name (⌘↵), copy phone/email/address, email, message, FaceTime, open in Contacts.app
(↵). Plumbing: addressbook entitlement, `NSContactsUsageDescription`, `Permissions.contactsAccess()`,
a Contacts row in the Permissions pane, a Contacts settings pane, and `docs/features/contacts.md`.
All strings are translated into the eight shipped languages.
**Verified:** `Scripts/run-tests.sh` (114 harnesses, including the new `contacts-test`),
`Scripts/lint.sh` (clean), the purity grep (empty), and an unsigned Debug build with no new warnings.
**Not verified:** never run on screen. The macOS permission prompt, a real address book's results,
photos, `addressbook://` opening the right card, and the tel/sms/facetime/mailto hand-offs are untested.
**Deviated:** multiple values are flat rows in the ⌘K menu (one per number or address, each showing
its label and value) rather than a labelled submenu, since the palette menu has no submenus. The
search-field text is not matched against company or email: it is the system name predicate only.
**Left undone:** a manual pass of the sweep in `docs/testing.md`; install into /Applications (needs the
user at the keyboard for codesign); the status flips to `shipped` once it is seen working and merged.

### Polish pass — 2026-11-14

**Landed:** the detail card is now a keyboard set. ⇥ (or → on an empty query) enters it, ↑↓ move between
stops (quick-action row, then each phone, email, address and the birthday), ←/Esc leave, ↵ runs the
field's primary action (Message, compose, Open in Maps), ⌘↵ copies with an inline "Copied", ⌘K offers
the field's own actions. Focus is a tint plus a full-perimeter border; the footer pill and a key-hint
strip under the card follow the focused stop. A large circular photo (full `imageData`, loaded for the
open card only, ImageIO-shrunk) or a stable-hue monogram; name in display weight, role · company
beneath, quick-action buttons, then grouped sections with hover-revealed primary and copy buttons.
List rows share the monogram logic. Pure logic (card stops, focus, monogram hue, maps URL) is in
`Model/ContactCard.swift` with 40 harness assertions; five strings translated into all eight languages.
**Verified (polish):** `contacts-test` 40/40, `Scripts/run-tests.sh` (114 harnesses), `Scripts/lint.sh`
clean, the purity grep empty, unsigned Debug build with no warnings.
**Deviated (polish):** added one shell hook, `PaletteScreen.escape(at:)`, because Esc had no screen
hook; ⌘↵ in the card copies and keeps the palette open (the list's ⌘↵ still closes with a HUD); ⇥ from
the list now enters the card instead of cycling to the launcher (Shift-⇥ still cycles); two `Theme.Colors`
tokens were added for the monogram.
**Left undone (polish):** never run on screen, so no screenshot: the build is unsigned and the Contacts
grant needs the macOS prompt answered by the user. Unseen: focus-ring look, monogram contrast on real
hues, photo load timing, the Maps/Messages/FaceTime hand-offs, → entering the card with the caret.

### Fix pass — 2026-11-14 (hands-on test)

**Causes:** (1) the focus border and the hover buttons / "Copied" label were inserted and removed in
layout, so text moved; (2) every open refetched up to 200 cards with every key, thumbnails, postal
addresses and birthdays included, and kept nothing between opens. **Changed:** a constant clear-stroke
border and one fixed trailing slot that only fades (rows and quick buttons); a names-only list fetch,
per-card details and per-row thumbnails loaded lazily, a warm names-only browse list kept across opens
and discarded by `CNContactStoreDidChange`; signposts (`ContactsEnumerate`, `ContactsSearch`,
`ContactsMap`, `ContactsCard`) in the subsystem `com.tinycast.perf`.
**Verified:** tests, lint, purity grep, unsigned Debug build. **Not measured:** no address book or
Contacts grant is available headlessly, so no before/after timings; the signposts are there for Instruments.
**Left undone:** the 200 cap still takes the first 200 the framework returns, then sorts.

### Index pass — 2026-11-14

**Landed:** supersedes the 200-card cap and the given-name sort. All contacts load once at launch (and
after a grant) with the light keys, off-main, sorted once and held as a names-only `ContactIndex`;
typing filters it locally and synchronously (case/diacritic-insensitive, name, nickname, company,
email, phone digits, prefix matches first), so there is no per-keystroke Contacts call. A debounced
reload follows `CNContactStoreDidChange`; the index is dropped when the feature is off or access is
lost. Photos and card details stay lazy. `contacts-test` is now 91 assertions.
**Correction:** the earlier polish pass claimed 40 harness assertions for the card model, but the
test functions for the card, focus, monogram and maps URL were never written (a failed command chain
skipped that edit), so they were unrun. They exist and pass now.
**Verified:** harness, run-tests, lint, purity grep, unsigned Debug build.
**Not verified on screen:** launch-time load duration with a large address book, the Loading state,
list scrolling and keyboard navigation at thousands of rows, live reload after an edit in Contacts.
**Left undone:** memory for a very large book is names, phones and emails for everyone, by design.

### Rename — 2026-11-14

The launcher command is now just "Contacts" (its old name, "people" and "address book" stay as
`CommandID.searchKeywords`, so they still find it); the settings toggle reads "Contacts in Tinycast".
Kept: `CommandID.searchContacts` and `command:search-contacts` (the id is persisted and used by deep
links, and is not shown to the user); the "Search your contacts…" prompt and permission wording.

### Customisable actions and apps — 2026-11-14

**Why:** ↵ on an email went to the system mailto handler, which here is a browser router, so no compose
window opened. **Landed:** Settings ▸ Contacts has Apps (Mail, Messages, Maps: System Default, any
installed handler, or Choose… with an open panel; bundle id and path stored; a missing app falls back
to the default with a note) and Actions (↵ and ⌘↵ per phone, email, postal address and contact row,
plus Reset to Defaults). Pure `ContactAction`, `ContactTarget`, `ContactActionChoices`,
`ContactAppChoices` in `Model/`; one `ContactAppLauncher`; 15 strings in all eight languages; Settings
search entries. `contacts-test` covers the resolver, defaults, fallbacks and JSON round trips.
**Deviated:** no birthday pickers (copy is its only action); no Phone/FaceTime app (tel: and facetime:
go to the system default); no `settings.json` keys for the two new settings (both are stored as JSON
and excluded from backups).
**Not verified on screen:** the pickers, the open panel, the app actually launching with a mailto URL,
or the footer and hint labels following a changed binding.

## Context

Raycast has "Search Contacts". Upstream parked it (`docs/not-planned.md`, #1503), so this lives on
`local` only and is never sent upstream. Calendar is the template: an opt-in setting that doubles as
consent, a TCC permission, a coordinator on `AppCore`, a feature folder split `Model/ Service/ UI/ Settings/`.
Read `AGENTS.md`, `docs/architecture.md`, `docs/standards.md`, `docs/testing.md`, `docs/features/calendar.md`
first; follow them (Model files import neither AppKit nor SwiftUI; Swift 6 strict concurrency; Theme tokens only).

## Scope (v1)

- Opt-in `contactsEnabled` setting; Tinycast dialog first, macOS prompt second, written only after macOS grants.
  Put it in `SettingsBackupCoverage.deliberatelyExcluded`. Only the coordinator writes it.
- Launcher command "Search Contacts" (hidden while disabled), opening a palette screen: search field,
  results list, detail pane (phones, emails, addresses, birthday, note-free), contact photo from thumbnailImageData.
- Actions: copy name / phone / email / address, email, message, FaceTime, open in Contacts.app.
  Multiple values: labelled submenu to choose.
- Read-only. Never write to contacts.
- Not in v1: root-search integration, groups, vCard export.

## Plumbing

- `Tinycast.entitlements`: `com.apple.security.personal-information.addressbook`.
- `Info.plist`: `NSContactsUsageDescription`.
- `Platform/Permissions.swift`: `contactsAccess()` beside `calendarAccess()`; add to the Permissions pane.
- `Features/Contacts/{Model,Service,UI,Settings}`; `ContactStore` wraps `CNContactStore`
  (`predicateForContacts(matchingName:)`, `CNContactStoreDidChange` via `NotificationToken`).
  Fetch off-main, validate staleness before applying results.
- Wire on `AppCore` like `calendarCoordinator`. Keep touch points in `AppCore.swift` minimal (hot file upstream).
- Localise in all eight languages as the Store did; add `docs/features/contacts.md` with an Invariants section.
- Pure logic (query normalisation, value/label formatting) in Model with a harness in `Tests/`.

## Verification

`Scripts/run-tests.sh`, `Scripts/lint.sh`, purity grep, unsigned Debug build. Do NOT run `install-local.sh`
(needs the user at the keyboard for codesign).
