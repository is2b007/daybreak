# Spec 08 — Empty states

Add empty-state messaging in the places where the app currently shows nothing. Empty states are the difference between "is this broken?" and "ah, I see what to do next."

## Context

When a user opens Daybreak for the first time, or on a quiet week, several screens render to a blank space. The day view has good empty copy already (see `_daily_log.html.erb`, `days/show.html.erb`). The week view does not — a brand new user lands on a kanban with seven empty columns and zero guidance.

This spec catches every blank surface and gives it a kind, instructive empty state.

## Files that need work

| File | Empty state to add |
|---|---|
| `app/views/weeks/show.html.erb` | First-time user with no tasks anywhere |
| `app/views/weeks/_day_column.html.erb` | A day with no tasks (currently silent) |
| `app/views/weeks/_sometime_row.html.erb` | The whole row is hidden when empty — show it inviting in the empty case |
| `app/views/weeks/_weekly_goals.html.erb` | Mid-week with no goals (only Monday gets a "Set goals" link) |
| `app/views/days/_timeline.html.erb` | Timeline with no events and no timeboxes (Spec 05 territory but minimal copy here) |
| `app/views/rituals/_morning_step_3.html.erb` | Already has empty copy — sharpen it |

## Implementation

### 1. Week view — first-run state

Right now `weeks/show.html.erb` always renders the kanban + sometime row + goals. For a brand new user:
- `@task_assignments` is empty
- `@weekly_goals` is empty  
- `@calendar_events` is empty

That's a lot of nothing. Add a one-time first-run hint above the kanban:

```erb
<%# weeks/show.html.erb — after the week-nav, before the kanban %>

<% first_run = @task_assignments.empty? && @weekly_goals.empty? && current_user.day_plans.where.not(morning_ritual_done: false).none? %>

<% if first_run %>
  <div class="first-run">
    <h2 class="first-run__heading">Welcome, <%= current_user.greeting_name %>.</h2>
    <p class="first-run__body">
      This is your week. The columns below are days. Tasks from Basecamp
      will start appearing as you sync. When you're ready,
      <%= link_to "shape today", ritual_morning_path %> with the morning ritual.
    </p>
  </div>
<% end %>
```

Style it light — a single paragraph in a centered card above the kanban. When `first_run` is false, the hint disappears entirely.

### 2. Day column — silent days

`_day_column.html.erb` lines 22–26 just render the task list. Add a tiny placeholder when the day has no tasks AND no events:

```erb
<div class="kanban__tasks" data-sortable-target="taskList" data-date="<%= date %>">
  <% if tasks.empty? && events.empty? %>
    <div class="kanban__empty">
      <% if date == Date.current %>
        <%= link_to "Plan today", ritual_morning_path, class: "kanban__empty-link" %>
      <% elsif date < Date.current %>
        <span class="kanban__empty-text">—</span>
      <% else %>
        <span class="kanban__empty-text">Drop something here</span>
      <% end %>
    </div>
  <% else %>
    <% tasks.sort_by(&:position).each do |task| %>
      <%= render "shared/task_card", task: task, compact: true %>
    <% end %>
  <% end %>
</div>
```

The three states:
- **Today, empty:** prompts the user to plan
- **Past day, empty:** quiet em-dash (no judgment for an empty Tuesday)
- **Future day, empty:** invites a drop

CSS for `components/kanban.css`:

```css
.kanban__empty {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 80px;
  font-size: 12px;
  color: var(--color-text-muted);
  border: 1px dashed var(--color-border-subtle);
  border-radius: var(--radius-sm);
  margin: 8px 0;
}
.kanban__empty-link {
  color: var(--color-accent);
  text-decoration: none;
}
.kanban__empty-text {
  opacity: 0.5;
}
```

### 3. Sometime row — show it always

Currently `weeks/show.html.erb` line 25:
```erb
<% if @sometime_tasks.any? %>
  <%= render "sometime_row", tasks: @sometime_tasks %>
<% end %>
```

Change to always render, and let the partial handle the empty case:

