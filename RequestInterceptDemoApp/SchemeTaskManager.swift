//
//  SchemeTaskManager.swift
//  RequestInterceptDemoApp
//
//  Created by Alastair on 9/25/18.
//  Copyright © 2018 NYTimes. All rights reserved.
//

import Foundation
import WebKit

class SchemeTaskAndDependencies: NSObject {
    let schemeTask: WKURLSchemeTask
    let dataTask: URLSessionDataTask

    init(schemeTask: WKURLSchemeTask, dataTask: URLSessionDataTask) {
        self.schemeTask = schemeTask
        self.dataTask = dataTask
    }
}

/// Our URLSchemeTaskManager pairs up a WKURLSchemeTask with a corresponding HTTP request, and streams the
/// data from the latter to the former as it downloads. Once the download completes, it finishes the WKURLSchemeTask.
class URLSchemeTaskManager: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionDataDelegate {
    var urlSession: URLSession!
    var currentTasks = Set<SchemeTaskAndDependencies>()

    override init() {
        super.init()

        // We have to create an instance of URLSession in order to use the delegate methods associated with it.
        urlSession = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: nil)
    }

    func process(schemeTask: WKURLSchemeTask, httpsURL: URL) {
        NSLog("Received request for \(schemeTask.request.url?.absoluteString ?? "unknown URL")")
        var request = schemeTask.request

        // When it arrives the WKURLSchemeTask will have a requestdemo:// URL. We need to replace that URL with an
        // https:// one. But we keep the rest of the URLRequest, so that we can preserve headers etc.

        request.url = httpsURL

        let dataTask = urlSession.dataTask(with: request)

        // Because all of this is happening asynchronously, we need to store both the data task
        // and the scheme task internally, for use in the delegate callbacks:
        currentTasks.insert(SchemeTaskAndDependencies(schemeTask: schemeTask, dataTask: dataTask))

        dataTask.resume()
    }

    // Called when the webview task is cancelled. Sometimes in response to user request, but not always - the webview
    // itself sometimes terminates requests for e.g. videos after downloading a small chunk.
    func stop(schemeTask: WKURLSchemeTask) {
        guard let existingTask = self.currentTasks.first(where: { $0.schemeTask.isEqual(schemeTask) }) else {
            NSLog("Received request to stop download of \(schemeTask.request.url?.absoluteString ?? "unknown URL"), but no download exists")
            return
        }

        NSLog("Stopping download of \(schemeTask.request.url?.absoluteString ?? "unknown URL")")

        // We stop our current download...
        existingTask.dataTask.cancel()
        // ...and then remove the task from our collection, as we no longer need it
        currentTasks.remove(existingTask)
    }

    // Called when we receive the initial response for our request, containing the headers
    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        NSLog("Received initial response for \(response.url?.absoluteString ?? "unknown URL")")

        guard let link = self.currentTasks.first(where: { $0.dataTask == dataTask }) else {
            // We've received a response for a data task we don't know about. This
            // shouldn't ever happen.
            return
        }

        // We now forward on the initial response to our WKURLScheme handler:
        link.schemeTask.didReceive(response)

        // And then instruct this response to become a stream, so we can send data
        // through as soon as it becomes available:
        completionHandler(.allow)
    }

    // Send incoming data from our URLSessionDataTask to the WKURLSchemeTask
    func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let link = self.currentTasks.first(where: { $0.dataTask == dataTask }) else {
            return
        }
        NSLog("Received \(data.count) bytes for \(link.dataTask.response?.url?.absoluteString ?? "unknown URL")")
        
        do {
            try ObjC.catchException {
                link.schemeTask.didReceive(data)
            }
        } catch {
            // If the task was cancelled while this runs the didReceive call throws. This error is acceptable
            // because it's trying to write data for a request that's already been disregarded.
        }
        
    }

    // Once the URLSessionTask has finished, we close up the WKURLSchemeTask, passing along any
    // error if it occurred.
    func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if error?.localizedDescription == "cancelled" {
            // This is called when we manually finish the task in stop(). If we try to call any didFinish()
            // method at this point it'll throw an error, because the WKURLSchemeTask is already cancelled.
            return
        }

        guard let link = self.currentTasks.first(where: { $0.dataTask == task }) else {
            return
        }

        do {
            try ObjC.catchException {
                if let error = error {
                    NSLog("Failing with error for URL \(link.dataTask.response?.url?.absoluteString ?? "unknown URL")")
                    link.schemeTask.didFailWithError(error)
                } else {
                    NSLog("Successfully finishing URL \(link.dataTask.response?.url?.absoluteString ?? "unknown URL")")
                    link.schemeTask.didFinish()
                }
            }
        } catch {
            // Similar to the above, the task will throw if it's been cancelled before this. But again, it's fine, because
            // the webview isn't listening to any response events any more.
        }
        
        

        currentTasks.remove(link)
    }
}
