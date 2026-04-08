# Spec 04 — Stamp completion flow

Wire up the ink-stamp animation so completing a task feels physical: a stamp presses down with a small rotation, the card mutes and gets a strikethrough, then it slides to the bottom of the day.

## Context

The stamp is the heartbeat of the product — it's what makes Daybreak feel like a planner instead of a checklist. The pieces exist but nothing is wired together:

- ✅ 5 stamp SVGs in `app/views/stamps/_*.html.erb`
- ✅ `task_card_controller.js#complete()` makes the right POST
- ✅ `stamp_controller.js#animate()` triggers a CSS animation
- ✅ Server-side: `TaskAssignment#complete!` sets `status: completed` and a random `stamp_rotation_degrees`
- ✅ Server-side: `TaskAssignmentsController#complete` re-renders the card via Turbo Stream
- ❌ **No DOM trigger calls `task_card#complete`** — there's no checkbox, click target, or button
- ❌ **`stamp_controller#animate` is never invoked** — `task-card` template uses the `task-card` controller, not `stamp`
- ❌ **No animation BEFORE the Turbo Stream replace** — the Turbo Stream just swaps in the completed card with the stamp already there, missing the satisfying press
- ❌ **No reorder** — completed cards don't slide to the bottom

The spec calls for: tap → stamp presses → card mutes → reorder. All in one flowing motion.

## Files that need work

| File | Change |
|---|---|
| `app/views/shared/_task_card.html.erb` | Add a click target (or checkbox) that fires `task-card#complete` |
| `app/javascript/controllers/task_card_controller.js` | Add an `animateThenComplete()` method that runs the stamp animation locally before POST, and falls back gracefully on slow networks |
| `app/javascript/controllers/stamp_controller.js` | Either delete (merge into task_card) or use it via cross-controller dispatch |
| `app/assets/stylesheets/animations.css` | Verify the `stamp-press` keyframes exist and look right |
| `app/assets/stylesheets/components/cards.css` | Add the muted/completed state with strikethrough and reorder rule |
| `app/controllers/task_assignments_controller.rb#complete` | Return turbo stream that **moves** the card to the bottom of the column, not just replaces in place |

## Implementation

### 1. Click target on the task card

The card already has the title and a size badge. Adding a "complete" button competes for visual space. Two options — pick the cleaner one:

**Option A — click anywhere on the card title:**

```erb
<%# in app/views/shared/_task_card.html.erb, replace the title span %>
<button class="task-card__complete-button"
        data-action="click->task-card#animateThenComplete"
        title="Mark done">
  <%= task.title %>
</button>
```

The button is invisible chrome — `task-card__complete-button` should be styled as `display: contents` or `all: unset` so it looks identical to the current span. Add to `components/cards.css`:

```css
.task-card__complete-button {
  all: unset;
  cursor: pointer;
  flex: 1;
  text-align: left;
}
.task-card__complete-button:hover {
  color: var(--color-text);
}
```

**Option B — small checkbox on the left of the card.** Heavier visually but more discoverable. The product spec leans toward Option A (calm, no checkboxes), so use A by default.

For completed cards, the button should be disabled (or an "uncomplete" action — out of scope here).

### 2. task_card_controller — local-first animation

```js
// app/javascript/controllers/task_card_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { id: Number, completed: Boolean }
  static targets = ["stamp"]

  cycleSize(event) {
    event.stopPropagation()
    this.fetch(`/task_assignments/${this.idValue}/cycle_size`)
  }

  animateThenComplete(event) {
    event.preventDefault()
    if (this.completedValue) return

    // 1. Set a random rotation that matches what the server will store (visual continuity)
    const rotation = Math.floor(Math.random() * 7) - 3
    this.element.style.setProperty("--stamp-rotation", `${rotation}deg`)

    // 2. Reveal the stamp element if it's not already in the DOM
    this.injectStamp()

    // 3. Trigger the press animation
    this.element.classList.add("task-card--completing")

    // 4. After the animation completes, POST and let Turbo Stream replace
    this.element.addEventListener("animationend", () => {
      this.element.classList.add("task-card--completed")
      this.fetch(`/task_assignments/${this.idValue}/complete`, { rotation })
    }, { once: true })
  }

  injectStamp() {
    if (this.hasStampTarget) return
    const stamp = document.createElement("div")
    stamp.className = "task-card__stamp"
    stamp.dataset.taskCardTarget = "stamp"
    // The actual SVG comes from the user's stamp choice — fetch from a data attribute set on the body
    stamp.innerHTML = document.querySelector("[data-user-stamp-svg]")?.innerHTML || ""
    this.element.appendChild(stamp)
  }

  fetch(url, body = null) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Accept": "text/vnd.turbo-stream.html",
        "Content-Type": "application/json"
      },
      body: body ? JSON.stringify(body) : null
    })
  }
}
```

