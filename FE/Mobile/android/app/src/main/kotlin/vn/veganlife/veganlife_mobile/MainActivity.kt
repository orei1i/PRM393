package vn.veganlife.veganlife_mobile

import android.graphics.Rect
import android.os.Build
import android.view.View
import android.view.ViewGroup
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, GESTURE_EXCLUSION_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "setExclusionRects") {
                    result.success(setExclusionRects(parseRects(call.arguments)))
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * The "Hỏi AI" bubble rests on a screen edge, where Android 10+ starts the
     * system Back gesture. Excluding its rect (physical pixels in the Flutter
     * view's coordinates; an empty list clears it) lets the app get those
     * touches. The system honours at most 200 dp per edge; the app sends one
     * rect well under that. Returns false below Android 10 (no edge gesture).
     */
    private fun setExclusionRects(rects: List<Rect>): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val target = findFlutterView(window.decorView) ?: window.decorView
        target.setSystemGestureExclusionRects(rects)
        return true
    }

    private fun parseRects(arguments: Any?): List<Rect> {
        val items = arguments as? List<*> ?: return emptyList()
        return items.mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val left = (map["left"] as? Number)?.toInt() ?: return@mapNotNull null
            val top = (map["top"] as? Number)?.toInt() ?: return@mapNotNull null
            val right = (map["right"] as? Number)?.toInt() ?: return@mapNotNull null
            val bottom = (map["bottom"] as? Number)?.toInt() ?: return@mapNotNull null
            Rect(left, top, right, bottom)
        }
    }

    private fun findFlutterView(view: View): FlutterView? {
        if (view is FlutterView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                val found = findFlutterView(view.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

    private companion object {
        const val GESTURE_EXCLUSION_CHANNEL = "vn.veganlife/gesture_exclusion"
    }
}
