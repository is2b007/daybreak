# Contributing to Daybreak

Thanks for your interest in Daybreak. This document covers local setup, conventions, and how to propose changes.

## Philosophy

Daybreak is intentionally small and opinionated. It follows the 37signals stack and product philosophy: software should have opinions, not options.

Before proposing a feature, check whether it fits. Changes that add team features, analytics, AI/LLM integrations, notifications, or a fourth view are likely out of scope. When in doubt, open an issue first and we'll chat.

## Tech stack (non-negotiable)

- Ruby on Rails 8.1
- SQLite
- Hotwire (Turbo + Stimulus)
- Propshaft + Import Maps
- Solid Queue / Solid Cache / Solid Cable
- Minitest + Capybara

No React. No Tailwind. No TypeScript. No bundler. No CSS framework. If a new dependency isn't already used by vanilla Rails 8, it probably doesn't belong here.

## Local setup

```bash
git clone https://github.com/is2b007/daybreak.git
cd daybreak
bin/setup
```

`bin/setup` will install gems, prepare the database, and print next steps.

You'll need a Basecamp OAuth app to sign in. Create one at [launchpad.37signals.com/integrations](https://launchpad.37signals.com/integrations) and set the redirect URL to `http://localhost:3000/auth/basecamp/callback`. Then copy `.env.example` to `.env` and fill in the credentials.

Start the dev server:

```bash
bin/dev
```

Open [http://localhost:3000](http://localhost:3000).

## Running tests

```bash
bin/rails test            # unit + integration
bin/rails test:system     # headless browser
```

System tests require a Chrome/Chromium install.

## Submitting changes

1. Fork, branch, commit.
2. Keep PRs small and focused. One change per PR.
3. Include tests for behavior changes.
4. Run `bin/rails test` before pushing.
5. Open a PR against `main`. Describe the user-visible change and link any related issue.

For larger changes, open an issue first to discuss scope.

## Reporting bugs

Open an issue with:

- What you did
- What you expected
- What happened instead
- Rails log excerpt if relevant

For security issues, **do not file a public issue**, see [SECURITY.md](SECURITY.md).
