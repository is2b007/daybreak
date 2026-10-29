package app.daybreak.android

import android.content.Context
import android.content.res.Configuration

// Daybreak is laid out for laptops. On a Daylight DC-1 everything, the web
// pages included, is drawn 15% larger by raising the density the app sees.
object Scale {
    private const val DAYLIGHT = 1.15f

    fun wrap(base: Context): Context {
        if (!Server.isDaylight) return base
        val config = Configuration(base.resources.configuration)
        config.densityDpi = (config.densityDpi * DAYLIGHT).toInt()
        return base.createConfigurationContext(config)
    }
}
