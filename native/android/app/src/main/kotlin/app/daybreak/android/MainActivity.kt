package app.daybreak.android

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.webkit.WebView
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AlertDialog
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.turbo.config.PathConfiguration
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.Navigator
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.util.applyDefaultImeWindowInsets

private const val MIN_WEBVIEW = 111

class MainActivity : HotwireActivity() {
    // Set before super.onCreate, which asks for navigatorConfigurations().
    private var serverUrl = "https://localhost"
    private var pendingLink: Uri? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        val url = Server.url(this)
        if (url == null) {
            super.onCreate(savedInstanceState)
            startActivity(Intent(this, SetupActivity::class.java))
            finish()
            return
        }
        serverUrl = url

        Hotwire.loadPathConfiguration(
            context = this,
            location = PathConfiguration.Location(
                assetFilePath = "json/path-configuration.json",
                remoteFileUrl = "$serverUrl/native/android/path-configuration"
            )
        )

        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<View>(R.id.root).applyDefaultImeWindowInsets()

        pendingLink = intent?.data
        if (savedInstanceState == null) checkWebView()
    }

    // Daybreak needs Chrome 111 or newer to draw. Some tablets (the DC-1 among
    // them) ship an older Android System WebView that only updates from Play.
    private fun checkWebView() {
        val version = WebView.getCurrentWebViewPackage()?.versionName ?: return
        val major = version.substringBefore('.').toIntOrNull() ?: return
        if (major >= MIN_WEBVIEW) return

        AlertDialog.Builder(this)
            .setTitle(R.string.webview_title)
            .setMessage(getString(R.string.webview_body, version))
            .setPositiveButton(R.string.webview_update) { _, _ ->
                val play = Uri.parse("market://details?id=com.google.android.webview")
                runCatching { startActivity(Intent(Intent.ACTION_VIEW, play)) }
            }
            .setNegativeButton(R.string.webview_later, null)
            .show()
    }

    override fun navigatorConfigurations() = listOf(
        NavigatorConfiguration(
            name = "main",
            startLocation = serverUrl,
            navigatorHostId = R.id.main_nav_host
        )
    )

    override fun onNavigatorReady(navigator: Navigator) {
        pendingLink?.let { handleLink(it, navigator) }
        pendingLink = null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val navigator = delegate.currentNavigator
        val link = intent.data ?: return
        if (navigator != null) handleLink(link, navigator) else pendingLink = link
    }

    // daybreak://signed-in?code=... comes back from the browser after sign-in;
    // daybreak://switch-server comes from the link in Settings.
    private fun handleLink(link: Uri, navigator: Navigator) {
        if (link.scheme != "daybreak") return
        when (link.host) {
            "signed-in" -> {
                val code = link.getQueryParameter("code") ?: return
                val verifier = Server.takeSignInVerifier(this) ?: return
                Thread {
                    Server.signIn(serverUrl, code, verifier)
                    // Signed in or not, the start page shows which (week or sign-in).
                    runOnUiThread { navigator.reset() }
                }.start()
            }
            // Any web page can open a daybreak:// link, so check first.
            "switch-server" -> AlertDialog.Builder(this)
                .setMessage(R.string.switch_server_confirm)
                .setPositiveButton(R.string.switch_server) { _, _ ->
                    Server.forget(this)
                    startActivity(Intent(this, SetupActivity::class.java))
                    finish()
                }
                .setNegativeButton(android.R.string.cancel, null)
                .show()
        }
    }
}
