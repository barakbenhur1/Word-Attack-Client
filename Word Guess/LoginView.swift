//
//  LoginView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI

struct LoginView<VM: LoginViewModel>: View {
    @EnvironmentObject private var loginHandeler: LoginHandeler
   
    private let auth = Authentication()
    private var loginVm = VM()
    
    var body: some View {
        VStack {
            Text("Word Guess")
                .font(.largeTitle)
                .padding(.bottom, 20)
            googleSignInButton
                .padding(.bottom, 140)
        }
        .padding(.horizontal, 40)
    }
    
    @ViewBuilder fileprivate var googleSignInButton: some View {
        let button = Button(action: {
            hideKeyboard()
            Task {
                auth.googleAuth(complition: { model in
                    Task {
                        guard await loginVm.login(email: model.email,
                                                  name: "\(model.givenName) \(model.lastName)")  else { return }
                        loginHandeler.model = model
                    }
                },
                                error: { error in print(error) })
            }
        }, label: {
            ZStack(alignment: .center) {
                Image("google")
                    .resizable()
                    .frame(width: 25,
                           height: 25)
                    .padding(.trailing, 195)
                
                Text("Google Login")
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            }
        })
            .buttonStyle(LoginButtonStyle())
            .font(.title2.weight(.medium))
            .foregroundStyle(.black)
        
        makeLoginButton(view: button)
    }
    
    @ViewBuilder private func makeLoginButton(view: some View) -> some View {
        view
            .clipShape(Capsule())
            .frame(height: 56)
    }
}

private struct LoginButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                configuration.isPressed ? .gray.opacity(0.8) :
                Color.clear
            }
            .contentShape(Capsule())
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .overlay(
                Capsule()
                    .stroke(Color.black,
                            lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil,
                                        from: nil,
                                        for: nil)
    }
    
    func showKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.becomeFirstResponder),
                                        to: nil,
                                        from: nil,
                                        for: nil)
    }
}
