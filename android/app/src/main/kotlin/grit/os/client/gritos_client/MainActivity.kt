package grit.os.client.gritos_client

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var webTransportChannel: MethodChannel
    private var webView: WebView? = null
    private var connected = false
    private val pendingMessages = ArrayDeque<String>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        webTransportChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "gritos_client/webtransport")
        webTransportChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> connectWebTransport(call, result)
                "send" -> sendWebTransportMessage(call, result)
                "disconnect" -> disconnectWebTransport(result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        destroyWebTransport()
        super.onDestroy()
    }

    private fun connectWebTransport(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val origin = call.argument<String>("origin") ?: "https://api.diogen.space"
        if (url.isNullOrBlank()) {
            result.error("bad_args", "Missing WebTransport url", null)
            return
        }

        runOnMain {
            try {
                destroyWebTransport()
                connected = false
                pendingMessages.clear()

                val nextWebView = createWebView(result)
                webView = nextWebView
                nextWebView.loadDataWithBaseURL(
                    "$origin/",
                    webTransportHtml(url),
                    "text/html",
                    "UTF-8",
                    null,
                )
            } catch (error: Throwable) {
                result.error("connect_failed", error.message, null)
            }
        }
    }

    private fun sendWebTransportMessage(call: MethodCall, result: MethodChannel.Result) {
        val message = call.argument<String>("message")
        if (message == null) {
            result.error("bad_args", "Missing message", null)
            return
        }

        runOnMain {
            if (!connected) {
                pendingMessages.addLast(message)
                result.success(null)
                return@runOnMain
            }
            evaluateSend(message)
            result.success(null)
        }
    }

    private fun disconnectWebTransport(result: MethodChannel.Result) {
        runOnMain {
            destroyWebTransport()
            result.success(null)
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun createWebView(connectResult: MethodChannel.Result): WebView {
        return WebView(this).apply {
            settings.javaScriptEnabled = true
            settings.domStorageEnabled = true
            webChromeClient = WebChromeClient()
            addJavascriptInterface(WebTransportBridge(connectResult), "GritosWebTransport")
        }
    }

    private fun evaluateSend(message: String) {
        val escapedMessage = jsString(message)
        webView?.evaluateJavascript("window.gritosSend($escapedMessage);", null)
    }

    private fun flushPendingMessages() {
        while (pendingMessages.isNotEmpty()) {
            evaluateSend(pendingMessages.removeFirst())
        }
    }

    private fun destroyWebTransport() {
        connected = false
        pendingMessages.clear()
        webView?.evaluateJavascript("window.gritosClose && window.gritosClose();", null)
        webView?.removeJavascriptInterface("GritosWebTransport")
        webView?.destroy()
        webView = null
    }

    private fun emitToFlutter(method: String, arguments: Any?) {
        runOnMain {
            webTransportChannel.invokeMethod(method, arguments)
        }
    }

    private fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }

    private fun jsString(value: String): String {
        val escaped = value
            .replace("\\", "\\\\")
            .replace("'", "\\'")
            .replace("\n", "\\n")
            .replace("\r", "\\r")
            .replace("\u2028", "\\u2028")
            .replace("\u2029", "\\u2029")
        return "'$escaped'"
    }

    private fun webTransportHtml(url: String): String {
        return """
            <!doctype html>
            <meta charset="utf-8">
            <script>
            (() => {
              const endpoint = ${jsString(url)};
              let transport = null;
              let writer = null;
              let reader = null;
              let readBuffer = new Uint8Array(0);

              function post(method, value) {
                GritosWebTransport[method](value == null ? '' : String(value));
              }

              function appendBuffer(left, right) {
                const merged = new Uint8Array(left.length + right.length);
                merged.set(left, 0);
                merged.set(right, left.length);
                return merged;
              }

              function processFrames() {
                while (readBuffer.length >= 4) {
                  const view = new DataView(readBuffer.buffer, readBuffer.byteOffset, readBuffer.byteLength);
                  const payloadLength = view.getUint32(0, false);
                  const frameLength = 4 + payloadLength;
                  if (readBuffer.length < frameLength) return;
                  const payload = readBuffer.slice(4, frameLength);
                  post('onMessage', new TextDecoder().decode(payload));
                  readBuffer = readBuffer.slice(frameLength);
                }
              }

              async function readLoop() {
                try {
                  while (true) {
                    const result = await reader.read();
                    if (result.done) break;
                    readBuffer = appendBuffer(readBuffer, result.value);
                    processFrames();
                  }
                  post('onClosed', '');
                } catch (error) {
                  post('onError', error && error.message ? error.message : error);
                }
              }

              window.gritosSend = async (message) => {
                try {
                  if (!writer) throw new Error('WebTransport writer is not ready');
                  const payload = new TextEncoder().encode(message);
                  const frame = new Uint8Array(4 + payload.length);
                  new DataView(frame.buffer).setUint32(0, payload.length, false);
                  frame.set(payload, 4);
                  await writer.write(frame);
                } catch (error) {
                  post('onError', error && error.message ? error.message : error);
                }
              };

              window.gritosClose = async () => {
                try {
                  if (writer) await writer.close();
                  if (transport) transport.close();
                } catch (_) {}
              };

              (async () => {
                try {
                  if (!('WebTransport' in window)) {
                    throw new Error('Android System WebView does not support WebTransport');
                  }
                  transport = new WebTransport(endpoint);
                  await transport.ready;
                  const stream = await transport.createBidirectionalStream();
                  writer = stream.writable.getWriter();
                  reader = stream.readable.getReader();
                  post('onReady', '');
                  readLoop();
                  transport.closed.then(
                    () => post('onClosed', ''),
                    (error) => post('onError', error && error.message ? error.message : error),
                  );
                } catch (error) {
                  post('onError', error && error.message ? error.message : error);
                }
              })();
            })();
            </script>
        """.trimIndent()
    }

    inner class WebTransportBridge(private val connectResult: MethodChannel.Result) {
        private var connectCompleted = false

        @JavascriptInterface
        fun onReady(value: String) {
            runOnMain {
                connected = true
                if (!connectCompleted) {
                    connectCompleted = true
                    connectResult.success(null)
                }
                flushPendingMessages()
            }
        }

        @JavascriptInterface
        fun onMessage(value: String) {
            emitToFlutter("onMessage", value)
        }

        @JavascriptInterface
        fun onClosed(value: String) {
            runOnMain {
                connected = false
                emitToFlutter("onClosed", null)
            }
        }

        @JavascriptInterface
        fun onError(value: String) {
            runOnMain {
                connected = false
                if (!connectCompleted) {
                    connectCompleted = true
                    connectResult.error("connect_failed", value, null)
                } else {
                    emitToFlutter("onError", value)
                }
            }
        }
    }
}
