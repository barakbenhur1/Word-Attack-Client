//
//  WordZapWidgetExtensionBundle.swift
//  WordZapWidgetExtension
//
//  Created by Barak Ben Hur on 30/08/2025.
//

import WidgetKit
import SwiftUI

@main
struct WordZapWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        WordZapWidget()
        WordZapWidgetExtensionControl()
        WordZapWidgetExtensionLiveActivity()
    }
}
