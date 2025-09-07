//
//  ScreenManger.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 06/09/2025.
//

import Observation
import UIKit

@Observable
class ScreenManager: Singleton {
    var keepScreenOn: Bool {
        didSet {
            UIApplication.shared.isIdleTimerDisabled = keepScreenOn
        }
    }
    
    override private init() {
        keepScreenOn = false
    }
}
