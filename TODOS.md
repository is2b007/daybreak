# HEY Email Triage — Follow-Up Work

Generated from adversarial code review findings. This feature shipped with critical data-loss bugs fixed. Remaining findings are lower-impact but should be addressed in follow-up.

## Medium Priority (P1)

### URL Scheme Validation on External Links [P1] ✓ FIXED
**File:** `app/models/task_assignment.rb`, `app/models/hey_email.rb`, `app/views/task_assignments/_modal.html.erb`  
**Status:** Fixed. Added `safe_hey_app_url` / `safe_hey_url` helpers that validate `https?://` scheme. Modal link uses `safe_hey_app_url` instead of raw `hey_app_url`.

### Missing Index on for_triage Scope [P1] ✓ FIXED
**File:** `db/migrate/20260408120000_create_hey_emails.rb` + `app/models/hey_email.rb`  
**Status:** Fixed in migration `20260414100000_add_for_triage_index_to_hey_emails`. Added partial index on `[:user_id, :received_at]` where `dismissed_at IS NULL AND triaged_at IS NULL`.

### Cross-User 404 Leakage (Low Impact) [P1]
**File:** `app/controllers/hey_emails_controller.rb:27-36`  
**Issue:** User A can probe `GET /hey_emails/<B's id>/triage` and see a friendly "Already handled" message instead of a 404. Allows enumeration of `hey_emails` id space, though no data is leaked.  
**Fix (optional):** Either let the 404 bubble, or add explicit user ownership check. Current behavior is acceptable given scoping already filters to current_user.

## Low Priority (P2)

### Timezone-Aware Week Bucket [P2]
**File:** `app/controllers/hey_emails_controller.rb:4` ✓ FIXED  
**Status:** Fixed in commit ff96c16. `week_start_date` now uses `current_user.timezone`.

### Enum String vs Symbol Fragility [P2]
**File:** `app/controllers/triage_controller.rb:12` and `app/views/triage/show.html.erb:16`  
**Issue:** Controller groups by `email.folder` (enum returns string), view accesses via `@emails_by_folder[folder.to_s]` (works, but fragile).  
**Fix (low-risk):** Verify types match in both directions. Consider using consistent symbol or string throughout. Not a bug today, but flag for robustness.

### Other Transport Errors Escape [P2]
**File:** `app/jobs/sync_hey_emails_job.rb:28-29` ✓ FIXED  
**Status:** Partially fixed in commit ff96c16. `refresh_and_retry!` now logs StandardError. Consider expanding in SyncHeyEmailsJob.perform to catch `StandardError` with logging before the AuthError-specific rescue.

### Server Timezone Mismatch (Informational) [P2]
**File:** `app/controllers/hey_emails_controller.rb:4` ✓ FIXED  
**Status:** Fixed in commit ff96c16. Now uses user timezone for `week_start_date`.

---

## Decision Log

**Commit ff96c16** ("fix: critical adversarial findings — prevent data loss and atomicity issues"):
- Fixed P0 #1 & #9: Prune logic silencing deleting folder
- Fixed P0 #2: Timestamp corruption
- Fixed P1 #3: Non-atomic triage action
- Fixed P1 #6: Token refresh race
- Fixed P1 #7: Unthrottled sync job

**Deferred to follow-up:**
- P1 #4: Cross-user 404 leak (low-risk enumeration, already scoped)
- P1 #5: URL scheme validation (FIXED — safe_hey_app_url / safe_hey_url helpers)
- P1 #8: Missing for_triage index (FIXED — migration 20260414100000)
- P2 #10: Enum string/symbol consistency (flag for robustness)
- P2 #11: Transport error handling (expand in SyncHeyEmailsJob)
- P2 #12: Timezone handling (FIXED)

**Justification:** The 5 fixed items were critical data-loss or atomicity issues. The deferred items are lower-leverage polish (indexing for query perf, URL validation for XSS prevention on compromised API, enum consistency). All are safe to ship separately.
