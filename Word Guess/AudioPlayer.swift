//
//  AudioPlayer.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 20/10/2024.
//

import AVFoundation

class AudioPlayer: ObservableObject {
    private var audioPlayer: AVAudioPlayer?
    
    func playSound(sound: String, type: String, loop: Bool = false) {
        if let path = Bundle.main.path(forResource: sound, ofType: type) {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
                audioPlayer?.numberOfLoops = loop ? .max : 0
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
