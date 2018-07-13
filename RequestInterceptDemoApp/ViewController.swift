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
    let statusCode:Int
    let headers: [String:String]
    let content: Data
}

let cachedItems: [CacheEntry] = [
    CacheEntry(
        url: URL(string: "https://request-intercept-demo.glitch.me/style.css")!,
        statusCode: 200,
        headers: [
            "Content-Type": "text/css; charset=utf-8"
        ],
        content: """
            body {
                background: red;
                color: white;
            }
        """.data(using: .utf8)!
    )
]

class ViewController: UIViewController, WKURLSchemeHandler {
    
    override func viewDidLoad() {
        
        // First we create a custom configuration, and add this class
        // as a handler for our custom URL scheme, "requestdemo":
        
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(self, forURLScheme: "requestdemo")
        
        // Then use that config to create the webview and add it to the controller:
        let webview = WKWebView(frame: self.view.frame, configuration: config)
        self.view.addSubview(webview)
        
        // Then, finally, send a request using that custom scheme, but that we want
        // to map to an HTTPS url:
        webview.load(URLRequest(url: URL(string: "requestdemo://request-intercept-demo.glitch.me")!))
     
    }

    // We need to map URLs between the custom scheme and HTTPS. URLComponents
    // is the easiest way to do that.
    func requestdemoURLToHTTPS(originalURL:URL) -> URL {
        var mutableURL = URLComponents(url: originalURL, resolvingAgainstBaseURL: true)!
        mutableURL.scheme = "https"
        return mutableURL.url!
    }
    
    func httpsURLToRequestDemo(originalURL:URL)  -> URL {
        var mutableURL = URLComponents(url: originalURL, resolvingAgainstBaseURL: true)!
        mutableURL.scheme = "requestdemo"
        return mutableURL.url!
    }

    // These two functions are the implementations of WKURLSchemeHandler:
    
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        
        let originalURL = urlSchemeTask.request.url!
        
        // Map the requestdemo: URL to https:
        let httpsURL = self.requestdemoURLToHTTPS(originalURL: originalURL)
        
        // Then check if we have a cached asset with that URL.
        let cachedItem = cachedItems.first(where: { $0.url.absoluteString == httpsURL.absoluteString })
      
        if let cachedItemExists = cachedItem {
            
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
            
            // If we don't have a cached asset, we perform a regular network request to the HTTPS
            // url, mirroring the behaviour the webview would normally do. Key benefit here is that
            // the remote servers won't know anything about the custom scheme - to them it'll just
            // look like a regular request.
            
            URLSession.shared.dataTask(with: httpsURL) { (data, response, err) in
                
                if let errExists = err {
                    urlSchemeTask.didFailWithError(errExists)
                    return
                }
                
                // To make sure the webview is internally consistent we need to make sure the
                // URLResponse returned is one with the custom scheme, not the HTTP scheme
                // we just received. So we create a new HTTPURLResponse that takes values from
                // the one.
                
                let httpsResponse = response as! HTTPURLResponse
                
                // We could use originalURL here, but there's a chance we were sent a 301/302 response
                // and were redirected before being sent a response. In a real scenario we'd want to *not*
                // follow that redirect and return the redirect to the browser, through this delegate method:
                // https://developer.apple.com/documentation/foundation/nsurlsessiontaskdelegate/1411626-urlsession
                // but again, for the demo we'll just ignore that potential bug.
                
                let customSchemeURL = self.httpsURLToRequestDemo(originalURL: httpsResponse.url!)
                
                let customResponse = HTTPURLResponse(url: customSchemeURL, statusCode: httpsResponse.statusCode, httpVersion: nil, headerFields: (httpsResponse.allHeaderFields as! [String: String]))!
                
                // Send through our custom scheme headers:
                urlSchemeTask.didReceive(customResponse)
                
                if let dataExists = data {
                    
                    // As with the cache response, in a real implementation we'd want to use
                    // streaming here rather than loading the whole response into memory then
                    // sending it all at once:
                    
                    urlSchemeTask.didReceive(dataExists)
                }
                
                // and finish the response:
                urlSchemeTask.didFinish()
            }.resume()
        }
        
        
        
        
    }
    
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // If we were streaming content this is where we'd make sure we
        // cancel the stream.
    }

}

