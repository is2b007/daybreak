package app.daybreak.android

import android.content.Context
import android.content.res.Configuration

// On a Daylight DC-1 the app's own screens are drawn 15% larger, by raising
// the density they see. The web pages scale themselves (data-device="daylight").
object Scale {
    private const val DAYLIGHT = 1.15f

    fun wrap(base: Context): Context {
        if (!Server.isDaylight) return base
        val config = Configuration(base.resources.configuration)
        config.densityDpi = (config.densityDpi * DAYLIGHT).toInt()
        return base.createConfigurationContext(config)
    }
}
