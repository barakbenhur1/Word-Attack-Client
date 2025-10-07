//
//  LoginView.swift
//  WordGuess
//
//  Created by Barak Ben Hur on 11/10/2024.
//

import AuthenticationServices
import SwiftUI

struct LoginView<VM: LoginViewModel>: View {
    @Environment(\.colorScheme) private var scheme
    
    @EnvironmentObject private var loginHandeler: LoginHandeler
    @State private var loading = false
    
    private let auth = Authentication()
    private let loginVm = VM()
    private var googleStyle: ElevatedButtonStyle { ElevatedButtonStyle(palette: .googleLogin) }
    private var googleDarkStyle: ElevatedButtonStyle { ElevatedButtonStyle(palette: .googleLoginDark) }
    private var appleStyle: ElevatedButtonStyle { ElevatedButtonStyle(palette: .appleLogin) }
    
    @ViewBuilder private var appleLabel: some View { ElevatedButtonLabel(LocalizedStringKey("Continue with Apple"), systemImage: "apple.logo") }
    @ViewBuilder private var googleLabel: some View { ElevatedButtonLabel(LocalizedStringKey("Continue with Google"), image: "google") }
    
    var body: some View {
        GeometryReader { _ in
            GameViewBackground().ignoresSafeArea()
            
            VStack {
                Spacer()
                GlassContainer(corner: 32) {
                    VStack(spacing: 26) {
                        AppTitle(size: 44)
                            .shadow(color: .black.opacity(0.12), radius: 4, x: 4, y: 4)
                            .shadow(color: .white.opacity(0.12), radius: 4, x: -4 ,y: -4)
                        VStack(spacing: 6) {
                            Button(action: appleAction, label: { appleLabel })
                                .buttonStyle(appleStyle)
                                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                                .frame(maxWidth: .infinity)
                            
                            Button(action: googleAction, label: { googleLabel })
                                .buttonStyle(scheme == .light ? googleStyle : googleDarkStyle)
                                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(14)
                }
                .frame(maxHeight: 360)
                Spacer()
            }
            .padding(.horizontal, 20)
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
                        let ok = await loginVm.login(uniqe: model.uniqe, name: name, gender: model.gender)
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
                        let ok = await loginVm.login(uniqe: model.uniqe, name: name, gender: model.gender)
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
