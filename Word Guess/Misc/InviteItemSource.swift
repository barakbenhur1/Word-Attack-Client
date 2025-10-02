//
//  InviteItemSource.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import UIKit
import LinkPresentation

final class InviteItemSource: NSObject, UIActivityItemSource {
    private let text: String
    private let urls: [URL]
    private let image: UIImage?
    private let subject: String
    
    init(text: String, urls: [URL], image: UIImage? = nil, subject: String) {
        self.text = text
        self.urls = urls
        self.image = image
        self.subject = subject
        super.init()
    }
    
    // Placeholder
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        text
    }
    
    // Primary item: keep it as TEXT so the first HTTPS in it becomes the preview link
    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        text
    }
    
    // Subject (Mail only)
    func activityViewController(_ activityViewController: UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        subject
    }
    
    // Extra items per target. Messaging apps behave best with text-only.
    func activityViewController(_ activityViewController: UIActivityViewController,
                                itemsForActivityType activityType: UIActivity.ActivityType?) -> [Any] {
        
        let raw = activityType?.rawValue ?? ""
        
        // Known message/social extensions → return ONLY the text (which includes your web link)
        let messageLike: Set<String> = [
            UIActivity.ActivityType.message.rawValue,                  // iMessage/SMS
            "net.whatsapp.WhatsApp.ShareExtension",                    // WhatsApp
            "ph.telegra.Telegraph.Share", "org.telegram.messenger.Share", // Telegram variants
            "com.facebook.Messenger.ShareExtension",                   // FB Messenger
            "com.apple.UIKit.activity.PostToTwitter",
            "com.apple.UIKit.activity.PostToFacebook",
            "com.apple.reminders.RemindersEditorExtension",
        ]
        
        if messageLike.contains(raw) {
            return [text]
        }
        
        // Everything else: include deep link + App Store URL (if any), plus image if provided
        var items: [Any] = [text]
        items.append(contentsOf: urls)
        if let image { items.append(image) }
        return items
    }
    
    // Rich link preview (iOS 13+)
    @available(iOS 13.0, *)
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let md = LPLinkMetadata()
        md.title = subject
        
        if let httpURL = urls.first(where: { ($0.scheme ?? "").hasPrefix("http") }) {
            md.url = httpURL
        }
        if let image {
            md.iconProvider = NSItemProvider(object: image)
        }
        return md
    }
}
