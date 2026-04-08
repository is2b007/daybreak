# Spec 07 — Copy improvements

Warm up the copy across the app. Daybreak should sound like a thoughtful friend, not a SaaS dashboard. Most strings are already good — this spec catches the ones that slipped into product-marketing or Rails-default tone.

## Context

The voice the product should hold (from the spec): calm, considered, slightly literary, never demanding. Avoid jargon ("unlock", "leverage", "personal layer"), avoid pressure ("Authentication failed!"), avoid cuteness ("Woohoo! 🎉"). When in doubt: short, declarative, kind.

This is a find/replace exercise. Make every change in this list. Read the surrounding context first if any of them feel ambiguous in their new form.

## Changes

### `app/controllers/sessions_controller.rb`

Line 35:
```diff
- redirect_to login_path, alert: "Authentication failed. Please try again."
+ redirect_to login_path, alert: "That didn't go through. Want to try again?"
```

Line 40:
```diff
- redirect_to login_path, notice: "Signed out."
+ redirect_to login_path, notice: "Signed out. See you tomorrow."
```

### `app/controllers/concerns/authentication.rb`

Line 20:
```diff
- redirect_to login_path, alert: "Please sign in to continue."
+ redirect_to login_path, alert: "Sign in to pick up where you left off."
```

### `app/controllers/onboarding_controller.rb`

Line 33:
```diff
- redirect_to root_path, notice: "Welcome to Daybreak, #{current_user.greeting_name}."
+ redirect_to root_path, notice: "Glad you're here, #{current_user.greeting_name}."
```

### `app/controllers/rituals_controller.rb`

Line 40:
```diff
- redirect_to day_path(Date.current), notice: "Your day is set. Let's go."
+ redirect_to day_path(Date.current), notice: "Your day is set."
```

(The "Let's go" reads as a coach prompt — the calmer version is enough.)

### `app/controllers/hey_connections_controller.rb`

Line 16:
```diff
- redirect_to settings_path, notice: "HEY connected."
+ redirect_to settings_path, notice: "HEY is connected."
```

Line 20:
```diff
- redirect_to settings_path, notice: "HEY disconnected."
+ redirect_to settings_path, notice: "HEY is disconnected."
```

### `app/controllers/settings_controller.rb`

Line 7:
```diff
- redirect_to settings_path, notice: "Settings saved."
+ redirect_to settings_path, notice: "Saved."
```

### `app/controllers/weekly_checkins_controller.rb`

Line 31:
```diff
- redirect_to ritual_morning_path, notice: "Goals set. Let's plan Monday."
+ redirect_to ritual_morning_path, notice: "Goals set. Now let's plan Monday."
```

(Removes the "Let's…" tic that reads as cheerleading. Slight rephrase keeps the through-line.)

### `app/views/sessions/new.html.erb`

Line 5 (the tagline) is good — keep it. The configured-state error is a system message, not user copy — leave it. The connect button text is fine.

### `app/views/onboarding/_step_1_name.html.erb`

Lines 1–2:
```diff
- <h2 class="onboarding__title">What should we call you?</h2>
- <p class="onboarding__subtitle">Just your first name. This is how Daybreak will greet you each morning.</p>
+ <h2 class="onboarding__title">What should we call you?</h2>
+ <p class="onboarding__subtitle">Just a first name. It's how Daybreak says hello in the morning.</p>
```

### `app/views/onboarding/_step_2_stamp.html.erb`

Line 2:
```diff
- <p class="onboarding__subtitle">When you complete a task, your stamp marks it done. Like a wax seal or a library date stamp.</p>
+ <p class="onboarding__subtitle">When you finish something, your stamp marks it done. Pick the one that feels right.</p>
```

### `app/views/onboarding/_step_3_hey.html.erb`

Line 1:
```diff
- <h2 class="onboarding__title">Do you use HEY?</h2>
+ <h2 class="onboarding__title">Use HEY?</h2>
```

