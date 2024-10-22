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
        ZStack {
            LinearGradient(colors: [.red, .yellow, .green, .blue],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .opacity(0.1)
            .ignoresSafeArea()
            VStack {
                AppTitle()
                    .padding(.bottom, 40)
                googleSignInButton
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 40)
        }
    }
    
    @ViewBuilder fileprivate var googleSignInButton: some View {
        GoogleLoginButton {
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
        }
    }
    
    @ViewBuilder private func makeLoginButton(view: some View) -> some View {
        view
            .clipShape(Capsule())
            .frame(height: 56)
    }
}

struct GoogleLoginButton: View {
    let didTap: () -> ()
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.white, .gray.opacity(0.1)],
                           startPoint: .topTrailing,
                           endPoint: .bottomLeading)
            
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Image("google")
                        .resizable()
                        .frame(width: 60, height: 60)
                        .foregroundColor(.blue)
                        .shadow(radius: 4)
                    
                    Text("Sign in with Google")
                        .font(.headline)
                }
                
                Button(action: { didTap() }) {
                    Text("Sign in with Google")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background {
                    LinearGradient(colors: [.green.opacity(0.4), .green],
                                   startPoint: .topTrailing,
                                   endPoint: .bottomLeading)
                }
                .frame(width: 280)
                .clipShape(Capsule())
                .shadow(radius: 4)
                .padding(.bottom, 14)
                .padding(.horizontal, 30)
            }
        }
        .shadow(radius: 4)
        .clipShape(RoundedRectangle(cornerRadius: 60))
        .frame(height: 320)
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
