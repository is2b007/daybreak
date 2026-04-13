# Daybreak

Daybreak is a personal planning layer between Basecamp and HEY.

It pulls your assignments, schedules, and HEY inputs into one calm workspace so you can shape a realistic day, run a morning/evening ritual, and keep momentum without creating another task silo.

## What Daybreak does

- Signs in with your Basecamp account (OAuth) and syncs assignments/schedules.
- Optionally connects HEY for calendar events, journal sync, and email triage.
- Gives you week and day planning views with drag/drop task flow.
- Includes daily rituals, timeboxing, and a lightweight focus timer.
- Supports personal local tasks alongside synced tasks.

## Tech stack

- Ruby on Rails `8.1`
- SQLite (default)
- Hotwire (`turbo-rails`, `stimulus-rails`)
- Importmap + Propshaft
- Solid Queue / Solid Cache / Solid Cable
- Minitest + Capybara + Selenium

## Prerequisites

- Ruby (matching `.ruby-version` if present, or current Rails 8-compatible Ruby)
- Bundler
- SQLite 3

## Getting started

```bash
git clone https://github.com/is2b007/daybreak.git
cd daybreak
bundle install
bin/rails db:prepare
bin/rails server
```

Then open [http://localhost:3000](http://localhost:3000).

## Configuration

### Basecamp OAuth (required for sign-in)

Daybreak needs Basecamp OAuth credentials. You can provide them either via encrypted Rails credentials or environment variables.

Environment variable fallback:

```bash
export BASECAMP_CLIENT_ID="..."
export BASECAMP_CLIENT_SECRET="..."
```

Credentials alternative (`bin/rails credentials:edit`):

```yml
basecamp:
  client_id: ...
  client_secret: ...
```

### HEY integration (optional)

HEY uses PKCE with Daybreak's built-in public client and can be connected from the app UI (`/auth/hey`).

When connected, Daybreak can sync:

- Calendar events
- HEY journal updates
- HEY email triage (Imbox, Reply Later, Set Aside)

## Running tests

```bash
bin/rails test
```

## Background jobs

Daybreak uses Solid Queue. In development, jobs can run in Puma with `SOLID_QUEUE_IN_PUMA=true` or via:

```bash
bin/jobs
```

## Deployment

The project includes Kamal deployment config in `config/deploy.yml` (template values should be updated for your server/domain).

Typical deploy flow:

```bash
bin/kamal setup
bin/kamal deploy
```

## Project structure

- `app/` - Rails MVC app code, jobs, and services
- `specs/` - implementation specs and scoped product work docs
- `TODOS.md` - follow-up engineering/security tasks
- `CHANGELOG.md` - release history

## Security and operational notes

- Never commit plaintext secrets.
- Keep `config/credentials.yml.enc` and your `RAILS_MASTER_KEY` secure.
- Review `TODOS.md` for known deferred hardening items.

## License

Proprietary (unless you choose to add an OSS license).
