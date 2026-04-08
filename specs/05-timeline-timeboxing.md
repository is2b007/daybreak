# Spec 05 — Timeline timeboxing

Let users drag a task from the day view's task list onto the right-side timeline to plant it at a specific hour. If HEY is connected, the timebox becomes a HEY Calendar todo. Otherwise it's a local timeline block.

## Context

The day view (`/days/2026-04-08`) is a two-column layout: tasks on the left, a 7am–9pm timeline on the right. The right side is where the user shapes _when_ they'll do something — not just _what_.

Right now the timeline only shows calendar events (and won't show those until Spec 02 lands). Drag-to-timebox is a stub:

```js
// app/javascript/controllers/timeline_controller.js#drop
console.log(`Timebox task ${assignmentId} at ${hourValue}:00 on ${this.dateValue}`)
```

## Files that need work

| File | Change |
|---|---|
| `db/migrate/...` | New migration adding `planned_start_at` and `planned_end_at` (or `planned_minutes_after_midnight`) to `task_assignments` |
| `app/models/task_assignment.rb` | New methods: `timeboxed?`, `start_hour`, `end_hour`, helper for positioning |
| `app/controllers/task_assignments_controller.rb` | New `timebox` action |
| `config/routes.rb` | New `patch :timebox` member route |
| `app/javascript/controllers/timeline_controller.js` | Real `drop` implementation that POSTs and updates the DOM |
| `app/views/days/_timeline.html.erb` | Render timeboxed tasks alongside calendar events |
| `app/services/hey_client.rb` | Use the existing `create_todo(title:, starts_at:, ends_at:)` method when HEY is connected |
| `app/jobs/sync_timebox_to_hey_job.rb` | New background job for the HEY write |

## Schema decision

Keep it simple: store `planned_start_at` (datetime) on `task_assignment`. The end time is implied by `planned_duration_minutes`, which already exists. If the user hasn't set a duration, default to 60 minutes when timeboxing.

```ruby
# db/migrate/<timestamp>_add_planned_start_at_to_task_assignments.rb
class AddPlannedStartAtToTaskAssignments < ActiveRecord::Migration[8.1]
  def change
    add_column :task_assignments, :planned_start_at, :datetime
    add_column :task_assignments, :hey_calendar_event_id, :string  # for HEY round-trip
    add_index :task_assignments, [:user_id, :planned_start_at]
  end
end
```

## Implementation

### 1. TaskAssignment additions

```ruby
# app/models/task_assignment.rb
scope :timeboxed_for, ->(date) {
  where(planned_start_at: date.beginning_of_day..date.end_of_day)
}

def timeboxed?
  planned_start_at.present?
end

def start_hour_in(timezone)
  return nil unless timeboxed?
  planned_start_at.in_time_zone(timezone).hour +
    (planned_start_at.in_time_zone(timezone).min / 60.0)
end

def duration_hours
  ((planned_duration_minutes || 60) / 60.0)
end
```

### 2. Route + controller action

```ruby
# config/routes.rb (inside the existing task_assignments resources)
member do
  patch :move
  patch :cycle_size
  patch :complete
  patch :defer
  patch :timebox  # ← new
end
```

```ruby
# app/controllers/task_assignments_controller.rb

before_action :set_task, only: [:update, :destroy, :move, :cycle_size, :complete, :defer, :timebox]

def timebox
  date = Date.parse(params[:date])
  hour = params[:hour].to_i
  minute = params[:minute].to_i || 0

  starts_at = current_user.timezone.then { |tz|
    ActiveSupport::TimeZone[tz].local(date.year, date.month, date.day, hour, minute)
  }

  @task.update!(
    planned_start_at: starts_at,
    planned_duration_minutes: @task.planned_duration_minutes || 60
  )

  SyncTimeboxToHeyJob.perform_later(@task.id) if current_user.hey_connected?

  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: turbo_stream.replace(
        "timeline_#{date}",
        partial: "days/timeline",
        locals: {
          date: date,
          events: current_user.calendar_events.for_date(date).map(&:to_view_hash),
          tasks: current_user.task_assignments.where(day_plan: current_user.day_plans.find_by(date: date)).ordered
        }
      )
    end
    format.html { redirect_to day_path(date) }
  end
end
```

If Spec 02 hasn't landed yet, `events:` can be `[]`.

### 3. Stimulus — real drop

```js
// app/javascript/controllers/timeline_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { date: String }
  static targets = ["hour"]

  dragover(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  dragenter(event) {
    const hour = event.target.closest(".timeline__hour")
    if (hour) hour.classList.add("timeline__hour--dragover")
  }

  dragleave(event) {
    const hour = event.target.closest(".timeline__hour")
    if (hour && !hour.contains(event.relatedTarget)) {
      hour.classList.remove("timeline__hour--dragover")
    }
  }

  drop(event) {
    event.preventDefault()
    const hour = event.target.closest(".timeline__hour")
    if (!hour) return
    hour.classList.remove("timeline__hour--dragover")

    const taskId = event.dataTransfer.getData("text/plain")
    const card = document.getElementById(taskId)
    if (!card) return

    const assignmentId = card.dataset.taskCardIdValue
    const hourValue = parseInt(hour.dataset.hour)

    // Determine minute based on Y-position within the hour cell
    const rect = hour.getBoundingClientRect()
    const offsetY = event.clientY - rect.top
    const minuteFraction = offsetY / rect.height
    const minute = Math.round(minuteFraction * 60 / 15) * 15  // snap to 15-min slots

    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    const body = new URLSearchParams({
      date: this.dateValue,
      hour: hourValue,
      minute: Math.min(45, minute)
    })

    fetch(`/task_assignments/${assignmentId}/timebox`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "text/vnd.turbo-stream.html"
      },
      body: body
    })
  }
}
```

### 4. Render timeboxed tasks on the timeline

In `app/views/days/_timeline.html.erb`, replace the empty timebox loop with real positioning:

```erb
<%# locals: (date:, events:, tasks:) %>
<div class="timeline" id="timeline_<%= date %>" data-controller="timeline" data-timeline-date-value="<%= date %>">
  <% (7..21).each do |hour| %>
    <div class="timeline__hour"
         data-timeline-target="hour"
         data-hour="<%= hour %>"
         data-action="dragover->timeline#dragover drop->timeline#drop dragenter->timeline#dragenter dragleave->timeline#dragleave">
      <span class="timeline__hour-label"><%= hour < 12 ? "#{hour}am" : (hour == 12 ? "noon" : "#{hour - 12}pm") %></span>
    </div>
  <% end %>

  <%# Calendar events %>
  <% events.each do |event| %>
    <% next unless event[:start_hour] %>
    <div class="timeline__block timeline__block--<%= event[:source] || 'basecamp' %>"
         style="top: <%= (event[:start_hour] - 7) * 60 %>px; height: <%= (event[:duration_hours] || 1) * 60 %>px;">
      <strong><%= event[:title] %></strong>
      <span class="text-xs"><%= event[:time] %></span>
    </div>
  <% end %>

  <%# Timeboxed tasks %>
  <% tasks.select(&:timeboxed?).each do |task| %>
    <% start = task.start_hour_in(current_user.timezone) %>
    <% next if start.nil? || start < 7 || start > 21 %>
    <div class="timeline__block timeline__block--task <%= 'timeline__block--completed' if task.completed? %>"
         style="top: <%= (start - 7) * 60 %>px; height: <%= task.duration_hours * 60 %>px;">
      <strong><%= task.title %></strong>
      <span class="text-xs"><%= task.planned_duration_minutes %>m</span>
    </div>
  <% end %>
</div>
```

### 5. CSS — make blocks visible

Add to `app/assets/stylesheets/components/timeline.css`:

```css
.timeline {
  position: relative;
}

.timeline__hour {
  position: relative;
  height: 60px;
  border-top: 1px solid var(--color-border-subtle);
  padding-left: 56px;
}

.timeline__hour--dragover {
  background: var(--color-accent-light);
}

.timeline__block {
  position: absolute;
  left: 56px;
  right: 8px;
  border-radius: var(--radius-sm);
  padding: 6px 10px;
  font-size: 13px;
  z-index: 1;
  overflow: hidden;
}

.timeline__block--basecamp { background: rgba(29, 106, 229, 0.15); border-left: 3px solid var(--color-basecamp); }
.timeline__block--hey      { background: rgba(81, 167, 77, 0.15); border-left: 3px solid var(--color-hey); }
.timeline__block--task     { background: rgba(245, 166, 35, 0.15); border-left: 3px solid var(--color-accent); }
.timeline__block--completed { opacity: 0.5; text-decoration: line-through; }
```

### 6. HEY round-trip job

```ruby
# app/jobs/sync_timebox_to_hey_job.rb
class SyncTimeboxToHeyJob < ApplicationJob
  queue_as :default

  def perform(task_assignment_id)
    task = TaskAssignment.find(task_assignment_id)
    return unless task.user.hey_connected? && task.timeboxed?

    client = HeyClient.new(task.user)
    ends_at = task.planned_start_at + task.planned_duration_minutes.minutes

    if task.hey_calendar_event_id.present?
      # TODO: HeyClient needs an update_todo method — add when needed
      client.create_todo(title: task.title, starts_at: task.planned_start_at, ends_at: ends_at)
    else
      result = client.create_todo(title: task.title, starts_at: task.planned_start_at, ends_at: ends_at)
      task.update!(hey_calendar_event_id: result&.dig("id")&.to_s)
    end
  rescue HeyClient::AuthError => e
    Rails.logger.warn("HEY timebox sync failed for task #{task_assignment_id}: #{e.message}")
  end
end
```

Out-of-scope but worth noting: if the user moves a timeboxed task to a different time, this job should also update HEY (not just create new). Add an `update_todo` method to `HeyClient` when that becomes necessary — for now, only the first drop syncs.

## Acceptance criteria

- [ ] Migration runs cleanly
- [ ] Drag a card from the day view's task list onto the timeline → card visually lands at the dropped hour, persists after reload
- [ ] Drop near the top of an hour cell snaps to :00; near the middle to :15/:30; near the bottom to :45
- [ ] Block height matches `planned_duration_minutes`
- [ ] If duration was nil, it defaults to 60 minutes
- [ ] Timeboxed task block uses the amber accent color, distinct from blue/green calendar events
- [ ] Completed timeboxed tasks render muted with strikethrough on the timeline
- [ ] When HEY is connected, the dropped task creates a HEY Calendar todo (verified in HEY UI)
- [ ] When HEY is not connected, the timebox is local-only and the drop still works

## Out of scope

- Resizing a block by dragging its bottom edge
- Moving a block by dragging it on the timeline
- HEY → Daybreak inbound sync of timeboxes (HEY is the source of truth for events but Daybreak is the source of truth for tasks)
- Multi-day blocks
- Conflict detection ("you have a meeting then")