The trick: the animation runs locally _first_, then the POST goes out. By the time the Turbo Stream replace lands, the card already shows the stamp — so the swap is invisible. If the network is slow, the user still sees instant feedback. If the network fails, the card looks completed but isn't (refresh recovers — acceptable for a single tap).

For `injectStamp()` to work, the layout needs the user's stamp SVG cached somewhere accessible. Add to `app/views/layouts/application.html.erb`:

```erb
<% if logged_in? %>
  <template data-user-stamp-svg>
    <%= render "stamps/#{current_user.stamp_choice}" %>
  </template>
<% end %>
```

### 3. CSS — the animation

In `app/assets/stylesheets/animations.css`, verify `stamp-press` keyframes exist:

```css
@keyframes stamp-press {
  0%   { transform: rotate(var(--stamp-rotation, 0deg)) scale(1.6); opacity: 0; }
  60%  { transform: rotate(var(--stamp-rotation, 0deg)) scale(0.92); opacity: 1; }
  100% { transform: rotate(var(--stamp-rotation, 0deg)) scale(1); opacity: 1; }
}
```

In `components/cards.css`:

```css
.task-card--completing .task-card__stamp {
  animation: stamp-press 400ms ease-out forwards;
}

.task-card--completed {
  opacity: 0.55;
}

.task-card--completed .task-card__title {
  text-decoration: line-through;
  color: var(--color-text-muted);
}

.task-card--completed .task-card__stamp {
  position: absolute;
  inset: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  pointer-events: none;
  transform: rotate(var(--stamp-rotation, 0deg));
}
```

The card becomes `position: relative` (likely already the case) so the absolutely-positioned stamp overlay anchors to it.

### 4. Server-side — accept the rotation, slide to bottom

Update `TaskAssignment#complete!` to take an optional rotation so the server stores the same value the client just animated:

```ruby
def complete!(rotation: nil)
  update!(
    status: :completed,
    completed_at: Time.current,
    stamp_rotation_degrees: rotation || rand(-3..3)
  )
end
```

And `TaskAssignmentsController#complete`:

```ruby
def complete
  rotation = params[:rotation]&.to_i
  @task.complete!(rotation: rotation)
  WriteCompletionJob.perform_later(@task.id) if @task.basecamp? || @task.hey?

  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: [
        turbo_stream.remove("task_#{@task.id}"),
        turbo_stream.append("day_#{@task.day_plan&.date}_completed",
          partial: "shared/task_card",
          locals: { task: @task, compact: true })
      ]
    end
    format.html { redirect_back fallback_location: root_path }
  end
end
```

This requires the day column template to have a separate completed-tasks list with id `day_<date>_completed`. Add it inside `weeks/_day_column.html.erb`:

```erb
<div class="kanban__tasks" data-sortable-target="taskList" data-date="<%= date %>">
  <% tasks.reject(&:completed?).sort_by(&:position).each do |task| %>
    <%= render "shared/task_card", task: task, compact: true %>
  <% end %>
</div>

<div class="kanban__tasks kanban__tasks--completed" id="day_<%= date %>_completed">
  <% tasks.select(&:completed?).each do |task| %>
    <%= render "shared/task_card", task: task, compact: true %>
  <% end %>
</div>
```

Day view (`app/views/days/show.html.erb`) already separates `@pending_tasks` from `@completed_tasks` — the same `turbo_stream.append` target id needs to exist there too. Add `id="day_<%= @date %>_completed"` to the completed wrapper.

### 5. Delete dead code

Once the stamp animation runs from `task_card_controller`, `stamp_controller.js` is unused. Either:
- Delete `app/javascript/controllers/stamp_controller.js`, or
- Have `task_card_controller#animateThenComplete` dispatch a custom event that `stamp_controller` listens to. The first option is simpler.

If deleting, also remove the `data-task-card-target="stamp"` reference and replace with `data-task-card-target="stamp"` (already correct — `stamp_controller.js` was the unused one, not the target).

## Acceptance criteria

- [ ] Tapping a card title fires the stamp animation
- [ ] The animation completes (~400ms) before the network response is required
- [ ] After animation, the card is muted with strikethrough and the stamp visible at the random rotation
- [ ] The completed card moves to the "completed" section at the bottom of the day column
- [ ] Reload preserves all of this — animation isn't required for state persistence
- [ ] If the task is from Basecamp/HEY, `WriteCompletionJob` runs in the background
- [ ] Completing a task on the day view also reorders correctly
- [ ] `stamp_controller.js` is either deleted or actively used (no dead code)

## Out of scope

- Uncompleting (un-stamping) a task
- Stamp choice changing on the fly without a page reload
- Sound effects
