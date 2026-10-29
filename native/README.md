# Daybreak apps

Thin native shells around the Daybreak web app. Every app asks "Where's your
Daybreak?" on first launch: the hosted one, or the address of your own server.
A fix to the web app reaches every app without a new build.

| App | Folder | Built with |
| --- | --- | --- |
| Android (tuned for the Daylight DC-1) | `android/` | Hotwire Native Android |
| Mac and Windows | `desktop/` | Tauri 2 |

## How the apps talk to a server

- `GET /native/config` says the server is a Daybreak and where to sign in. The
  apps check it before saving an address.
- Sign-in runs in the system browser. `GET /auth/basecamp?native=1` sends the
  browser to Basecamp, and when Basecamp sends it back the server redirects to
  `daybreak://signed-in?code=...`. The app opens `/native/sign_in?code=...` in
  its web view, which trades the code (single use, two minutes) for a session.
- Settings shows "Use a different server" inside the apps; it opens
  `daybreak://switch-server`.
- The Android app adds `Daylight` to its user agent on a DC-1. There, the
  "Match my system" theme means Paper: black on white and fully greyscale.

## Android

```sh
cd native/android
./gradlew assembleRelease            # app/build/outputs/apk/release/app-release.apk
./gradlew assembleRelease -PdaybreakHostedUrl=https://your.hosted.daybreak
```

To install on the DC-1, copy the APK over (or download it from a release on the
tablet), open it, and allow installs from that app when Android asks.

Release builds use the key in `DAYBREAK_KEYSTORE` when it is set, and the debug
key otherwise. Without the secrets below, GitHub Actions signs each build with a
throwaway key, so a new build won't install over the last one. Add them:
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`,
`ANDROID_KEY_PASSWORD`. Keep the same key forever: Android refuses an update
signed with a different one.

## Mac and Windows

```sh
cd native/desktop
npm ci
npm run tauri dev       # run it
npm run tauri build     # .dmg / .msi under src-tauri/target/release/bundle
```

The builds are not signed yet. On a Mac, open the app the first time with
right-click, Open. On Windows, choose More info, Run anyway.

## Releases

`.github/workflows/apps.yml` builds all three on pull requests that touch
`native/`, and attaches them to a GitHub release when a `v*` tag is pushed. Set
the repository variable `DAYBREAK_HOSTED_URL` to show the "Daybreak hosted"
button; without it the apps only offer your own server.
