---
status: in-progress
plan_date: 2026-11-08
---

# Extension Store: a top-level launcher command

## Outcome — in progress 2026-11-08

**Landed:** Steps 1, 2 and 4 on `feature/extension-store`: browse/search paging, detail and README
fetching with `ext-store-test` cases on saved fixtures, `ExtensionStoreSession`, and
`ExtensionStoreScreen` with its detail pane. Nothing can open the screen yet.
**Verified:** `ext-store-test`, `ext-test`, `lint.sh`, the Model purity grep, and an unsigned Debug
build all pass. Not yet run in the app, so nothing has been seen on screen.
**Deviated:** `ExtensionListing` gained `categories`, `updatedAt`, `storeURL` and a derived
`storeHandle` (the detail lookup needs the owner's handle). "Open" on an installed extension opens
its Settings page. Paging fires from both the selection and rows scrolling into view.
**Left undone:** Step 3 wiring and naming (waits on Q-A), Step 5 Settings (Q-B), Step 6 docs,
translations in all eight languages, the manual pass, memory and leak numbers. Q-C (upstream) is open.

## Context

Tinycast already installs Raycast-store extensions, but only from Settings → Extensions → Install New
→ **Search extensions** (`Features/Extensions/Settings/ExtensionStorePanel.swift`). That panel loads
one debounced page of search results, shows a prompt instead of anything to browse, and has no detail,
uninstall or update. The goal is a Store you open from the launcher like Clipboard History: browse the
popular list, search, open an extension's page (screenshots, README, commands, changelog) and install,
update or uninstall in place.

This lives in our fork (`akaready/tinycast`, branch `feature/extension-store`) and ships to the local
build through the `local` branch. Upstream is unlikely to take it as is: `docs/not-planned.md` says
"Tinycast is not a copy of Raycast" and that Raycast-compatibility work "has stopped". If we want it
upstream later, that starts with a feature-request issue (CONTRIBUTING: settle it before building).

## Data sources (verified 2026-11-08 with plain requests, no auth)

| Need | Endpoint | Notes |
|---|---|---|
| Browse, most downloaded first | `https://www.raycast.com/frontend_api/extensions?page=N&platform=macOS` | 10 per page, `total_results` ≈ 3,500; `sort=` is ignored |
| Search | `https://www.raycast.com/frontend_api/extensions/search?q=…&page=N&platform=macOS` | already used; empty `q` returns an unordered list, so browse uses the list endpoint |
| Detail page | `https://www.raycast.com/api/v1/extensions/<handle>/<name>` | already used for lookup; also returns `metadata[]` (screenshot URLs on `files.raycast.com`), `changelog.versions[]`, `commands[]` with title/description, `readme_url`, `categories`, `store_url`, `updated_at` |
| README body | `readme_url` rewritten from `github.com/raycast/extensions/tree/<sha>/…` to `raw.githubusercontent.com/raycast/extensions/<sha>/…` | one file per extension, fetched only when its page opens |
| Install | `download_url` (prebuilt zip) | unchanged: `ExtensionInstaller.install(listing)` |

Not available as JSON: Featured, New/Recent, server-side category filtering. v1 skips them.

**Terms posture.** Raycast's Terms (§VI) forbid scraping and bulk data gathering. The Store fetches only
what the person is looking at, as the store's own site does: a page of the list as they scroll, one
detail record and one README when they open an extension. No background prefetch, no full-catalog
crawl, no mirror. Responses live in memory for the session; nothing new is written to Caches.

## Design

**Entry point.** A new built-in command, `CommandID.extensionStore` ("Extension Store", English alias
"Store"), routed by `LauncherCoordinator.runCommand` to a new `PaletteMode.extensionStore`. It is an
`AppEntry.Kind.command` row like Calculator History, owned by `SettingsTab.extensions` in
`ownedCommands`, so it gets an alias and hotkey for free. It is hidden while
`AppSettings.extensionsEnabled` is off, through `appIndex.setCommandsVisible`, the way Clipboard
hides its commands. Deeplink `tinycast://command/extension-store` is classified in
`DeepLinkConsentPolicy` like other commands that only open a screen.

**Screen.** `Features/Extensions/UI/ExtensionStoreScreen.swift`, a `PaletteScreen`. List on the left,
the selected extension's page on the right (the split `ExtensionListView` and Clipboard History
already use; the layout is duplicated inside `Features/Extensions/`, per AGENTS.md).

