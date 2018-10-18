import UIKit
import WebKit

// A very simple demo of how you might go about using WKURLSchemeHandler to serve
// a mix of locally cached assets with remote ones. The coding style is terrible
// (exclamation points all over the place, tsk tsk) but hopefully it should convey
// the basic concept.
//
// ---

// Very simple example of what we'd need to store in a cached asset:

struct CacheEntry {
    let url: URL
    let statusCode: Int
    let headers: [String: String]
    let content: Data
}

let cachedItems: [CacheEntry] = [
    CacheEntry(
        url: URL(string: "https://request-intercept-demo.glitch.me/style.css")!,
        statusCode: 200,
        headers: [
            "Content-Type": "text/css; charset=utf-8",
        ],
        content: """
            body {
                background: red;
                color: white;
            }
        """.data(using: .utf8)!
    ),
]

class ViewController: UIViewController, WKURLSchemeHandler {
    let schemeTaskManager = URLSchemeTaskManager()

    override func viewDidLoad() {
        // First we create a custom configuration, and add this class
        // as a handler for our custom URL scheme, "requestdemo":

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(self, forURLScheme: "requestdemo")

        // Then use that config to create the webview and add it to the controller:
        let webview = WKWebView(frame: view.frame, configuration: config)
        view.addSubview(webview)

        // Then, finally, send a request using that custom scheme, but that we want
        // to map to an HTTPS url:
        webview.load(URLRequest(url: URL(string: "requestdemo://request-intercept-demo.glitch.me")!))
    }

    // These two functions are the implementations of WKURLSchemeHandler:

    func webView(_: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let originalURL = urlSchemeTask.request.url!

        // Map the requestdemo: URL to https:
        let httpsURL = URLConvert.requestdemoURLToHTTPS(originalURL: originalURL)

        // Then check if we have a cached asset with that URL.
        let cachedItem = cachedItems.first(where: { $0.url.absoluteString == httpsURL.absoluteString })

        if let cachedItemExists = cachedItem {
            NSLog("Found cached response for \(httpsURL.absoluteString)")

            // If the cached asset exists, we construct an HTTPURLResponse using the custom scheme URL,
            // and set the headers we have in the cache entry:

            let urlResponse = HTTPURLResponse(url: originalURL, statusCode: cachedItemExists.statusCode, httpVersion: nil, headerFields: cachedItemExists.headers)!

            // Then send that initial response back to the webview:
            urlSchemeTask.didReceive(urlResponse)

            // From here, WKURLSchemeHandler supports sending chunks of data, so in a real-world
            // scenario we might implement streaming from disk rather than loading all of the content
            // into memory. But for this demo we'll just immediately output the cached asset content
            // and finish the response:

            urlSchemeTask.didReceive(cachedItemExists.content)
            urlSchemeTask.didFinish()

        } else {
            NSLog("No cached response for \(httpsURL.absoluteString)")

            schemeTaskManager.process(schemeTask: urlSchemeTask, httpsURL: httpsURL)
        }
    }

    func webView(_: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        schemeTaskManager.stop(schemeTask: urlSchemeTask)
    }
}