```erb
<%= render "sometime_row", tasks: @sometime_tasks %>
```

In `_sometime_row.html.erb`:

```erb
<%# locals: (tasks:) %>
<div class="sometime-row">
  <div class="sometime-row__label">Sometime this week</div>
  <div class="sometime-row__tasks"
       data-sortable-target="sometimeList"
       data-action="dragover->sortable#dragover drop->sortable#drop dragenter->sortable#dragenter dragleave->sortable#dragleave">
    <% if tasks.any? %>
      <% tasks.each do |task| %>
        <%= render "shared/task_card", task: task, compact: true %>
      <% end %>
    <% else %>
      <p class="sometime-row__empty">Things you want to do this week, but not on a particular day. Drag stuff here.</p>
    <% end %>
  </div>
</div>
```

CSS:

```css
.sometime-row__empty {
  font-size: 13px;
  color: var(--color-text-muted);
  padding: 12px 16px;
  font-style: italic;
}
```

### 4. Weekly goals — empty mid-week

Right now `_weekly_goals.html.erb` only shows a "Set goals" link on Mondays. Mid-week with no goals = silent. Show the empty state always but soften the wording when it's not Monday:

```erb
<%# locals: (goals:, week_start:) %>
<div class="weekly-goals">
  <div class="weekly-goals__label">
    This week
  </div>
  <% if goals.any? %>
    <div class="weekly-goals__list">
      <% goals.each do |goal| %>
        <div class="weekly-goal <%= 'weekly-goal--completed' if goal.completed? %>">
          <span class="weekly-goal__title"><%= goal.title %></span>
          <span class="weekly-goal__progress"><%= goal.progress_text %></span>
        </div>
      <% end %>
    </div>
  <% else %>
    <div class="weekly-goals__empty">
      <% if Date.current.beginning_of_week(:monday) == week_start %>
        <%= link_to "What is this week for?", weekly_checkin_path, class: "weekly-goals__empty-link" %>
      <% else %>
        <span class="weekly-goals__empty-text">No goals this week.</span>
      <% end %>
    </div>
  <% end %>
</div>
```

### 5. Day timeline — empty timeline

`days/_timeline.html.erb` right now renders the hour cells regardless. That's the right behavior — even empty hours are useful structure. But add a small inline hint over the empty timeline area for first-time users:

```erb
<%# at the top of the timeline, after the opening div %>
<% if events.empty? && tasks.none?(&:timeboxed?) %>
  <div class="timeline__hint">
    Drag a task onto the timeline to give it a time.
  </div>
<% end %>
```

CSS:

```css
.timeline__hint {
  position: absolute;
  top: 50%;
  left: 56px;
  right: 8px;
  text-align: center;
  font-size: 13px;
  color: var(--color-text-muted);
  font-style: italic;
  pointer-events: none;
}
```

(`timeboxed?` requires Spec 05's model addition. Until that lands, simplify to `if events.empty?`.)

### 6. Morning ritual step 3 — sharpen empty

`_morning_step_3.html.erb` line 28 already has:
```erb
<p class="text-muted">No tasks available. Add something personal in the next step.</p>
```

Spec 07 already changes this to "Nothing waiting. You can add something personal next." — leave it to that spec.

### 7. Sessions / login — already handled

`sessions/new.html.erb` already shows a configured-vs-unconfigured state. No empty state needed.

## Acceptance criteria

- [ ] Brand-new user lands on the week view and sees the welcome paragraph
- [ ] Each empty day column shows the right placeholder for past/today/future
- [ ] Sometime row is always visible with helpful empty copy
- [ ] Weekly goals show "What is this week for?" on Monday and "No goals this week." otherwise
- [ ] Day timeline shows the inline hint when empty
- [ ] No screen in the app renders to literal blank space anymore

## Out of scope

- Skeleton loading states (the app is fast enough that they'd flicker)
- Illustrations or imagery in empty states (the spec calls for restraint)
- Onboarding tooltips that follow the cursor (not the calm aesthetic)
