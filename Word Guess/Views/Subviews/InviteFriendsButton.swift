//
//  InviteFriendsButton.swift
//  WordZap
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import SwiftUI

struct InviteFriendsButton: View {
    // Configure with your real values
    private let appStoreID = "6751823737"
    private let website    = URL(string: "https://barakbenhur1.github.io/wordzap-support")!
    private let deepScheme = "wordzap"
    private let refUserID: String
    private let onClick: ((InviteItemSource) -> Void)?
    
    init(refUserID: String, onClick: ((InviteItemSource) -> Void)? = nil) { self.refUserID = refUserID; self.onClick = onClick }
    
    var body: some View {
        Button {
            let links = ShareLinks(appStoreID: appStoreID,
                                   websiteFallback: website,
                                   deepScheme: deepScheme,     // <-- your scheme here
                                   ref: refUserID,
                                   campaign: "virality",
                                   source: "share_button",
                                   medium: "app",
                                   inviteCopy: "I’m playing WordZap — come beat my score!".localized)
            
            let icon = UIImage(named: "AppIcon")
            let subject = "Join me on WordZap".localized
            
            // Text has ONLY web+UTM; deep link is a separate URL item
            let itemSource = InviteItemSource(
                text: links.compositeText,
                urls: [links.appStoreURL, links.deepLinkURL],  // <-- deep link separate
                image: icon,
                subject: subject
            )
         
            onClick?(itemSource)
        } label: {
            Label("Share with friends", systemImage: "square.and.arrow.up")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .foregroundStyle(ElevatedButtonStyle.Palette.share.gradient)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThickMaterial)
                        .opacity(0.2)
                )
        }
    }
}
