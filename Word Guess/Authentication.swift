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
}

class Authentication {
    private func checkStatus() -> GoogleAuthModel? {
        if GIDSignIn.sharedInstance.currentUser != nil {
            guard let user =  GIDSignIn.sharedInstance.currentUser else { return nil }
            var google = GoogleAuthModel()
            let givenName = user.profile?.givenName
            let lastName = user.profile?.familyName
            google.email = user.profile?.email ?? ""
            google.givenName = givenName ?? ""
            google.lastName = lastName ?? ""
            return google
        }
        return nil
    }
    
    func googleAuth(complition: @escaping (GoogleAuthModel) -> (), error: @escaping (String) -> ())  {
        logout()
        // google sign in
        guard let clientID = FirebaseApp.app()?.options.clientID else { return error("no client id") }
        
        // Create Google Sign In configuration object.
        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config
        
        let queue = DispatchQueue.main
        
        queue.async {
            //get rootView
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            guard let rootViewController = scene?.windows.first?.rootViewController
            else { fatalError("There is no root view controller!") }
            
            //google sign in authentication response
            GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { [weak self] result, err in
                guard err == nil else { return error(err!.localizedDescription) }
                guard let self else { return error("faild") }
                guard let user = result?.user else { return error("faild to get user") }
                guard let idToken = user.idToken?.tokenString else { return error("faild to get token") }
                
                //Firebase auth
                let credential = GoogleAuthProvider.credential(withIDToken: idToken,
                                                               accessToken: user.accessToken.tokenString)
                Auth.auth().signIn(with: credential)
                guard let model = checkStatus() else { return error("faild to get result") }
                complition(model)
            }
        }
    }
    
//    func facebookAuth(complition: @escaping (FacebookAuthModel) -> (), error: @escaping (String) -> ()) {
//        logout()
//        let fbLoginManager = LoginManager()
//        //get rootView
//        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
//        guard let rootViewController = scene?.windows.first?.rootViewController
//        else { fatalError("There is no root view controller!") }
//        
//        fbLoginManager.logIn(permissions:  ["public_profile", "email"], from: rootViewController) { result, err in
//            guard err == nil else { return error(err!.localizedDescription) }
//            guard let tokenString = result?.token?.tokenString else { return error("no token") }
//            
//            let credential = FacebookAuthProvider.credential(withAccessToken: tokenString)
//            
//            Auth.auth().signIn(with: credential) { authResult, err in
//                guard err == nil else { return error(err!.localizedDescription) }
//                guard let id = authResult?.user.uid.encrypt() else { return error("no id") }
//                complition(FacebookAuthModel(id: id,
//                                             birthday: "",
//                                             gender: "",
//                                             email: authResult?.user.email ?? ""))
//            }
//        }
//    }
//    
//    func phoneAuth(phone: String, auth: @escaping (_ verificationID: String) -> (), error: @escaping (String?) -> ()) {
//        PhoneAuthProvider.provider()
//            .verifyPhoneNumber(phone.internationalPhone(),
//                               uiDelegate: nil) { verificationID, err in
//                guard err == nil else { return error(err?.localizedDescription) }
//                guard let verificationID else { return error("no verificationID") }
//                auth(verificationID)
//            }
//    }
//    
//    func phoneVerify(verificationID: String, verificationCode: String, phoneAuthModel: @escaping (PhoneAuthModel) -> (), error: @escaping (String?) -> ()) {
//        logout()
//        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID,
//                                                                 verificationCode: verificationCode)
//        Auth.auth().signIn(with: credential) { result, err in
//            guard err == nil else { return error("קוד שגוי") }
//            guard let result else { return error("no result") }
//            guard let id = result.user.uid.encrypt() else { return }
//            phoneAuthModel(.init(id: id,
//                                 name: result.user.displayName ?? "",
//                                 email: result.user.email ?? ""))
//        }
//    }
    
    func logout() {
        try? Auth.auth().signOut()
        GIDSignIn.sharedInstance.signOut()
    }
}


extension String: @retroactive Error {}
