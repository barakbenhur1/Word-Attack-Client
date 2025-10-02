//
//  LoginView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import AuthenticationServices
import SwiftUI

struct LoginView<VM: LoginViewModel>: View {
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @State private var loading = false
    
    private let auth = Authentication()
    private let loginVm = VM()
    private var googleStyle: ElevatedButtonStyle { ElevatedButtonStyle(palette: .googleLogin) }
    private var appleStyle: ElevatedButtonStyle { ElevatedButtonStyle(palette: .appleLogin) }
    
    @ViewBuilder private var appleLabel: some View { ElevatedButtonLabel(LocalizedStringKey("Continue with Apple"), systemImage: "apple.logo") }
    @ViewBuilder private var googleLabel: some View { ElevatedButtonLabel(LocalizedStringKey("Continue with Google"), image: "google") }
    
    var body: some View {
        GeometryReader { _ in
            GameViewBackguard().ignoresSafeArea()
            
            VStack(spacing: 40) {
                Spacer()
                AppTitle(size: 44)
                
                VStack(spacing: 16) {
                    Button(action: appleAction, label: { appleLabel })
                        .buttonStyle(appleStyle)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .frame(maxWidth: .infinity)
                    
                    Button(action: googleAction, label: { googleLabel })
                        .buttonStyle(googleStyle)
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                        .frame(maxWidth: .infinity)
                }
                
                Spacer()
            }
            .padding(.horizontal, 40)
            .ignoresSafeArea(.keyboard)
            .loading(show: loading)
        }
    }
    
    private func googleAction() {
        UIApplication.shared.hideKeyboard()
        loading = true
        Task(priority: .userInitiated) {
            auth.googleAuth(
                complition: { model in
                    Task {
                        let name = "\(model.givenName) \(model.lastName)"
                        let ok = await loginVm.login(email: model.email, name: name, gender: model.gender)
                        loading = false
                        if ok { loginHandeler.model = model }
                    }
                },
                error: { err in loading = false; print(err) }
            )
        }
    }
    
    private func appleAction() {
        UIApplication.shared.hideKeyboard()
        loading = true
        Task(priority: .userInitiated) {
            auth.appleAuth(
                complition: { model in
                    Task {
                        let name = "\(model.givenName) \(model.lastName)".trimmingCharacters(in: .whitespaces)
                        let ok = await loginVm.login(email: model.email, name: name, gender: model.gender)
                        loading = false
                        if ok {
                            await MainActor.run {
                                loginHandeler.model = model
                            }
                        }
                    }
                },
                error: { err in loading = false; print(err) }
            )
        }
    }
}

extension UIApplication {
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
