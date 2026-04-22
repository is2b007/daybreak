# Daybreak marketing site

Static HTML/CSS for [daybreakplanner.com](https://daybreakplanner.com). No build step, no framework, no dependencies.

## Preview locally

```bash
open site/index.html
```

Or serve it on a local port:

```bash
python3 -m http.server 4000 --directory site
```

## Deploy to Vercel

The site is deployed via Vercel (free, custom domain, edge-cached). One-time setup:

1. In the [Vercel dashboard](https://vercel.com/new), import the `daybreak` GitHub repo.
2. Set **Root Directory** to `site`. Framework Preset is **Other** (no build command, no install command). Everything else: defaults.
3. Deploy. Vercel serves `site/` statically and applies the headers / clean-URL config from `site/vercel.json`.
4. In the project's **Domains** settings, add `daybreakplanner.com` (and `www.daybreakplanner.com` if you want the www redirect). Vercel prints the DNS records you need at your registrar.

After that, every push to `main` auto-deploys. PRs get preview deployments.

## Assets

- `assets/daybreak-logo.svg`: mirror of `app/assets/images/daybreak-logo.svg`. Keep in sync if the app logo changes.
- `assets/logos/basecamp.svg` + `basecamp-mark.svg`: Basecamp wordmark and icon (used on hero and product mockups).
- `assets/logos/hey.svg` + `hey-mark.svg`: HEY wordmark and icon.
- `assets/style.css`: design tokens mirror `app/assets/stylesheets/application.css`.

## Updating the site

Edit `index.html` directly. Everything is one page, no templating. Commit and push, Vercel redeploys automatically.