Line 2:
```diff
- <p class="onboarding__subtitle">Connecting HEY unlocks your personal layer — calendar, to-dos, journal, and time tracking.</p>
+ <p class="onboarding__subtitle">If you do, Daybreak can pull in your calendar, to-dos, journal, and time tracking. If you don't, no problem.</p>
```

The four feature lines (lines 7, 11, 15, 19) — change:
```diff
- <span>HEY Calendar events appear alongside Basecamp schedules</span>
+ <span>Calendar events sit next to your Basecamp schedule</span>
```
```diff
- <span>Personal to-dos from HEY appear in your task list</span>
+ <span>Personal to-dos slot into your day</span>
```
```diff
- <span>Track time with HEY's built-in time tracker</span>
+ <span>Time tracking, when you want it</span>
```
```diff
- <span>Daily log and reflections sync to your HEY Journal</span>
+ <span>Daily logs and reflections write back to your Journal</span>
```

Line 32:
```diff
- Without HEY, everything still works — timer, journal, and personal tasks are stored locally in Daybreak. You can connect HEY anytime from Settings.
+ Without HEY, everything still works. Your timer, journal, and personal tasks live in Daybreak. You can connect later from Settings.
```

### `app/views/onboarding/_step_4_timezone.html.erb`

Line 2:
```diff
- <p class="onboarding__subtitle" data-controller="timezone-detector" data-timezone-detector-target="message">Detecting your timezone...</p>
+ <p class="onboarding__subtitle" data-controller="timezone-detector" data-timezone-detector-target="message">Figuring out where you are…</p>
```

(Use a real ellipsis `…`, not three dots. Same rule applies anywhere else with `...`.)

Line 15 button text:
```diff
- <%= f.submit "Start using Daybreak", class: "btn btn--warm" %>
+ <%= f.submit "Begin", class: "btn btn--warm" %>
```

### `app/views/days/show.html.erb`

Lines 11–14 (subtitle):
```diff
- <p class="day-view__subtitle">
-   <%= @pending_tasks.count %> tasks &middot;
-   <% total = @tasks.sum(:planned_duration_minutes).to_i %>
-   <% if total > 0 %><%= total / 60 %>h <%= total % 60 %>m planned<% else %>no time planned<% end %>
- </p>
+ <p class="day-view__subtitle">
+   <%= pluralize(@pending_tasks.count, "task") %> &middot;
+   <% total = @tasks.sum(:planned_duration_minutes).to_i %>
+   <% if total > 0 %><%= total / 60 %>h <%= total % 60 %>m planned<% else %>nothing planned yet<% end %>
+ </p>
```

Line 50:
```diff
- No tasks planned for this day. <%= link_to "Run your morning ritual", ritual_morning_path %> to shape your day.
+ Nothing on the books for this day. <%= link_to "Plan your morning", ritual_morning_path %>.
```

Line 48:
```diff
- All done for today. Nice work.
+ Everything's done. That's a good day.
```

### `app/views/days/_daily_log.html.erb`

Line 14:
```diff
- <p class="text-muted text-sm">No entries yet. Start typing below.</p>
+ <p class="text-muted text-sm">Nothing here yet. Add something below.</p>
```

Line 21 placeholder:
```diff
- <%= f.text_area :content, class: "form-input", placeholder: "Type here...", rows: 3, ...
+ <%= f.text_area :content, class: "form-input", placeholder: "What's on your mind?", rows: 3, ...
```

### `app/views/days/_timer_bar.html.erb`

Line 7:
```diff
- Timer running
+ Tracking time
```

### `app/views/rituals/_morning_step_1.html.erb`

Line 3:
```diff
- <p class="ritual__prompt">A few things from yesterday.</p>
+ <p class="ritual__prompt">A few things from yesterday.</p>
```

(Already good — leave it.)

