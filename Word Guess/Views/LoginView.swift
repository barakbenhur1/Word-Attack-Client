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
    
    private var style: ElevatedButtonStyle { ElevatedButtonStyle(palette: .login) }
    
    @ViewBuilder private var label: some View { ElevatedButtonLabel(LocalizedStringKey("Login with google"), image: "google") }
    
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
                    .padding(.bottom, 60)
                googleSignInButton
                    .frame(height: 80)
            }
            .padding(.horizontal, 40)
            .loading(show: loading)
        }
    }
    
    @ViewBuilder private var googleSignInButton: some View {
        Button(action: action,
               label: { label })
            .buttonStyle(style)
            .shadow(radius: 4)
    }
    
    private func action() {
        UIApplication.shared.hideKeyboard()
        loading = true
        Task(priority: .userInitiated) {
            auth.googleAuth(
                complition: { model in
                    Task {
                        let name = "\(model.givenName) \(model.lastName)"
                        let email = model.email
                        let gender = model.gender
                        guard await loginVm.login(email: email,
                                                  name: name,
                                                  gender: gender) else { return loading = false }
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
