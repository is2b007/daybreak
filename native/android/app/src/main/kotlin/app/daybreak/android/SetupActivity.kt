package app.daybreak.android

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputMethodManager
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

// First launch: "Where's your Daybreak?"
class SetupActivity : AppCompatActivity() {
    private lateinit var address: EditText
    private lateinit var error: TextView
    private lateinit var connect: Button

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_setup)

        address = findViewById(R.id.address)
        error = findViewById(R.id.error)
        connect = findViewById(R.id.connect)

        val hosted = findViewById<Button>(R.id.hosted)
        if (BuildConfig.HOSTED_URL.isBlank()) {
            hosted.visibility = View.GONE
            findViewById<View>(R.id.or).visibility = View.GONE
        } else {
            hosted.setOnClickListener { use(BuildConfig.HOSTED_URL) }
        }

        connect.setOnClickListener { use(Server.normalize(address.text.toString())) }
        address.setOnEditorActionListener { _, action, _ ->
            if (action == EditorInfo.IME_ACTION_GO) connect.performClick()
            true
        }
    }

    private fun use(url: String) {
        if (url == "https://") return
        error.visibility = View.GONE
        getSystemService(InputMethodManager::class.java)?.hideSoftInputFromWindow(address.windowToken, 0)
        connect.isEnabled = false
        connect.setText(R.string.setup_checking)

        Thread {
            val result = Server.check(url)
            runOnUiThread {
                connect.isEnabled = true
                connect.setText(R.string.setup_connect)
                if (result.isSuccess) {
                    Server.save(this, result.getOrThrow())
                    startActivity(Intent(this, MainActivity::class.java))
                    finish()
                } else {
                    error.text = getString(R.string.setup_error, url)
                    error.visibility = View.VISIBLE
                }
            }
        }.start()
    }
}
