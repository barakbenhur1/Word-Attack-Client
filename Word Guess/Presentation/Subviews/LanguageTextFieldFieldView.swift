//
//  LanguageTextField.swift
//  WordZap
//
//  Created by Barak Ben Hur on 17/10/2024.
//

import Foundation
import UIKit
import SwiftUI

class LanguageTextField: UITextField {
    var language: String? {
        didSet {
            if self.isFirstResponder{
                self.resignFirstResponder();
                self.becomeFirstResponder();
            }
        }
    }
    
    override var textInputMode: UITextInputMode? {
        if let language = self.language {
            for inputMode in UITextInputMode.activeInputModes {
                if inputMode.primaryLanguage == language.replacingOccurrences(of: "_", with: "-") {
                    return inputMode
                }
            }
        }
        return super.textInputMode
    }
    
}

struct LanguageTextFieldFieldView: UIViewRepresentable {
    let placeHolder: String
    private let language: String = Locale.current.identifier
    private let dataSource = LanguageTextFieldFieldDataStore()
    @Binding var text: String
    let didType: (String) -> ()
    
    func makeUIView(context: Context) -> UITextField{
        let textField = LanguageTextField(frame: .zero)
        textField.placeholder = self.placeHolder
        textField.textAlignment = .center
        textField.text = self.text
        textField.delegate = dataSource
        textField.language = self.language
        
        dataSource.didType = { value in
            text = value
            didType(text)
        }
        
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        print(uiView.text ?? "")
    }
}

class LanguageTextFieldFieldDataStore: NSObject, UITextFieldDelegate {
    var didType: ((String) -> ())?
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        didType?((textField.text ?? "") + string)
        return true
    }
}
