//
//  MainViewModel.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 23/09/2025.
//

import SwiftUI
import FirebaseRemoteConfig

struct WordZapFireBaseConfig {
    var adFrequency: Int = 7
}

@Observable
class FirebaseFlagManager: ObservableObject {
    var remoteConfig: WordZapFireBaseConfig
    
    required init() {
        remoteConfig = .init()
    }
    
    func refashRemoteConfig() {
        RemoteConfig.remoteConfig().fetchAndActivate { [weak self] (status, error) in
            guard let self else { return }
            if status == .successFetchedFromRemote || status == .successUsingPreFetchedData {
                let config = RemoteConfig.remoteConfig()
                let adFrequency = config.configValue(forKey: "show_interstitial_ad").numberValue.intValue
                remoteConfig = .init(adFrequency: adFrequency)
            } else { remoteConfig = .init() }
        }
    }
}
