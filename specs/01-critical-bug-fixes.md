# Spec 01 — Critical bug fixes

These are blocking bugs the app will hit on first real use. Fix all four. Each is small and self-contained.

## Context

Daybreak is a Rails 8 daily planner (Hotwire, Propshaft, import maps, SQLite). The audit found four bugs that crash or dead-end on common paths. None is a feature — they're all small fixes.

---

## Bug 1 — DailyLogsController reads the wrong param name

**File:** `app/controllers/daily_logs_controller.rb`

The route is `get "days/:date/log"` (and similar `post`/`patch`), so Rails sets `params[:date]`. The controller reads `params[:day_date]`, which is always nil — every action calls `Date.parse(nil)` and raises `TypeError`.

**Fix:** Replace all three `params[:day_date]` with `params[:date]`.

```diff
- @date = Date.parse(params[:day_date])
+ @date = Date.parse(params[:date])
```

Three occurrences: `show` (line 3), `create` (line 9), `update` (line 19).

**Verify:** Open `/days/2026-04-08/log`, type something, hit "Add entry". Should redirect back to the day view's log tab with the entry rendered.

---

## Bug 2 — TaskAssignmentsController#move has no template

**File:** `app/controllers/task_assignments_controller.rb` (line 47–50)

```ruby
respond_to do |format|
  format.turbo_stream
  format.html { redirect_back fallback_location: root_path }
end
```

There is no `app/views/task_assignments/move.turbo_stream.erb`. Every drag-drop in the kanban triggers `ActionController::MissingExactTemplate` and the card snaps back.

**Fix:** Render a turbo stream inline that replaces the source and target day columns. The Stimulus controller (`app/javascript/controllers/sortable_controller.js`) already moves the DOM optimistically, but the server response should reconcile positions in case other tasks shifted.

Render this inline (mirrors what `cycle_size` and `complete` do):

```ruby
respond_to do |format|
  format.turbo_stream do
    render turbo_stream: [
      turbo_stream.replace("day_#{target_date}",
        partial: "weeks/day_column",
        locals: {
          date: target_date,
          tasks: current_user.task_assignments.for_week(target_date.beginning_of_week(:monday)).where(day_plan: target_plan).ordered,
          events: []
        })
    ]
  end
  format.html { redirect_back fallback_location: root_path }
end
```

If the source date differs from the target date, also replace the source column. Track the source via a `source_date` param sent from the JS controller — update `sortable_controller.js#drop` to include `source_date=${this.dragSourceDate}` in the body. (This also makes use of `dragSourceDate`, which is currently dead.)

The `events: []` placeholder is fine for now; calendar integration is a separate spec.

**Verify:** Drag a card from Tuesday to Friday. The card should land in Friday in the right position, persist on reload, and the source column should re-render without the moved card.

---

## Bug 3 — Onboarding "Connect HEY" dead-ends

**File:** `app/controllers/onboarding_controller.rb` (line 21)

When the user clicks "Connect HEY" on step 3, the controller calls `redirect_to auth_hey_path`. That route hits `HeyConnectionsController#new`, which is currently a stub that bounces to `/settings` with "HEY connection coming soon."

The user is now stranded mid-onboarding with `onboarded: false`, and the next page load will redirect them right back to step 1.

**Fix (interim, until Spec 03 implements HEY OAuth):** Until HEY OAuth works, have step 3's "Connect HEY" button mark `connect_hey_intent` somewhere (or just not exist) and proceed to step 4. The cleanest interim fix is hiding the "Connect HEY" button entirely and leaving only "Skip for now" — don't pretend a feature exists. When Spec 03 lands, restore the button.

In `app/views/onboarding/_step_3_hey.html.erb`, replace lines 25–28:

```erb
<div class="flex flex-col gap-3">
  <%= f.submit "Skip for now", name: "connect_hey", value: "false", class: "btn btn--primary btn--large" %>
  <p class="text-xs text-muted text-center">HEY support is on the way. You'll be able to connect from Settings.</p>
</div>
```

**When Spec 03 lands**, restore the original two-button layout.

**Verify:** Run through onboarding with a fresh user. Step 3 should let you continue without dead-ending.

---

## Bug 4 — `dragSourceDate` is dead, and source column doesn't re-render

**File:** `app/javascript/controllers/sortable_controller.js`

Line 15 stores `this.dragSourceDate` but nothing reads it. As part of Bug 2's fix, send it to the server:

```diff
  body: `target_date=${targetDate}&position=${position}`
+ body: `target_date=${targetDate}&position=${position}&source_date=${this.dragSourceDate}`
```

And in `TaskAssignmentsController#move`, if `params[:source_date].present?` and it differs from `target_date`, also include a `turbo_stream.replace("day_#{source_date}", ...)` in the response.

**Verify:** Same as Bug 2 — the source column should not still show the dragged card after a successful drop.

---

## Acceptance criteria

- [ ] `bin/rails test` passes (write at least one regression test for daily_log POST and one for task_assignments#move)
- [ ] Drag-drop persists across page reloads
- [ ] Daily log entries save without error
- [ ] Onboarding step 3 doesn't strand the user
- [ ] No `dragSourceDate` dead reference

## Out of scope

- Full HEY OAuth (Spec 03)
- Calendar event population in `move` response (Spec 02)
- Stamp animation chaining (Spec 04)
