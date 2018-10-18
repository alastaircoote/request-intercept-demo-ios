//
//  URLConvert.swift
//  RequestInterceptDemoApp
//
//  Created by Alastair on 10/18/18.
//  Copyright © 2018 NYTimes. All rights reserved.
//

import Foundation

class URLConvert {
    // We need to map URLs between the custom scheme and HTTPS. URLComponents
    // is the easiest way to do that.
    static func requestdemoURLToHTTPS(originalURL: URL) -> URL {
        var mutableURL = URLComponents(url: originalURL, resolvingAgainstBaseURL: true)!
        mutableURL.scheme = "https"
        return mutableURL.url!
    }
    
    static func httpsURLToRequestDemo(originalURL: URL) -> URL {
        var mutableURL = URLComponents(url: originalURL, resolvingAgainstBaseURL: true)!
        mutableURL.scheme = "requestdemo"
        return mutableURL.url!
    }
}
