//
//  WordZapWidgetExtensionLiveActivity.swift
//  WordZapWidgetExtension
//
//  Created by Barak Ben Hur on 30/08/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct WordZapWidgetExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct WordZapWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WordZapWidgetExtensionAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension WordZapWidgetExtensionAttributes {
    fileprivate static var preview: WordZapWidgetExtensionAttributes {
        WordZapWidgetExtensionAttributes(name: "World")
    }
}

extension WordZapWidgetExtensionAttributes.ContentState {
    fileprivate static var smiley: WordZapWidgetExtensionAttributes.ContentState {
        WordZapWidgetExtensionAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: WordZapWidgetExtensionAttributes.ContentState {
         WordZapWidgetExtensionAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: WordZapWidgetExtensionAttributes.preview) {
   WordZapWidgetExtensionLiveActivity()
} contentStates: {
    WordZapWidgetExtensionAttributes.ContentState.smiley
    WordZapWidgetExtensionAttributes.ContentState.starEyes
}
