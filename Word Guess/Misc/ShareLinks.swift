//
//  ShareLinks.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import Foundation

struct ShareLinks {
    let appStoreURL: URL        // App Store page
    let webURLWithParams: URL   // Web fallback + UTM + ref  (primary link to share)
    let deepLinkURL: URL        // wordzap://invite?ref=...
    let compositeText: String   // Text that includes ONLY the web link
    
    init(appStoreID: String,
         websiteFallback: URL,
         deepScheme: String = "wordzap",
         ref: String,
         campaign: String = "virality",
         source: String = "share_button",
         medium: String = "app",
         inviteCopy: String = "I’m playing WordZap — come beat my score!") {
        
        // 1) App Store link
        self.appStoreURL = URL(string: "https://apps.apple.com/app/id\(appStoreID)")!
        
        // 2) Web link with UTM + ref  (share THIS as the main link)
        func addParams(to url: URL) -> URL {
            var c = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            var q = c.queryItems ?? []
            q.append(URLQueryItem(name: "ref", value: ref))                  // <-- carry referral
            q.append(URLQueryItem(name: "utm_source", value: source))
            q.append(URLQueryItem(name: "utm_medium", value: medium))
            q.append(URLQueryItem(name: "utm_campaign", value: campaign))
            c.queryItems = q
            return c.url!
        }
        self.webURLWithParams = addParams(to: websiteFallback)
        
        // 3) Custom deep link (some apps ignore this; keep for AirDrop/Copy etc.)
        var deep = URLComponents()
        deep.scheme = deepScheme
        deep.host   = "invite"
        deep.queryItems = [URLQueryItem(name: "ref", value: ref)]
        self.deepLinkURL = deep.url!
        
        // 4) Text shown in most targets — include ONLY the web link
        self.compositeText = """
        \(inviteCopy)
        \(appStoreURL.absoluteString)
        \(webURLWithParams.absoluteString)
        """
    }
}
