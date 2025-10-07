//
//  LoginViewModel.swift
//  WordZap
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
    
    func login(uniqe: String, name: String, gender: String) async -> Bool {
        guard let language = Locale.current.identifier.components(separatedBy: "_").first else { return false }
        let value: EmptyModel? = await network.send(route: .root,
                                                    parameters: ["uniqe": uniqe,
                                                                 "name": name,
                                                                 "gender": gender,
                                                                 "language": language])
        return value != nil
    }
    
    func isLoggedin(uniqe: String) async -> Bool {
        let value: EmptyModel? = await network.send(route: .isLoggedin,
                                                    parameters: ["uniqe": uniqe])
        return value != nil
    }
    
    func gender(uniqe: String) async -> String {
        let value: GenderData? = await network.send(route: .gender,
                                                    parameters: ["uniqe": uniqe])
        return value?.gender ?? "male"
    }
    
    @discardableResult
    func changeLanguage(uniqe: String) async -> Bool {
        guard let language = Locale.current.identifier.components(separatedBy: "_").first else { return false }
        let value: EmptyModel? = await network.send(route: .changeLanguage,
                                                    parameters: ["uniqe": uniqe,
                                                                 "language": language])
        return value != nil
    }
}
