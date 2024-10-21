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
    private let loginVm = VM()
    
    var body: some View {
        VStack {
            AppTitle()
                .padding(.bottom, 80)
            googleSignInButton
                .padding(.bottom, 240)
        }
        .padding(.horizontal, 40)
    }
    
    @ViewBuilder fileprivate var googleSignInButton: some View {
        let button = Button(action: {
            hideKeyboard()
            Task {
                auth.googleAuth(complition: { model in
                    Task {
                        let name = "\(model.givenName) \(model.lastName)"
                        let email = model.email
                        guard await loginVm.login(email: email,
                                                  name: name)  else { return }
                        loginHandeler.model = model
                    }
                }, error: { error in print(error) })
            }
        }, label: {
            HStack {
                Spacer()
                Image("google")
                    .resizable()
                    .frame(width: 40)
                    .frame( height: 40)
                
                Text("Google Login")
                    .font(.largeTitle)
                    .padding(.trailing, 195)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity)
            .padding(.all, 30)
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
