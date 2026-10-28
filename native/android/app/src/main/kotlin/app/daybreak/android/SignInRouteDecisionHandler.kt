package app.daybreak.android

import androidx.browser.customtabs.CustomTabsIntent
import androidx.core.net.toUri
import dev.hotwire.core.turbo.visit.VisitProposal
import dev.hotwire.navigation.activities.HotwireActivity
import dev.hotwire.navigation.navigator.NavigatorConfiguration
import dev.hotwire.navigation.routing.Router

// Basecamp sign-in runs in the system browser, where people already have their
// password saved and sign-in pages work as they expect. The server sends the
// browser back to daybreak://signed-in, which MainActivity picks up.
class SignInRouteDecisionHandler : Router.RouteDecisionHandler {
    override val name = "sign-in"

    override fun matches(proposal: VisitProposal, configuration: NavigatorConfiguration): Boolean {
        val uri = proposal.location.toUri()
        return uri.host == configuration.startLocation.toUri().host && uri.path == "/auth/basecamp"
    }

    override fun handle(
        proposal: VisitProposal,
        configuration: NavigatorConfiguration,
        activity: HotwireActivity
    ): Router.Decision {
        val uri = proposal.location.toUri().buildUpon().clearQuery().appendQueryParameter("native", "android").build()
        CustomTabsIntent.Builder().setShowTitle(true).build().launchUrl(activity, uri)
        return Router.Decision.CANCEL
    }
}
