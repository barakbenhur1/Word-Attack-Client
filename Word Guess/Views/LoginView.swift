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
    
    @ViewBuilder private var appleLabel: some View  { ElevatedButtonLabel(LocalizedStringKey("Continue with Apple"), systemImage: "apple.logo") }
    @ViewBuilder private var googleLabel: some View { ElevatedButtonLabel(LocalizedStringKey("Continue with Google"), image: "google") }
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [.red, .yellow, .green, .blue],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            .blur(radius: 4).opacity(0.1).ignoresSafeArea()
            
            VStack(spacing: 40) {
                AppTitle(size: 50)
                
                VStack(spacing: 16) {
                    Button(action: appleAction, label: { appleLabel })
                        .buttonStyle(appleStyle)
                        .shadow(radius: 4)
                        .frame(maxWidth: .infinity)   // 👈 expand width
//                        .frame(height: 60)
                    
                    Button(action: googleAction, label: { googleLabel })
                        .buttonStyle(googleStyle)
                        .shadow(radius: 4)
                        .frame(maxWidth: .infinity)   // 👈 expand width
//                        .frame(height: 60)
                }
            }
            .padding(.horizontal, 40)
            .loading(show: loading)
        }
        .ignoresSafeArea(.keyboard)
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
                        if ok { loginHandeler.model = model }
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
