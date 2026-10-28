package app.daybreak.android

import android.content.Context
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

// The Daybreak this app talks to: the hosted one, or someone's own server.
object Server {
    private const val PREFS = "daybreak"
    private const val KEY_URL = "server_url"

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

    // Asks the server's /native/config whether it is a Daybreak. Runs on a background thread.
    fun check(url: String): Result<Unit> = runCatching {
        val connection = URL("$url/native/config").openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        try {
            if (connection.responseCode != 200) error("not a Daybreak")
            val body = connection.inputStream.bufferedReader().readText()
            if (JSONObject(body).optString("app") != "daybreak") error("not a Daybreak")
        } finally {
            connection.disconnect()
        }
    }

    // The server switches to the Paper theme on a Daylight DC-1.
    val isDaylight: Boolean
        get() = listOf(Build.MANUFACTURER, Build.BRAND, Build.MODEL).any {
            it.orEmpty().contains("daylight", ignoreCase = true) || it.orEmpty().contains("DC-1", ignoreCase = true)
        }
}
