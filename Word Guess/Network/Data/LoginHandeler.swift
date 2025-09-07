//
//  LoginHandeler.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI

@Observable
class LoginHandeler: ObservableObject {
    var model: LoginAuthModel?
    var hasGender: Bool { model != nil && !model!.gender.isEmpty }
}
