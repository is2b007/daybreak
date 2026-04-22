# Daybreak

A calm daily and weekly planner that bridges [Basecamp](https://basecamp.com) and [HEY](https://hey.com) into one opinionated workspace.

**Website:** [daybreakplanner.com](https://daybreakplanner.com)

Daybreak pulls your Basecamp assignments and schedules, optionally layers HEY calendar events and email triage on top, and gives you a week view, a day view, and a focus mode for working on a single task. That's it. No team features, no AI, no notifications, no analytics.

Built on the 37signals stack (Rails 8, Hotwire, SQLite). Designed for self-hosting.

## What Daybreak does

- **Week view:** kanban of days across the week, plus a "sometime" bucket. Drag tasks between days.
- **Day view:** today's tasks with timeboxing, calendar events pinned from HEY, and a daily log.
- **Focus mode:** single-task view with a lightweight timer for deep work.
- **Morning ritual:** review yesterday, plan today, add events to the week.
- **Evening ritual:** close out open items, reflect, log the day.
- **Basecamp sync:** OAuth sign-in; auto-syncs your assignments and schedules; triage your Basecamp inbox into day or week.
- **HEY integration (optional):** calendar events, email triage (Imbox / Reply Later / Set Aside), journal digest, email-to-task.

## Self-host it

Daybreak is single-user and made to run on your own machine or small server. The easiest path is Docker Compose.

### Quick start

```bash
git clone https://github.com/is2b007/daybreak.git
cd daybreak
cp .env.example .env            # fill in BASECAMP_CLIENT_ID / SECRET / RAILS_MASTER_KEY
docker compose up -d
open http://localhost:3000
```

### Get Basecamp credentials

1. Go to [launchpad.37signals.com/integrations](https://launchpad.37signals.com/integrations) and create a new integration.
2. Set the redirect URL to `http://localhost:3000/auth/basecamp/callback` (or your real host when deploying).
3. Copy the Client ID and Client Secret into your `.env` file as `BASECAMP_CLIENT_ID` and `BASECAMP_CLIENT_SECRET`.

### Generate a Rails master key

If you're starting fresh and don't have a `config/master.key`:

```bash
bin/rails credentials:edit
```

That creates `config/master.key`. Copy the contents into `.env` as `RAILS_MASTER_KEY`.

### Data persistence

The `docker-compose.yml` mounts `./storage` from the host into the container, so your SQLite databases and Active Storage blobs survive restarts. Back up this folder and you've backed up everything.

## Develop it

If you want to hack on Daybreak instead of just run it:

```bash
git clone https://github.com/is2b007/daybreak.git
cd daybreak
bin/setup
bin/dev
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for conventions, stack constraints, and how to submit changes.

## Stack

- Ruby on Rails 8.1
- SQLite (Solid Queue / Solid Cache / Solid Cable all on SQLite too)
- Hotwire (Turbo + Stimulus)
- Propshaft + Import Maps, no bundler
- Minitest + Capybara
- Kamal for deployment (optional)

No React, Tailwind, TypeScript, or CSS framework. By design.

## Tests

```bash
bin/rails test            # unit + integration
bin/rails test:system     # headless browser
```

## Deploying to a real server

A Kamal config lives in `config/deploy.yml` with placeholder IP and domain values. Fill those in with your own server and domain, then:

```bash
bin/kamal setup
bin/kamal deploy
```

Kamal expects Docker on the target host and uses the same Dockerfile as the local compose setup.

## Project layout

- `app/` : Rails MVC code, jobs, services
- `site/` : static marketing site served at [daybreakplanner.com](https://daybreakplanner.com)
- `specs/` : implementation specs and product docs
- `CHANGELOG.md` : release history

## License

[MIT](LICENSE). Do what you want; attribution appreciated.

## Support the work

If Daybreak is useful to you, [sponsor the project on GitHub](https://github.com/sponsors/is2b007). Sponsorships keep the site online and pay for the time to maintain it.
