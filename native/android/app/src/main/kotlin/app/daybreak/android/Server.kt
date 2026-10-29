package app.daybreak.android

import android.content.Context
import android.os.Build
import android.util.Base64
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.security.SecureRandom

// The Daybreak this app talks to: the hosted one, or someone's own server.
object Server {
    private const val PREFS = "daybreak"
    private const val KEY_URL = "server_url"
    private const val KEY_VERIFIER = "sign_in_verifier"

    fun url(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY_URL, null)

    fun save(context: Context, url: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_URL, url).apply()
    }

    fun forget(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY_URL).apply()
    }

    // "daybreak.example.com" -> "https://daybreak.example.com", no trailing slash.
    fun normalize(input: String): String {
        val trimmed = input.trim().trimEnd('/')
        return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) trimmed else "https://$trimmed"
    }

    // Asks the server's /native/config whether it is a Daybreak, and returns its
    // address after any redirects (example.com -> www.example.com). Runs on a
    // background thread.
    fun check(url: String): Result<String> = runCatching {
        val connection = URL("$url/native/config").openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        try {
            if (connection.responseCode != 200) error("not a Daybreak")
            val body = connection.inputStream.bufferedReader().readText()
            if (JSONObject(body).optString("app") != "daybreak") error("not a Daybreak")
            connection.url.toString().removeSuffix("/native/config")
        } finally {
            connection.disconnect()
        }
    }

    // Starts a sign-in: keeps a new secret and returns its SHA-256 for the server.
    // Only this app can then redeem the code that comes back (PKCE).
    fun newSignInChallenge(context: Context): String {
        val verifier = base64(ByteArray(32).also { SecureRandom().nextBytes(it) })
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY_VERIFIER, verifier).apply()
        return base64(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()))
    }

    // The secret for the sign-in in progress, once; null if this app didn't start one.
    fun takeSignInVerifier(context: Context): String? {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return prefs.getString(KEY_VERIFIER, null).also { prefs.edit().remove(KEY_VERIFIER).apply() }
    }

    private fun base64(bytes: ByteArray) =
        Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_PADDING or Base64.NO_WRAP)

    // The server switches to the Paper theme on a Daylight DC-1.
    val isDaylight: Boolean
        get() = listOf(Build.MANUFACTURER, Build.BRAND, Build.MODEL).any {
            it.orEmpty().contains("daylight", ignoreCase = true) || it.orEmpty().contains("DC-1", ignoreCase = true)
        }
}
