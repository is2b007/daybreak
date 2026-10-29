package app.daybreak.android

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.TextView
import dev.hotwire.core.turbo.errors.VisitError
import dev.hotwire.navigation.destinations.HotwireDestinationDeepLink
import dev.hotwire.navigation.fragments.HotwireWebBottomSheetFragment
import dev.hotwire.navigation.fragments.HotwireWebFragment

// The web app draws its own header and tab bar, so the native toolbar stays out of the way.
@HotwireDestinationDeepLink(uri = "hotwire://fragment/web")
class WebFragment : HotwireWebFragment() {
    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        toolbarForNavigation()?.visibility = View.GONE
    }

    // Hotwire covers the page with a spinner on every move to a new screen, even
    // when the next page arrives a moment later. Leave the last page showing and
    // only bring in the spinner when loading is very slow (the page shows its
    // own loading outline sooner).
    @SuppressLint("InflateParams")
    override fun createProgressView(location: String): View {
        return layoutInflater.inflate(R.layout.view_progress, null).apply {
            findViewById<View>(R.id.progress_spinner).animate()
                .alpha(1f).setStartDelay(SLOW_LOAD_MS).setDuration(200)
        }
    }

    // Instead of Hotwire's bare "Error loading page": say which server, and
    // offer a way out when it's gone for good.
    @SuppressLint("InflateParams")
    override fun createErrorView(error: VisitError): View {
        return layoutInflater.inflate(R.layout.view_error, null).apply {
            val server = Server.url(requireContext())?.let { Uri.parse(it).host } ?: ""
            findViewById<TextView>(R.id.error_body).text = getString(R.string.error_body, server)
            findViewById<View>(R.id.error_retry).setOnClickListener { refresh(displayProgress = true) }
            findViewById<View>(R.id.error_switch).setOnClickListener {
                startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse("daybreak://switch-server"), requireContext(), MainActivity::class.java)
                )
            }
        }
    }
}

private const val SLOW_LOAD_MS = 2500L

@HotwireDestinationDeepLink(uri = "hotwire://fragment/web/modal/sheet")
class WebBottomSheetFragment : HotwireWebBottomSheetFragment()
