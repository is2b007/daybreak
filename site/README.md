# Daybreak marketing site

Static HTML/CSS for [daybreakplanner.com](https://daybreakplanner.com). No build step, no framework, no dependencies.

## Preview locally

The page loads ES modules, so serve it rather than opening the file:

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

- `assets/site.css`: design tokens mirror `app/assets/stylesheets/application.css` (light and dark).
- `assets/sky.js`: copy of `app/javascript/sky/scene.js`, the ritual sky. Keep them in sync.
- `assets/site.js`: gives each sky canvas its time of day, pauses skies that are off screen, and runs the copy button.
- `assets/fonts/`: Newsreader, self-hosted (no Google Fonts, so no third-party requests). Mirror of `app/assets/fonts/`.
- `assets/tiles/`, `assets/stamps/`: Basecamp/HEY tiles and the stamp masks, mirrored from `app/assets/images/`.
- `assets/shots/focus.webp`: Focus mode screenshot.
- `assets/daybreak-logo.svg`: the rounded glass-dome mark used next to the wordmark. Mirror of `app/assets/images/daybreak-logo.svg`.
- `assets/daybreak-icon.svg`: the square app-icon tile, used as the favicon. Mirror of `public/icon.svg`.

`/assets/*` is served with a one-year immutable cache (see `vercel.json`), so give a changed asset a new filename.

## Updating the site

Edit `index.html` directly. Everything is one page, no templating. Commit and push, Vercel redeploys automatically.
