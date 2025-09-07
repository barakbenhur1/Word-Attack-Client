//
//  Authentication.swift
//  TaxiShare_MVP
//
//  Created by Barak Ben Hur on 08/08/2024.
//

import Foundation
import AuthenticationServices
import CryptoKit
import FirebaseAuth
import Firebase
import FacebookLogin
import GoogleSignIn
import UIKit

// MARK: - Models

struct LoginAuthModel: Codable, Equatable {
    var givenName: String = ""
    var lastName:  String = ""
    var email:     String = ""
    var gender:    String = ""   // Apple does not provide gender
}

// MARK: - Authentication

final class Authentication: NSObject {
    
    // ---- Google People API scope (gender) ----
    private let genderScope = "https://www.googleapis.com/auth/user.gender.read"
    
    // ---- Apple state ----
    private var currentNonce: String?
    private var appleCompletion: ((Result<LoginAuthModel, Error>) -> Void)?
    
    // ---- Local cache key (for Apple display name) ----
    private func cachedNameKey(for uid: String) -> String { "apple.displayName.\(uid)" }
    
    // MARK: - GOOGLE
    
    private func checkStatus(gender: String?) async -> LoginAuthModel? {
        guard let user = GIDSignIn.sharedInstance.currentUser else { return nil }
        var google = LoginAuthModel()
        google.email     = user.profile?.email ?? ""
        google.givenName = user.profile?.givenName ?? ""
        google.lastName  = user.profile?.familyName ?? ""
        google.gender    = gender ?? "male"                // default neutral
        return google
    }
    
    /// Calls People API to read gender; returns nil if not set/visible.
    private func fetchGender(
        accessToken: String,
        completion: @escaping (Result<String?, Error>) -> Void
    ) {
        var comps = URLComponents(string: "https://people.googleapis.com/v1/people/me")!
        comps.queryItems = [URLQueryItem(name: "personFields", value: "genders")]
        
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { return completion(.failure(err)) }
            guard let http = resp as? HTTPURLResponse, let data = data else {
                return completion(.failure(URLError(.badServerResponse)))
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                return completion(.failure(NSError(domain: "PeopleAPI", code: http.statusCode,
                                                   userInfo: [NSLocalizedDescriptionKey: body])))
            }
            
            struct Gender: Decodable { let formattedValue: String?; let value: String? }
            struct Response: Decodable { let genders: [Gender]? }
            
            do {
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                let g = decoded.genders?.first
                completion(.success(g?.value)) // String?; nil if not set
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
    
    func googleAuth(complition: @escaping (LoginAuthModel) -> (), error: @escaping (String) -> ())  {
        logout()
        
        // Google Sign-In
        guard let clientID = FirebaseApp.app()?.options.clientID else { return error("no client id") }
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        // Root VC
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        guard let rootViewController = scene?.windows.first?.rootViewController
        else { return error("There is no root view controller!") }
        
        // Sign-in + gender
        signInAndFetchGender(rootViewController: rootViewController) { result in
            Task.detached { [weak self] in
                guard let self else { return error("failed init class") }
                switch result {
                case .failure(let e): error(e.localizedDescription)
                case .success(let gender):
                    guard let model = await checkStatus(gender: gender) else { return error("failed to get result") }
                    await MainActor.run { complition(model) }
                }
            }
        }
    }
    
    // MARK: - Sign in + Firebase + Gender (Google)
    
    func signInAndFetchGender(rootViewController: UIViewController, completion: @escaping (Result<String?, Error>) -> Void) {
        GIDSignIn.sharedInstance.signIn(
            withPresenting: rootViewController,
            hint: nil,
            additionalScopes: [genderScope]
        ) { result, err in
            if let err { return completion(.failure(err)) }
            guard let user = result?.user else {
                return completion(.failure(NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "No user"])))
            }
            
            let accessTokenStr = user.accessToken.tokenString
            guard let idToken = user.idToken?.tokenString else {
                return completion(.failure(NSError(domain: "Auth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing tokens"])))
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessTokenStr)
            Auth.auth().signIn(with: credential) { [weak self] _, firebaseErr in
                guard let self else { return }
                if let firebaseErr { return completion(.failure(firebaseErr)) }
                
                self.ensureGenderScopeAndFreshToken(for: user, presenting: rootViewController) { result in
                    switch result {
                    case .failure(let e): completion(.failure(e))
                    case .success(let freshAccessToken):
                        self.fetchGender(accessToken: freshAccessToken, completion: completion)
                    }
                }
            }
        }
    }
    
    /// If gender scope wasn’t granted, asks for it; always returns a fresh access token.
    private func ensureGenderScopeAndFreshToken(for user: GIDGoogleUser,
                                                presenting: UIViewController,
                                                completion: @escaping (Result<String, Error>) -> Void) {
        let hasScope = (user.grantedScopes ?? []).contains(genderScope)
        
        let proceed: (GIDGoogleUser) -> Void = { u in
            u.refreshTokensIfNeeded { newUser, err in
                if let err { return completion(.failure(err)) }
                completion(.success((newUser ?? u).accessToken.tokenString))
            }
        }
        
        if hasScope { proceed(user) }
        else {
            user.addScopes([genderScope], presenting: presenting) { _, err in
                if let err { return completion(.failure(err)) }
                proceed(user)
            }
        }
    }
    
    // MARK: - APPLE
    
    func appleAuth(complition: @escaping (LoginAuthModel) -> (), error: @escaping (String) -> ()) {
        logout()
        
        appleCompletion = { result in
            switch result {
            case .success(let model): complition(model)
            case .failure(let e):     error(e.localizedDescription)
            }
        }
        
        // Build request
        let nonce = randomNonceString()
        currentNonce = nonce
        
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    // MARK: - Common
    
    func logout() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }
}

