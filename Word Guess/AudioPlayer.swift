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
    var isOn = true
    
    func playSound(sound: String, type: String, loop: Bool = false) {
        guard isOn else { return }
        if let path = Bundle.main.path(forResource: sound, ofType: type) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                audioPlayer?.numberOfLoops = loop ? .max : 0
                audioPlayer?.volume = type == "mp3" ? 0.5 : 1
                audioPlayer?.play()
            } catch {
                print("ERROR")
            }
        }
    }
    
    func stop() {
        audioPlayer?.pause()
        audioPlayer = nil
    }
}
