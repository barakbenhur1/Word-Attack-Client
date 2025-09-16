//
//  LoginViewModel.swift
//  Word Guess
//
//  Created by Barak Ben Hur on 13/10/2024.
//

import SwiftUI

@Observable
class LoginViewModel: ObservableObject {
    private let network: Network
    
    required init() {
        network = Network(root: .login)
    }
    
    func login(email: String, name: String, gender: String) async -> Bool {
        guard let language = Locale.current.identifier.components(separatedBy: "_").first else { return false }
        let value: EmptyModel? = await network.send(route: .root,
                                                    parameters: ["email": email,
                                                                 "name": name,
                                                                 "gender": gender,
                                                                 "language": language])
        return value != nil
    }
    
    func gender(email: String) async -> String {
        let value: GenderData? = await network.send(route: .gender,
                                                    parameters: ["email": email])
        return value?.gender ?? "male"
    }
    
    @discardableResult
    func changeLanguage(email: String) async -> Bool {
        guard let language = Locale.current.identifier.components(separatedBy: "_").first else { return false }
        let value: EmptyModel? = await network.send(route: .changeLanguage,
                                                    parameters: ["email": email,
                                                                 "language": language])
        return value != nil
    }
}
