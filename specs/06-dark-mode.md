# Spec 06 — Dark mode wiring

Make the dark theme actually work end-to-end: a quick toggle in the nav, instant client-side application, server-side persistence, and proper system-preference detection.

## Context

Dark mode is half-built:

- ✅ `app/assets/stylesheets/dark-mode.css` exists with `@media (prefers-color-scheme: dark)` and `[data-theme="dark"]` rules
- ✅ `User.theme` column with `system | light | dark` validation
- ✅ Settings form has a radio group for theme
- ✅ `<html data-theme="<%= current_user&.theme || 'system' %>">` in the layout
- ✅ `dark_mode_controller.js` has a `toggle()` method
- ❌ The Stimulus controller is **never connected to any element** — its `connect()` runs nowhere
- ❌ The Settings radio just submits the form; there's no live preview
- ❌ When `theme` is `"system"`, `<html data-theme="system">` is wrong — `system` should mean *no* `data-theme` attribute so the CSS media query takes over
- ❌ No nav-bar toggle for quick switching (the spec calls for one)
- ❌ Theme is not persisted to localStorage as a fallback for unauthenticated pages

## Files that need work

| File | Change |
|---|---|
| `app/views/layouts/application.html.erb` | Fix the `data-theme` rendering, attach `dark_mode` controller to `<html>`, add a nav toggle |
| `app/javascript/controllers/dark_mode_controller.js` | Add `cycle()` action, persist locally, fetch backend update on the fly |
| `app/controllers/settings_controller.rb` | Add a small JSON endpoint so the toggle can save without a full form submit (optional but cleaner) |
| `app/assets/stylesheets/dark-mode.css` | Verify the media query and `[data-theme="dark"]` rules |
| `app/assets/stylesheets/components/navigation.css` | Style the toggle button |

## Implementation

### 1. Fix the layout

```erb
<%# app/views/layouts/application.html.erb — top %>
<!DOCTYPE html>
<html
  <% theme = current_user&.theme || "system" %>
  <%= "data-theme=\"#{theme}\"".html_safe unless theme == "system" %>
  data-controller="dark-mode"
  data-dark-mode-theme-value="<%= theme %>">
```

The key change: when `theme == "system"`, **don't** render `data-theme` at all. The CSS media query handles it. When the user picks light or dark explicitly, the attribute pins it.

### 2. dark_mode_controller — three-state cycle

```js
// app/javascript/controllers/dark_mode_controller.js
import { Controller } from "@hotwired/stimulus"

const ORDER = ["system", "light", "dark"]
const ICONS = {
  system: '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>',
  light:  '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>',
  dark:   '<svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>'
}

export default class extends Controller {
  static values = { theme: String }
  static targets = ["icon"]

  connect() {
    this.applyTheme(this.themeValue || "system")
    this.updateIcon()
  }

  cycle() {
    const current = this.themeValue || "system"
    const next = ORDER[(ORDER.indexOf(current) + 1) % ORDER.length]
    this.themeValue = next
    this.applyTheme(next)
    this.updateIcon()
    this.persist(next)
  }

  applyTheme(theme) {
    const root = document.documentElement
    if (theme === "system") {
      root.removeAttribute("data-theme")
    } else {
      root.dataset.theme = theme
    }
  }

  updateIcon() {
    if (!this.hasIconTarget) return
    this.iconTarget.innerHTML = ICONS[this.themeValue || "system"]
  }

  persist(theme) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    fetch("/settings", {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken,
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      body: JSON.stringify({ user: { theme: theme } })
    })
  }
}
```

### 3. Nav-bar toggle

Add to `application.html.erb` inside `nav__right`, before the settings link:

```erb
<button class="nav__icon-btn"
        data-action="click->dark-mode#cycle"
        data-dark-mode-target="icon"
        title="Theme">
  <%# Initial icon set by JS on connect %>
</button>
```

The empty button gets its SVG injected by `dark_mode_controller#updateIcon` on `connect()`. To prevent a flash of empty button on first paint, server-render the matching SVG inline:

