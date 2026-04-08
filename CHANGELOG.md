# Changelog

All notable changes to Daybreak will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-04-08

### Added
- **HEY Email triage** — Pull inbox, reply later, and set aside folders from HEY into Daybreak. Turn any email into a "sometime this week" task or dismiss it locally. No write-back to HEY. Accessed via `/triage` or a footnote in the morning ritual.
  - New triage surface at `/triage` with three folder sections (Imbox, Reply Later, Set Aside)
  - Click "This week" to move an email to the week view's Sometime column
  - Click "Dismiss" to hide it locally (sync-safe: dismissed rows persist across syncs)
  - Morning ritual step 2 shows a footnote with count when emails are waiting
  - Settings links to triage when HEY is connected
  - Onboarding mentions email triage as a HEY feature
  - `SyncHeyEmailsJob` runs daily at 6am + on-demand when triage is opened
  - Full test coverage for controller, job, and model

### Fixed
- **Critical: Prune logic silent data loss** — Fixed a bug where any empty API response (transient failure or legitimate empty folder) would silently delete the user's entire triage queue. `prune_stale` now always applies the exclusion filter, even when current_ids is empty.
- **Critical: Timestamp corruption on bad data** — Fixed `parse_time` defaulting to `Time.current` on missing/malformed timestamps, which caused rows to re-sort to top on every sync. Now preserves the row's existing `received_at` or skips assignment if new data is bad.
- **Non-atomic triage action** — Wrapped `triage` action in a database transaction to ensure both task creation and email state update succeed or both fail. Added error rescue for `RecordInvalid` and `RecordNotFound`.
- **Token refresh race under concurrent syncs** — Added `with_lock` around token refresh to prevent concurrent jobs from clobbering each other's access tokens. Re-checks token freshness after lock acquisition.
- **Unthrottled sync job flooding queue** — Added 90-second debounce to `TriageController#show`. Only enqueues `SyncHeyEmailsJob` if the most recent hey_email was updated > 90 seconds ago, preventing queue spam and HEY rate-limit issues.
- **Timezone-aware week bucket** — Fixed `week_start_date` calculation in triage action to use the user's configured timezone instead of server timezone.

### Security
- Transport errors in HEY client now log before re-raising, improving visibility into network failures.
- See `TODOS.md` for remaining deferred security items (URL scheme validation, cross-user enumeration hardening).

---

[0.1.0]: https://github.com/is2b007/daybreak/releases/tag/v0.1.0
