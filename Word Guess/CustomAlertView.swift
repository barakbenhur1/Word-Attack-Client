//
//  CustomAlertView.swift
//  CustomAlert
//
//  Created by Marwa Abou Niaaj on 25/01/2024.
//

import SwiftUI

enum AlertType {
    case success, fail
}

struct CustomAlertView<T: Any, M: View>: View {

    @Namespace private var namespace

    private let type: AlertType
    @Binding private var isPresented: Bool
    @State private var titleKey: LocalizedStringKey
    @State private var actionTextKey: LocalizedStringKey
    @State private var cancelButtonTextKey: LocalizedStringKey?

    private var data: T?
    private var actionWithValue: ((T) -> ())?
    private var messageWithValue: ((T?) -> M)?

    private var action: (() -> ())?
    private var message: (() -> M)?

    // Animation
    @State private var isAnimating = false
    private let animationDuration = 0.3

    init(
        type: AlertType,
        _ titleKey: LocalizedStringKey,
        _ isPresented: Binding<Bool>,
        returnedValue data: T?,
        actionTextKey: LocalizedStringKey,
        cancelButtonTextKey: LocalizedStringKey?,
        action: @escaping (T) -> (),
        @ViewBuilder message: @escaping (T?) -> M
    ) {
        _titleKey = State(wrappedValue: titleKey)
        _actionTextKey = State(wrappedValue: actionTextKey)
        _cancelButtonTextKey = State(wrappedValue: cancelButtonTextKey)
        _isPresented = isPresented

        self.type = type
        self.data = data
        self.action = nil
        self.message = nil
        self.actionWithValue = action
        self.messageWithValue = message
    }

    var body: some View {
        ZStack {
            Color.gray
                .ignoresSafeArea()
                .opacity(isPresented ? 0.6 : 0)
                .zIndex(1)

            if isAnimating {
                VStack {
                    VStack {
                        /// Title
                        Text(titleKey)
                            .font(.title2).bold()
                            .foregroundStyle(foregroundStyle)
                            .padding(8)
                        
                       icon

                        /// Message
                        Group {
                            if let messageWithValue {
                                if let data {
                                    messageWithValue(data)
                                }
                                else {
                                    messageWithValue(nil)
                                }
                            } else if let message {
                                message()
                            }
                        }
                        .multilineTextAlignment(.center)
                        
                        /// Buttons
                        HStack {
                            if let cancelButtonTextKey {
                                cancelButton(cancelButtonTextKey: cancelButtonTextKey)
                            }
                            doneButton
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .padding()
                        .frame(maxWidth: .infinity)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(.background)
                    .cornerRadius(35)
                }
                .padding()
                .transition(.scale)
                .zIndex(2)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            show()
        }
    }
    
    // MARK: Buttons
    func cancelButton(cancelButtonTextKey: LocalizedStringKey) -> some View {
        Button {
            dismiss()
        } label: {
            Text(cancelButtonTextKey)
                .font(.headline)
                .foregroundStyle(foregroundStyle)
                .padding()
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .background(Material.regular)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 30))
        }
    }

    var doneButton: some View {
        Button {
            dismiss()

            if let data, let actionWithValue {
                actionWithValue(data)
            } else if let action {
                action()
            }
        } label: {
            Text(actionTextKey)
                .font(.headline).bold()
                .foregroundStyle(.white)
                .padding()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .background(backgroundStyle)
                .clipShape(RoundedRectangle(cornerRadius: 30))
        }
    }

    func dismiss() {
        if #available(iOS 17.0, *) {
            withAnimation(.easeInOut(duration: animationDuration)) {
                isAnimating = false
            } completion: {
                isPresented = false
            }
        } else {
            withAnimation(.easeInOut(duration: animationDuration)) {
                isAnimating = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                isPresented = false
            }
        }
    }

    func show() {
        withAnimation(.easeInOut(duration: animationDuration)) {
            isAnimating = true
        }
    }
    
    @ViewBuilder private var icon: some View {
        switch type {
        case .success:
            GifImageView("successGif")
                .frame(height: 100)
                .frame(width: 100)
                .padding(.top, 10)
                .padding(.bottom, 10)
        case .fail:
            GifImageView("failGif")
                .frame(height: 100)
                .frame(width: 100)
                .padding(.top, 10)
                .padding(.bottom, 10)
        }
    }
    
    private var foregroundStyle: Color {
        switch type {
        case .success:
            return Color.blue
        case .fail:
            return Color.red
        }
    }
    
    private var backgroundStyle: Color {
        switch type {
        case .success:
            return Color.blue
        case .fail:
            return Color.red
        }
    }
}

// MARK: - Overload
extension CustomAlertView where T == Never {

    init(
        type: AlertType,
        _ titleKey: LocalizedStringKey,
        _ isPresented: Binding<Bool>,
        actionTextKey: LocalizedStringKey,
        cancelButtonTextKey: LocalizedStringKey?,
        action: (() -> ())?,
        @ViewBuilder message: @escaping () -> M
    ) where T == Never {
        _titleKey = State(wrappedValue: titleKey)
        _actionTextKey = State(wrappedValue: actionTextKey)
        _cancelButtonTextKey = State(wrappedValue: cancelButtonTextKey)
        
        _isPresented = isPresented

        self.type = type
        self.data = nil
        self.action = action
        self.message = message
        self.actionWithValue = nil
        self.messageWithValue = nil
    }
}
