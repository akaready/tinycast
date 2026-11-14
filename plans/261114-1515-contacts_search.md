---
status: planned
plan_date: 2026-11-14
---

# Contacts search: a launcher command (fork-only)

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
