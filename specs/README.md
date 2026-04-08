# Daybreak — implementation specs

These specs are the gap between the current state of the app and the product spec. Each one is self-contained: hand it to a fresh Claude Code instance and it should have everything needed to land the work without reading any other file in this directory.

## How to use

- Each spec lives in its own `.md` file. Read the **Context** section first to understand why the work matters.
- Specs cite file paths and line numbers from the current state of the codebase as of writing. If you find them stale, trust the current code and adjust.
- "Out of scope" sections are intentional — they protect against scope creep. If the work spans two specs, do them as separate PRs.
- Acceptance criteria are checklists, not suggestions. Don't mark a spec done until every box is checked.

## Order of operations

The specs have a few cross-references. Recommended order:

1. **`01-critical-bug-fixes.md`** — Crashes the app hits on first real use. Land this first; everything else assumes a working app.
2. **`07-copy-improvements.md`** — Pure find/replace, no architecture. Easy parallel work.
3. **`03-hey-oauth.md`** — Unblocks `02` and `04` for HEY-connected users. Independent of UI specs.
4. **`02-calendar-integration.md`** — Depends on `03` for HEY events. Basecamp half is independent.
5. **`04-stamp-completion-flow.md`** — Independent. The most product-critical of the UX specs.
6. **`05-timeline-timeboxing.md`** — Depends on `02` for the timeline rendering polish.
7. **`06-dark-mode.md`** — Independent. Small but visible.
8. **`08-empty-states.md`** — Touches some files that `04`, `05`, `07` also touch. Land last to avoid merge friction.

## The specs

| # | Title | Type | Risk |
|---|---|---|---|
| 01 | [Critical bug fixes](./01-critical-bug-fixes.md) | Bug fixes | Low — small targeted patches |
| 02 | [Calendar integration (Basecamp + HEY)](./02-calendar-integration.md) | Feature | Medium — new model + jobs + scheduling |
| 03 | [HEY OAuth + token refresh](./03-hey-oauth.md) | Feature | Medium — OAuth callback flow + credentials |
| 04 | [Stamp completion flow](./04-stamp-completion-flow.md) | UX wiring | Medium — animation timing matters |
| 05 | [Timeline timeboxing](./05-timeline-timeboxing.md) | Feature | Medium — schema change + drag-drop |
| 06 | [Dark mode wiring](./06-dark-mode.md) | UX wiring | Low — mostly view + JS plumbing |
| 07 | [Copy improvements](./07-copy-improvements.md) | Polish | Low — find/replace |
| 08 | [Empty states](./08-empty-states.md) | Polish | Low — view-only |

## Voice for any new copy you write along the way

Calm, considered, slightly literary, never demanding. When in doubt: short, declarative, kind. See `07-copy-improvements.md` for the full set of patterns to avoid.

## What this list does NOT cover

- New features beyond the original product spec
- Sunrise / sunset full-screen animations (`Phase 10` of the original plan — not yet built, no spec written here)
- Mobile-specific gestures
- Notifications (push or local)
- Data export
- Multi-user / sharing
- Tests for the existing happy paths (worth doing, but not blocking the above)

If you build any of these, write a new spec first.
