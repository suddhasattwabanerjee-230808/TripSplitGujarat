package com.example.trip_split_gujarat

import android.content.Context
import android.net.Uri
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.io.File

/** On-device text recognition for "Scan receipt" (ML Kit Latin model from Play services). */
object ReceiptOcr {
    /** Reads the photo at [path] and returns its text one line per row, top to bottom. */
    fun recognize(context: Context, path: String, done: (String?, String?) -> Unit) {
        val image = try {
            InputImage.fromFilePath(context, Uri.fromFile(File(path)))
        } catch (e: Exception) {
            done(null, "Couldn't open the photo: ${e.message}")
            return
        }
        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
        recognizer.process(image)
            .addOnSuccessListener { text ->
                val lines = text.textBlocks
                    .flatMap { it.lines }
                    .sortedBy { it.boundingBox?.top ?: 0 }
                    .joinToString("\n") { it.text }
                done(lines, null)
            }
            .addOnFailureListener {
                // Play services fetches the model after install; a scan before
                // that finishes fails with UNAVAILABLE.
                val unavailable = it is MlKitException && it.errorCode == MlKitException.UNAVAILABLE
                done(null, if (unavailable) "the bill reader is still downloading, try again in a minute" else it.message ?: "Text recognition failed")
            }
            .addOnCompleteListener { recognizer.close() }
    }
}
