//
//  Authentication.swift
//  TaxiShare_MVP
//
//  Created by Barak Ben Hur on 08/08/2024.
//

import Foundation
import FirebaseAuth
import Firebase
import FacebookLogin
import GoogleSignIn

struct GoogleAuthModel: Codable {
    var givenName: String = ""
    var lastName: String = ""
    var email: String = ""
    var gender: String = ""
}

class Authentication {
    private let genderScope = "https://www.googleapis.com/auth/user.gender.read"
    
    private func checkStatus(gender: String?) async -> GoogleAuthModel? {
        if GIDSignIn.sharedInstance.currentUser != nil {
            guard let user =  GIDSignIn.sharedInstance.currentUser else { return nil }
            var google = GoogleAuthModel()
            let givenName = user.profile?.givenName
            let lastName = user.profile?.familyName
            google.email = user.profile?.email ?? ""
            google.givenName = givenName ?? ""
            google.lastName = lastName ?? ""
            google.gender = gender ?? "male"
            
            return google
        }
        return nil
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
    
    func googleAuth(complition: @escaping (GoogleAuthModel) -> (), error: @escaping (String) -> ())  {
        logout()
        // google sign in
        guard let clientID = FirebaseApp.app()?.options.clientID else { return error("no client id") }
        
        // Create Google Sign In configuration object.
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        //get rootView
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        guard let rootViewController = scene?.windows.first?.rootViewController
        else { fatalError("There is no root view controller!") }
        
        //google sign in authentication response
        signInAndFetchGender(rootViewController: rootViewController) { result in
            Task.detached { [weak self] in
                guard let self else { return error("faild init class") }
                switch result {
                case .failure(let e): error(e.localizedDescription)
                case .success(let gender):
                    guard let model = await checkStatus(gender: gender) else { return error("faild to get result") }
                    await MainActor.run { complition(model) }
                }
            }
        }
    }
    
    // MARK: - Sign in + Firebase + Gender
    
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
            
            // ---- Firebase sign-in (optional, as you have it) ----
            let accessTokenStr = user.accessToken.tokenString
            guard let idToken = user.idToken?.tokenString
            else { return completion(.failure(NSError(domain: "Auth", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing tokens"]))) }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessTokenStr)
            Auth.auth().signIn(with: credential) { [weak self] _, firebaseErr in
                guard let self else { return }
                if let firebaseErr { return completion(.failure(firebaseErr)) }
                
                // ---- Ensure scope + refresh token, then call People API ----
                ensureGenderScopeAndFreshToken(for: user, presenting: rootViewController) { [weak self]  result in
                    switch result {
                    case .failure(let e): completion(.failure(e))
                    case .success(let freshAccessToken):
                        guard let self else { return }
                        fetchGender(accessToken: freshAccessToken,
                                    completion: completion)
                    }
                }
            }
        }
    }
    
    /// If gender scope wasn’t granted, asks for it; always returns a fresh access token.
    private func ensureGenderScopeAndFreshToken(for user: GIDGoogleUser,presenting: UIViewController, completion: @escaping (Result<String, Error>) -> Void) {
        let hasScope = (user.grantedScopes ?? []).contains(genderScope)
        
        let proceed: (GIDGoogleUser) -> Void = { u in
            // Refresh tokens if needed, then return access token string
            u.refreshTokensIfNeeded { newUser, err in
                if let err { return completion(.failure(err)) }
                let current = newUser ?? u
                let token = current.accessToken.tokenString
                completion(.success(token))
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
    
    func logout() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }
}


extension String: @retroactive Error {}

enum PeopleAPI {
    struct Gender: Decodable {
        let formattedValue: String?
        let value: String?
    }
    struct Response: Decodable {
        let genders: [Gender]?
    }

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

// MARK: - Models

private extension PeopleAPI.Gender {
    var formatted: String {
        // Prefer formattedValue, fallback to raw value
        (formattedValue ?? value ?? "").capitalized
    }
}
