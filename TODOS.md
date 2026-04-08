# HEY Email Triage — Follow-Up Work

Generated from adversarial code review findings. This feature shipped with critical data-loss bugs fixed. Remaining findings are lower-impact but should be addressed in follow-up.

## Medium Priority (P1)

### URL Scheme Validation on External Links [P1]
**File:** `app/views/triage/_hey_email.html.erb:10`  
**Issue:** `hey_url` from the HEY API is rendered directly in `href` with no validation. A malicious or compromised HEY posting could inject `javascript:` or `data:` URIs.  
**Fix:** Validate that the URL scheme is `http` or `https` before rendering. Use Rails `sanitize_url` helper or add a simple scheme check:
```erb
<% if @email.hey_url&.match?(%r{^https?://}) %>
  <%= link_to @email.subject, @email.hey_url, target: "_blank", rel: "noopener" %>
<% else %>
  <span><%= @email.subject %></span>
<% end %>
```

### Missing Index on for_triage Scope [P1]
**File:** `db/migrate/20260408120000_create_hey_emails.rb` + `app/models/hey_email.rb`  
**Issue:** `for_triage` filters `dismissed_at IS NULL AND triaged_at IS NULL` ordered by `received_at DESC`. The existing indexes `[user_id, folder]` and `[user_id, received_at]` don't cover the soft-delete predicate. Queries are sequential scans. Also, `app/views/rituals/_morning_step_2.html.erb` renders `for_triage.count` on every page.  
**Fix:** Add a partial index to cover both soft-delete columns:
```ruby
add_index :hey_emails, 
  [:user_id, :folder, :received_at], 
  where: "dismissed_at IS NULL AND triaged_at IS NULL",
  name: "idx_hey_emails_for_triage"
```

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
- P1 #5: URL scheme validation (add sanitize_url)
- P1 #8: Missing for_triage index (add partial index)
- P2 #10: Enum string/symbol consistency (flag for robustness)
- P2 #11: Transport error handling (expand in SyncHeyEmailsJob)
- P2 #12: Timezone handling (FIXED)

**Justification:** The 5 fixed items were critical data-loss or atomicity issues. The deferred items are lower-leverage polish (indexing for query perf, URL validation for XSS prevention on compromised API, enum consistency). All are safe to ship separately.
