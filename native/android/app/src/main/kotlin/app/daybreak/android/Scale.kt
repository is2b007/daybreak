package app.daybreak.android

import android.content.Context
import android.content.res.Configuration

// On a Daylight DC-1 the native setup screen is drawn 15% larger, by raising
// the density it sees. The web pages scale themselves (data-device="daylight"),
// so MainActivity stays unscaled: Hotwire shows a screenshot of the last page
// while the next one loads, and at the raised density it was drawn 15% too
// big, which looked like a zoom on every page change.
object Scale {
    private const val DAYLIGHT = 1.15f

    fun wrap(base: Context): Context {
        if (!Server.isDaylight) return base
        val config = Configuration(base.resources.configuration)
        config.densityDpi = (config.densityDpi * DAYLIGHT).toInt()
        return base.createConfigurationContext(config)
    }
}