Line 23 button labels:
```diff
- <input ...> Done
- <input ...> Today
- <input ...> Let it go
+ <input ...> Done
+ <input ...> Today
+ <input ...> Let go
```

(Tighter "Let go" reads better as a button. Or keep "Let it go" — hold the line. Decision: **keep "Let it go"** — it's the warmer version. So **revert this change**.)

Line 34:
```diff
- <p class="text-muted">Nothing left over. Clean slate.</p>
+ <p class="text-muted">Nothing left over. Clean slate.</p>
```

(Already perfect.)

### `app/views/rituals/_morning_step_2.html.erb`

Line 4:
```diff
- <p class="ritual__prompt">Here's what's already scheduled.</p>
+ <p class="ritual__prompt">Here's what's already on your calendar.</p>
```

Line 16:
```diff
- <p class="text-muted mb-6">No calendar events today. Wide open.</p>
+ <p class="text-muted mb-6">Nothing on your calendar today. Wide open.</p>
```

Line 19:
```diff
- <p class="text-sm font-semibold mb-3">Basecamp assignments</p>
+ <p class="text-sm font-semibold mb-3">Waiting on you in Basecamp</p>
```

### `app/views/rituals/_morning_step_3.html.erb`

Line 4:
```diff
- <p class="text-sm text-muted mb-6">Tap tasks to add them to today. Set rough durations — how much time you <em>want</em> to give each one.</p>
+ <p class="text-sm text-muted mb-6">Pick what you'll work on. Set rough durations — how much time you <em>want</em> to give each one.</p>
```

Line 28:
```diff
- <p class="text-muted">No tasks available. Add something personal in the next step.</p>
+ <p class="text-muted">Nothing waiting. You can add something personal next.</p>
```

### `app/views/rituals/_morning_step_4.html.erb`

Lines 2–3 (already good — leave them).

Line 8 placeholder:
```diff
- placeholder: "Go for a walk, sketch that logo idea, call mom..."
+ placeholder: "Go for a walk, sketch that logo idea, call mom…"
```

(Real ellipsis.)

### `app/views/rituals/_morning_step_5.html.erb`

Line 3 (good — keep).

Line 8:
```diff
- That's a full day. You've planned <%= total_planned / 60 %>h <%= total_planned % 60 %>m against <%= current_user.work_hours_target %>h. Sure you want all of it?
+ That's a full day. <%= total_planned / 60 %>h <%= total_planned % 60 %>m against your usual <%= current_user.work_hours_target %>h. Sure?
```

Line 37 button:
```diff
- <%= f.submit "Start your day", class: "btn btn--warm" %>
+ <%= f.submit "Begin", class: "btn btn--warm" %>
```

### `app/views/rituals/_evening_step_1.html.erb`

Line 3 (good — keep).

Line 20:
```diff
- <p class="text-muted">Nothing completed today. That's okay — some days are like that.</p>
+ <p class="text-muted">Nothing finished today. Some days are like that.</p>
```

### `app/views/rituals/_evening_step_2.html.erb`

Line 34:
```diff
- <p class="text-muted mb-6">Everything's done. Well played.</p>
+ <p class="text-muted mb-6">Everything's done. That's a rare day.</p>
```

### `app/views/rituals/_evening_step_3.html.erb`

Line 3:
```diff
- <p class="text-sm text-muted mb-6">One line. That's your record.</p>
+ <p class="text-sm text-muted mb-6">One line. That's all.</p>
```

Line 9 placeholder:
```diff
- placeholder: "Shipped the landing page. Good day."
+ placeholder: "Shipped the landing page. Good day."
```

(Already good — keep.)

Line 11 button:
```diff
- <%= f.submit "Done", class: "btn btn--warm" %>
+ <%= f.submit "Good night", class: "btn btn--warm" %>
```

### `app/views/settings/show.html.erb`

Line 28:
```diff
- <%= f.label :work_hours_target, "Work hours target", class: "form-label" %>
+ <%= f.label :work_hours_target, "Your work day", class: "form-label" %>
```

Line 30:
```diff
- <p class="text-xs text-muted mt-1">How many hours of planned work before Daybreak warns you.</p>
+ <p class="text-xs text-muted mt-1">Daybreak will gently push back when you plan more than this.</p>
```

Line 33:
```diff
- <%= f.label :sundown_time, "Sundown time", class: "form-label" %>
+ <%= f.label :sundown_time, "When the day winds down", class: "form-label" %>
```

Line 35:
```diff
- <p class="text-xs text-muted mt-1">When the evening ritual triggers.</p>
+ <p class="text-xs text-muted mt-1">When Daybreak suggests the evening ritual.</p>
```

Line 14 (section title):
```diff
- <div class="settings__section-title">Stamp</div>
+ <div class="settings__section-title">Your stamp</div>
```

Line 26:
```diff
- <div class="settings__section-title">Schedule</div>
+ <div class="settings__section-title">Your day</div>
```

Line 86 button:
```diff
- <%= f.submit "Save settings", class: "btn btn--primary btn--large" %>
+ <%= f.submit "Save", class: "btn btn--primary btn--large" %>
```

Line 77:
```diff
- <%= button_to "Disconnect", disconnect_hey_path, ...
+ <%= button_to "Disconnect HEY", disconnect_hey_path, ...
```

### `app/views/weekly_checkins/show.html.erb`

Line 3:
```diff
- <p class="checkin__subtitle">Monday, <%= @week_start.strftime("%B %-d") %>. Look back, then look forward.</p>
+ <p class="checkin__subtitle">Monday, <%= @week_start.strftime("%B %-d") %>. A look back, a look forward.</p>
```

Line 8:
```diff
- <h3 class="text-lg font-semibold mb-4">Last week's goals</h3>
+ <h3 class="text-lg font-semibold mb-4">How last week went</h3>
```

Line 23:
```diff
- <h3 class="text-lg font-semibold mb-4">This week's goals</h3>
+ <h3 class="text-lg font-semibold mb-4">What this week is for</h3>
```

Line 24:
```diff
- <p class="text-sm text-muted mb-4">Set 2&ndash;4 goals for the week. What would make this week a success?</p>
+ <p class="text-sm text-muted mb-4">Two to four. What would make this week feel like a good one?</p>
```

Line 35 button:
```diff
- <%= f.submit "Set goals & start the week", class: "btn btn--warm" %>
+ <%= f.submit "Set the week", class: "btn btn--warm" %>
```

### `app/views/weeks/_weekly_goals.html.erb`

Line 3:
```diff
- This week's goals
+ This week
```

Line 6:
```diff
- &middot; <%= link_to "Set goals", weekly_checkin_path, class: "text-sm" %>
+ &middot; <%= link_to "Set the week", weekly_checkin_path, class: "text-sm" %>
```

### Universal sweep

Search the views for these patterns and replace:

| Find | Replace |
|---|---|
| `...` (in user-visible strings) | `…` (real ellipsis) |
| `&` in button text | `and` |
| `Tasks` (heading-like) | `Today` or `What you're doing` depending on context |
| `Click to ...` | `Tap to ...` (mobile-first) |
| `Please ` (as polite filler) | (drop it — "sign in" is enough) |

Run a final read of every view file you touched and ask: would I send this to a friend in a text message? If not, soften it.

## Acceptance criteria

- [ ] Every diff above applied
- [ ] No `...` (three dots) in any user-facing string
- [ ] No "Please" as politeness filler
- [ ] No "Authentication failed" or other system-error tone
- [ ] No "unlock", "leverage", "powerful", "seamless", "effortless"
- [ ] Read through onboarding, the morning ritual, the evening ritual, and settings end-to-end as a real user would. Each screen should sound like one voice — calm, direct, slightly warm.

## Out of scope

- Localization (English only for now)
- Tooltip copy — that's a microcopy pass for later
- Marketing site copy
