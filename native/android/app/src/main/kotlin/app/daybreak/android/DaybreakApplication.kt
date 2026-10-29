package app.daybreak.android

import android.app.Application
import android.content.Context
import dev.hotwire.core.config.Hotwire
import dev.hotwire.core.logging.HotwireLogLevel
import dev.hotwire.navigation.config.defaultFragmentDestination
import dev.hotwire.navigation.config.registerFragmentDestinations
import dev.hotwire.navigation.config.registerRouteDecisionHandlers
import dev.hotwire.navigation.routing.AppNavigationRouteDecisionHandler
import dev.hotwire.navigation.routing.BrowserTabRouteDecisionHandler
import dev.hotwire.navigation.routing.SystemNavigationRouteDecisionHandler

class DaybreakApplication : Application() {
    override fun attachBaseContext(base: Context) = super.attachBaseContext(Scale.wrap(base))

    override fun onCreate() {
        super.onCreate()

        Hotwire.defaultFragmentDestination = WebFragment::class
        Hotwire.registerFragmentDestinations(WebFragment::class, WebBottomSheetFragment::class)
        Hotwire.registerRouteDecisionHandlers(
            SignInRouteDecisionHandler(),
            AppNavigationRouteDecisionHandler(),
            BrowserTabRouteDecisionHandler(),
            SystemNavigationRouteDecisionHandler()
        )

        Hotwire.config.applicationUserAgentPrefix =
            if (Server.isDaylight) "Daybreak Android; Daylight;" else "Daybreak Android;"
        Hotwire.config.webViewDebuggingEnabled = BuildConfig.DEBUG
        Hotwire.config.logger.logLevel = if (BuildConfig.DEBUG) HotwireLogLevel.DEBUG else HotwireLogLevel.NONE
    }
}
