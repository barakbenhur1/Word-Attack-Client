//
//  LoginView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import SwiftUI

struct LoginView<VM: LoginViewModel>: View {
    @EnvironmentObject private var loginHandeler: LoginHandeler
    
    @State private var loading = false
    
    private let auth = Authentication()
    private let loginVm = VM()
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.red,
                                    .yellow,
                                    .green,
                                    .blue],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .blur(radius: 4)
            .opacity(0.1)
            .ignoresSafeArea()
            
            VStack {
                AppTitle()
                    .padding(.bottom, 40)
                googleSignInButton
                    .padding(.bottom, 160)
            }
            .padding(.horizontal, 40)
            .loading(show: loading)
        }
    }
    
    @ViewBuilder fileprivate var googleSignInButton: some View {
        GoogleLoginButton {
            hideKeyboard()
            loading = true
            Task {
                auth.googleAuth(complition: { model in
                    Task {
                        let name = "\(model.givenName) \(model.lastName)"
                        let email = model.email
                        let gender = model.gender
                        guard await loginVm.login(email: email,
                                                  name: name,
                                                  gender: gender)  else { return loading = false }
                        loading = false
                        loginHandeler.model = model
                    }
                }, error: { error in
                    loading = false
                    print(error)
                })
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
            LinearGradient(colors: [.white.opacity(0.4), .gray.opacity(0.1)],
                           startPoint: .topTrailing,
                           endPoint: .bottomLeading)
            .blur(radius: 4)
            
            VStack(spacing: 30) {
                VStack(spacing: 8) {
                    Image("google")
                        .resizable()
                        .frame(width: 120,
                               height: 120)
                        .shadow(radius: 4)
                    
                    Text("Sign in with Google")
                        .font(.largeTitle)
                }
                
                Button(action: { didTap() }) {
                    Text("Sign in")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .background {
                    AngularGradient(colors: [.init(hex: "#4285F4"),
                                             .init(hex: "#34A853"),
                                             .init(hex: "#FBBC04"),
                                             .init(hex: "#EA4335")],
                                    center: .topTrailing,
                                    startAngle: .degrees(40),
                                    endAngle: .degrees(290))
                    .blur(radius: 4)
                }
                .frame(width: 280)
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(.black.opacity(0.6), lineWidth: 0.1)
                }
                .padding(.bottom, 30)
                .padding(.horizontal, 30)
                .shadow(color: .black.opacity(0.6),
                        radius: 4)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 60))
        .shadow(radius: 4)
        .frame(height: 360)
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