// MARK: - Apple Delegates

private enum AuthError: Error {
    case noAppleCredential
    case missingNonce
    case missingIDToken
}

extension Authentication: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first ?? ASPresentationAnchor()
    }
    
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        // 1) Extract Apple credential
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            appleCompletion?(.failure(AuthError.noAppleCredential)); return
        }
        // 2) Nonce
        guard let nonce = currentNonce else {
            appleCompletion?(.failure(AuthError.missingNonce)); return
        }
        // 3) ID token -> string
        guard let idTokenData = credential.identityToken,
              let idTokenString = String(data: idTokenData, encoding: .utf8) else {
            appleCompletion?(.failure(AuthError.missingIDToken)); return
        }
        
        // 4) Firebase credential (non-deprecated)
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: credential.fullName
        )
        
        // 5) Sign in to Firebase
        Auth.auth().signIn(with: firebaseCredential) { authResult, err in
            if let err {
                self.appleCompletion?(.failure(err))
                return
            }
            
            let user = authResult?.user
            
            // Compose name from Apple (only on first auth) and persist to Firebase + local cache
            let given  = credential.fullName?.givenName ?? ""
            let family = credential.fullName?.familyName ?? ""
            let composedName = [given, family].joined(separator: " ").trimmingCharacters(in: .whitespaces)
            
            if !composedName.isEmpty, let user {
                let change = user.createProfileChangeRequest()
                change.displayName = composedName
                change.commitChanges { commitErr in
                    if let commitErr { print("⚠️ displayName commit error:", commitErr) }
                }
                // Cache locally so we can recover it next sessions even if Firebase didn't persist yet
                UserDefaults.standard.set(composedName, forKey: self.cachedNameKey(for: user.uid))
            }
            
            // Resolve best-known display name now
            let firebaseDisplay = user?.displayName ?? ""
            let cachedDisplay = user.map { UserDefaults.standard.string(forKey: self.cachedNameKey(for: $0.uid)) } ?? nil
            let bestDisplay = (!composedName.isEmpty ? composedName
                               : (!firebaseDisplay.isEmpty ? firebaseDisplay
                                  : (cachedDisplay ?? "")))
            
            // Split into given/last if possible
            let parts = bestDisplay.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            let resolvedGiven = !given.isEmpty ? given : (parts.first.map(String.init) ?? "")
            let resolvedLast  = !family.isEmpty ? family : (parts.count > 1 ? String(parts[1]) : "")
            
            // 6) Build your model
            var model = LoginAuthModel()
            let email = credential.email ?? user?.email ?? ""
            model.email     = email
            model.givenName = resolvedGiven.isEmpty ? String(email.split(separator: "@").first ?? "\(resolvedGiven)") : resolvedGiven
            model.lastName  = resolvedLast
            model.gender    = "male"                                       // Apple doesn't provide gender
            
            self.appleCompletion?(.success(model))
        }
    }
    
    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        appleCompletion?(.failure(error))
    }
}

// MARK: - Nonce helpers (Apple)

private extension Authentication {
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.map { String(format: "%02x", $0) }.joined()
    }
    
    func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            if status != errSecSuccess { fatalError("Unable to generate nonce.") }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }
}

// MARK: - Optional helpers / People API async flavor (unchanged)

extension String: @retroactive Error {}

enum PeopleAPI {
    struct Gender: Decodable { let formattedValue: String?; let value: String? }
    struct Response: Decodable { let genders: [Gender]? }
    
    static func getGender(accessToken: String) async throws -> Gender? {
        var comps = URLComponents(string: "https://people.googleapis.com/v1/people/me")!
        comps.queryItems = [URLQueryItem(name: "personFields", value: "genders")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "PeopleAPI", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body)"])
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return decoded.genders?.first
    }
}

private extension PeopleAPI.Gender {
    var formatted: String {
        (formattedValue ?? value ?? "").capitalized
    }
}