```erb
<button class="nav__icon-btn"
        data-action="click->dark-mode#cycle"
        data-dark-mode-target="icon"
        title="Theme">
  <%# server-render initial icon to avoid flash %>
  <% theme = current_user&.theme || "system" %>
  <% case theme %>
  <% when "light" %><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>
  <% when "dark" %><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12.79A9 9 0 1 1 11.21 3 7 7 0 0 0 21 12.79z"/></svg>
  <% else %><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="3" width="20" height="14" rx="2"/><line x1="8" y1="21" x2="16" y2="21"/><line x1="12" y1="17" x2="12" y2="21"/></svg>
  <% end %>
</button>
```

### 4. Settings controller — accept JSON

The existing `update` already redirects on success and re-renders on failure. Make it respond to JSON too:

```ruby
def update
  if current_user.update(settings_params)
    respond_to do |format|
      format.html { redirect_to settings_path, notice: "Saved." }
      format.json { head :ok }
    end
  else
    respond_to do |format|
      format.html { render :show, status: :unprocessable_entity }
      format.json { render json: { errors: current_user.errors }, status: :unprocessable_entity }
    end
  end
end
```

### 5. Settings page — live preview on radio change

The settings form has a radio group. Wire it to the same `dark-mode#cycle`-style action:

```erb
<%# app/views/settings/show.html.erb — replace the theme section %>
<div class="settings__section">
  <div class="settings__section-title">Theme</div>
  <div class="form-group">
    <% %w[system light dark].each do |theme| %>
      <label class="flex items-center gap-2 mb-2">
        <%= f.radio_button :theme, theme,
              data: { action: "change->dark-mode#applyFromRadio", theme: theme } %>
        <span class="text-sm"><%= theme.capitalize %></span>
      </label>
    <% end %>
    <p class="text-xs text-muted mt-2">System follows your device. Light and dark stay put.</p>
  </div>
</div>
```

Add a method to `dark_mode_controller`:

```js
applyFromRadio(event) {
  const theme = event.target.dataset.theme
  this.themeValue = theme
  this.applyTheme(theme)
  this.updateIcon()
  // Don't persist here — the form submit handles it
}
```

The Settings form submission still hits `settings#update` and the page reloads with the persisted theme.

### 6. Verify the CSS

Open `app/assets/stylesheets/dark-mode.css` and confirm both rules exist:

```css
@media (prefers-color-scheme: dark) {
  :root {
    --color-canvas: #1A1D21;
    --color-surface: #232629;
    --color-text: #E8EAED;
    /* ...all the overrides... */
  }
}

[data-theme="dark"] {
  --color-canvas: #1A1D21;
  --color-surface: #232629;
  --color-text: #E8EAED;
  /* ...same overrides... */
}

[data-theme="light"] {
  /* The light defaults — needed when system is dark but user pinned light */
  --color-canvas: #FAFAF7;
  --color-surface: #FFFFFF;
  --color-text: #1D2D35;
  /* ...etc... */
}
```

If `[data-theme="light"]` is missing, that's a bug — without it, a user on a dark-mode OS who pins "light" will still see dark, because the media query fires regardless.

## Acceptance criteria

- [ ] Nav toggle cycles `system → light → dark → system`
- [ ] Each cycle: instant visual change, no page reload, persisted to the user record (verify with `bin/rails console`)
- [ ] On `system`, the rendered HTML has no `data-theme` attribute on `<html>`
- [ ] On a macOS dark-mode device with `theme: system`, Daybreak is dark
- [ ] On the same device with `theme: light`, Daybreak is light (the user override wins)
- [ ] Settings radio buttons preview live and persist on form submit
- [ ] No flash of wrong theme on initial page load
- [ ] Login and onboarding pages also respect system preference (they don't have a current_user yet, but the media query handles it)

## Out of scope

- Per-page theme override
- A "schedule" option (auto-switch at sunset)
- Animating the theme transition (would clash with the calm aesthetic)
