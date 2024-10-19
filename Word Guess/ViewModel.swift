//
//  VIewModel.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI
import Alamofire

enum WordLanguage: String {
    case en, he
}

@Observable
class ViewModel: ObservableObject {
    private let network: Network
    var word: WordData
    var isError: Bool
    var current: Int
    
    private let queue = DispatchQueue.main
    
    required init() {
        network = Network(root: "words")
        word = .emapty
        current = 0
        isError = false
    }
    
    func word(diffculty: DifficultyType, email: String) async {
        let value: WordData? = await network.send(route: "getWord",
                                                  parameters: ["diffculty": diffculty.rawValue,
                                                               "email": email])
        queue.async { [weak self] in
            guard let self else { return }
            guard let value else {
                return isError = true
            }
            word = value
        }
    }
    
    func addGuess(diffculty: DifficultyType, email: String, guess: String) async {
        let value: EmptyModel? = await network.send(route: "addGuess",
                                                    parameters: ["diffculty": diffculty.rawValue,
                                                                 "email": email,
                                                                 "guess": guess])
        queue.async { [weak self] in
            guard let self else { return }
            guard value != nil else {
                return isError = true
            }
        }
    }
    
    func score(diffculty: DifficultyType, email: String) async {
        let value: EmptyModel? = await network.send(route: "score",
                                                    parameters: ["diffculty": diffculty.rawValue,
                                                                 "email": email])
        queue.async { [weak self] in
            guard let self else { return }
            guard value != nil else {
                return isError = true
            }
        }
    }
}
