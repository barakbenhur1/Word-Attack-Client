//
//  AudioPlayer.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 20/10/2024.
//

import AVFoundation
import SwiftUI

@Observable
class AudioPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    private var audioPlayer: AVAudioPlayer?
    private var stopPlay = false
    private var resumeOnForeground = false
    
    var isOn = UserDefaults.standard.value(forKey: "sound") as? Bool ?? true { didSet { UserDefaults.standard.set(isOn, forKey: "sound") } }
    
    override init() {
        let session = AVAudioSession.sharedInstance()
        // .ambient respects the Silent switch; mixWithOthers won't stop user music
        try? session.setCategory(.ambient, options: [.mixWithOthers])
        try? session.setActive(true)
    }
    
    func playSound(sound: String, type: String, loop: Bool = false) {
        guard isOn && !stopPlay else { return }
        if let path = Bundle.main.path(forResource: sound, ofType: type) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                audioPlayer?.numberOfLoops = loop ? .max : 0
                audioPlayer?.volume = type == "mp3" ? 0.3 : 1
                audioPlayer?.play()
            } catch { print("ERROR") }
        }
    }
    
    func stop() {
        audioPlayer?.pause()
        audioPlayer = nil
    }
    
    func stopAudio(_ value: Bool) { stopPlay = value }
    
    // MARK: Background handling
    func pauseForBackground() {
        guard let audioPlayer, audioPlayer.isPlaying else { return }
        resumeOnForeground = true
        audioPlayer.pause()
    }
    
    func resumeIfNeeded() {
        if resumeOnForeground {
            audioPlayer?.play()
            resumeOnForeground = false
        }
    }
    
    // MARK: AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        resumeOnForeground = false
    }
}

struct AutoPauseAudioModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var audio: AudioPlayer
    
    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .inactive, .background:
                    audio.pauseForBackground()
                case .active:
                    audio.resumeIfNeeded()
                default:
                    break
                }
            }
    }
}

extension View {
    /// Attach this once (e.g., on your root view) to auto-pause/resume audio on background/foreground.
    func autoPauseAudio() -> some View { modifier(AutoPauseAudioModifier()) }
}