- Row: icon, title, author, download count, and a state tag (Installed / Update).
- Empty query: the popular list, loading the next page as the selection nears the end.
- Typing: debounced search, paged the same way.
- A filter accessory: All / Installed / Updates.
- Detail pane: header (icon, title, author, downloads, updated, categories), screenshots (selected
  extension only, downsampled to the pane width), commands with descriptions, README through
  `ExtensionMarkdownView`, newest changelog entry.
- Actions (↵ and ⌘K): Install, or Open when installed; Update when behind; Uninstall (confirmed through
  `core.confirm`); Open in Browser (`store_url`); Copy Link.

**State.** `ExtensionStoreSession` (`@Observable`, `Features/Extensions/UI/`) owns the query, loaded
pages, selection, per-extension detail and README, and in-flight installs. Every async result checks
that its query and selection are still current before applying (AGENTS.md: stale results). Opening the
Store runs `ExtensionManager.checkForUpdates()` once so Update tags are accurate.

**Reuse, not rewrite.**
- `ExtensionStoreClient`: add `browse(page:)`, pass `page` through `search`, add `detail(handle:name:)`
  and `readme(url:)`. Same private `.ephemeral`, `urlCache = nil` session.
- `ExtensionStoreResponse` (Model, Foundation-only): decode the extra list fields (`categories`,
  `updated_at`, `store_url`) and a new `ExtensionStoreDetail` (screenshots, commands, changelog,
  README URL). Add any new Model file to the fixed list in `Scripts/run-tests.sh`.
- `ExtensionManager.installFromStore / update / uninstall`, `ExtensionVersionStore`,
  `ExtensionIconCache.loadRemoteAsync` for icons and screenshots: unchanged.
- **Settings:** the "Search extensions" route opens the Store screen and `ExtensionStorePanel` is
  deleted, so there is one store UI, not two. *(Open question Q-B.)*

## Steps

1. Model + client: list/detail/README decoding and paging, with `ext-store-test` cases from saved
   JSON fixtures (no network in tests).
2. `ExtensionStoreSession` with paging, search debounce, stale-result guards, filter, update check.
3. Command plumbing: `CommandID`, `PaletteMode`, `RootPaletteView`, `LauncherCoordinator`,
   `ownedCommands`, visibility gate, deeplink policy, localization in all eight languages
   (`./Scripts/sync-strings.sh`).
4. `ExtensionStoreScreen`: list, detail pane, actions, keyboard paths, empty/error/offline states.
5. Settings route → Store; remove `ExtensionStorePanel`.
6. Docs: `docs/features/extensions.md` (Installing extensions, Updates: "at no other time" changes),
   `docs/features/launcher.md` if the command table lists built-ins.

## Verification

- `./Scripts/run-tests.sh`, `./Scripts/lint.sh`, Model purity grep, clean Debug build with no new
  warnings (testing.md, Definition of done).
- Manual pass in the Debug channel: open from the launcher and by alias, browse 5+ pages, search,
  open several pages with screenshots, install, update, uninstall, extensions off hides the command,
  offline shows an error state.
- Memory: idle, palette open, Store browsing with screenshots (peak), palette closed and settled;
  stays under 100 MB and returns to baseline. Leaks checked with `leaks` after closing the palette.
- Then merge into `local` and rebuild the installed app with `Scripts/install-local.sh`.

## Open questions

- **Q-A Name:** "Extension Store" (alias "Store") vs "Store".
- **Q-B Settings:** replace the Settings search panel with a jump to the Store (one UI), or keep both.
- **Q-C Upstream:** keep it fork-only, or open a feature-request issue upstream first.
