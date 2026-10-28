# Stay signed in across restarts: the native apps' web views drop cookies that
# have no expiry when the app closes.
Rails.application.config.session_store :cookie_store, key: "_daybreak_session", expire_after: 1.year
