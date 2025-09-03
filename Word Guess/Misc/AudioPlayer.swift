//
//  AudioPlayer.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 20/10/2024.
//

import AVFoundation

@Observable
class AudioPlayer: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    private var stopPlay = false
    
    var isOn = UserDefaults.standard.value(forKey: "sound") as? Bool ?? true { didSet { UserDefaults.standard.set(isOn, forKey: "sound") } }
    
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
}
