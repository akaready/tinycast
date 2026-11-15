---
status: in-progress
plan_date: 2026-11-14
---

# Space after an exact alias engages the entry (fork-only)

## Outcome — in progress, 2026-11-14

**Landed:** an opt-in setting, "Space after an alias opens it" (General ▸ Search, `aliasSpaceEngages`,
default off, carried by backups and `settings.json` as `search.spaceAfterAlias`). With it on, typing an
alias that is the entire query and pressing Space engages the selected entry: an entry with inline
argument fields (quicklink, custom command, extension command) focuses its first field without running;
an entry that opens a screen (Contacts and the other search commands, extension view commands) opens as
↵ would; everything else, apps included, types the space normally. The decision is the pure
`AliasEngage.action` in `Launcher/Model/`, with `alias-engage-test`. Strings translated into all eight
languages; `docs/features/launcher.md`, `palette.md` and `testing.md` updated.
**Verified:** `run-tests.sh` (115 harnesses, including `alias-engage-test` with 19 cases), `lint.sh`, the purity
grep, `check-localizations.js` and the unsigned Debug build all passed.
**Not verified:** never run on screen. Whether SwiftUI's `onKeyPress(.space)` on the palette root sees the
Space before the focused search field inserts it is untested; if it does not, the fix is an `onBareSpace`
hook in `PalettePanel.sendEvent` like `onBareBackspace`. Also untried: the focus hand-off to the first
argument field, and Contacts opening with an empty query.
**Deviated:** "hidden or disabled entry" is enforced structurally, not by a flag: the decision reads the
selected row, and the ranker never lists a hidden or disabled entry, so `AliasEngage` takes no visibility
input. `CommandID.opensSearchScreen` is a hand-kept list of the commands that take the palette over.
**Left undone:** the on-screen pass above; the status flips to `shipped` once it is seen working.

## Context

Raycast types `c` then Space to enter a command with an empty query. Tinycast selects the entry on an
exact alias (ranking rule 1) but waits for ↵. This adds the Space shortcut as an opt-in.
