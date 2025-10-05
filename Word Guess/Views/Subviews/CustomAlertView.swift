//
//  CustomAlertView.swift
//  CustomAlert
//
//  Created by Marwa Abou Niaaj on 25/01/2024.
//

//
//  CustomAlertView.swift
//  CustomAlert
//
//  Created by Marwa Abou Niaaj on 25/01/2024.
//  Updated for animated close-before-action + no corner flash.
//

import SwiftUI

enum AlertType { case success, fail, info }

struct CustomAlertView<T: Any, M: View>: View {
    
    // MARK: Inputs
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
    
    // MARK: Animation State
    @State private var showCard = false           // drives the card pop in/out
    @State private var isClosing = false          // prevents double-tap/jank during close
    private let overlayFade: Double = 0.28        // dimmer fade duration
    private let closeTime: Double = 0.32          // wait before unmounting (match removal)
    private let popAnim = Animation.interpolatingSpring(stiffness: 280,
                                                        damping: 22)
    
    // MARK: Init (T value version)
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
    
    // MARK: Body
    var body: some View {
        if isPresented {
            ZStack {
                // Dim background; fades with showCard for smooth in/out
                Color.black
                    .ignoresSafeArea()
                    .opacity(showCard ? 0.6 : 0)
                    .animation(.easeInOut(duration: overlayFade), value: showCard)
                
                // Card mounts/unmounts with pop transition while overlay stays
                if showCard {
                    alertCard
                        .transition(popTransition)
                        .animation(popAnim, value: showCard)
                        .zIndex(1)
                }
            }
            .transition(.opacity)              // whole overlay fades when mounting/unmounting
            .onAppear { withAnimation(popAnim) { showCard = true } }
        }
    }
    
    // MARK: Card
    private var alertCard: some View {
        VStack {
            VStack {
                // Title
                Text(titleKey)
                    .multilineTextAlignment(.center)
                    .font(.title2).bold()
                    .foregroundStyle(foregroundStyle)
                    .padding(8)
                
                icon
                
                // Message
                Group {
                    if let messageWithValue {
                        messageWithValue(data)
                    } else if let message {
                        message()
                    }
                }
                .multilineTextAlignment(.center)
                
                // Buttons
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
        }
        .padding()
        // IMPORTANT: shape drawn in background (no .cornerRadius) to avoid snapshot/mask artifacts
        .background(
            RoundedRectangle(cornerRadius: 35,
                             style: .continuous)
                .fill(Color(.systemBackground))
        )
        .shadow(radius: 10, y: 4)
        .compositingGroup()
        // Subtle polish
        .blur(radius: showCard ? 0 : 3)
        .scaleEffect(showCard ? 1 : 0.96)
    }
    
    // MARK: Buttons
    func cancelButton(cancelButtonTextKey: LocalizedStringKey) -> some View {
        Button { dismiss() }
        label: {
            Text(cancelButtonTextKey)
                .font(.headline)
                .foregroundStyle(foregroundStyle)
                .padding()
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
    
    var doneButton: some View {
        Button {
            // capture what to run AFTER close
            let actionToRun: (() -> Void)? = {
                if let data, let actionWithValue { actionWithValue(data) }
                else if let action { action() }
            }
            dismiss(then: actionToRun)
        } label: {
            Text(actionTextKey)
                .font(.headline).bold()
                .foregroundStyle(.white)
                .padding()
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .background(backgroundStyle,
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
    
    // MARK: Dismiss / Show
    func dismiss(then completion: (() -> Void)? = nil) {
        guard !isClosing else { return }
        isClosing = true
        
        // Play the pop removal on the card
        withAnimation(popAnim) { showCard = false }
        
        // After the card finishes, unmount overlay, then run action
        DispatchQueue.main.asyncAfter(deadline: .now() + closeTime) {
            isPresented = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.004) {
                isClosing = false
                completion?()
            }
        }
    }
    
    // MARK: Icon & Colors
    @ViewBuilder private var icon: some View {
        switch type {
        case .success: Text("🏆").padding(.vertical, 10)
        case .fail: Text("💔").padding(.vertical, 10)
        case .info: Text("ℹ️").padding(.vertical, 10)
        }
    }
    
    private var foregroundStyle: Color {
        switch type {
        case .success: return .blue
        case .fail: return .red
        case .info: return .yellow
        }
    }
    
    private var backgroundStyle: Color {
        switch type {
        case .success: return .blue
        case .fail: return .red
        case .info: return .yellow
        }
    }
    
    // MARK: Transition
    private var popTransition: AnyTransition {
        .asymmetric(insertion: .scale(scale: 0.92, anchor: .center).combined(with: .opacity),
                    removal: .scale(scale: 0.75, anchor: .center).combined(with: .opacity))
    }
}

// MARK: - Overload (no value)
extension CustomAlertView where T == Never {
    init(
        type: AlertType,
        _ titleKey: LocalizedStringKey,
        _ isPresented: Binding<Bool>,
        actionTextKey: LocalizedStringKey,
        cancelButtonTextKey: LocalizedStringKey?,
        action: (() -> ())?,
        @ViewBuilder message: @escaping () -> M
    ) {
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

extension View {
    /// Presents an alert with a message when a given condition is true, using a localized string key for a title.
    /// - Parameters:
    ///   - titleKey: The key for the localized string that describes the title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to present the alert.
    ///   - data: An optional binding of generic type T value, this data will populate the fields of an alert that will be displayed to the user.
    ///   - actionText: The key for the localized string that describes the text of alert's action button.
    ///   - action: The alert’s action given the currently available data.
    ///   - message: A ViewBuilder returning the message for the alert given the currently available data.
    func customAlert<M, T: Any>(
        _ titleKey: LocalizedStringKey,
        type: AlertType,
        isPresented: Binding<Bool>,
        returnedValue data: T?,
        actionText: LocalizedStringKey,
        cancelButtonText: LocalizedStringKey? = nil,
        action: @escaping (T) -> (),
        @ViewBuilder message: @escaping (T?) -> M
    ) -> some View where M: View {
        fullScreenCover(isPresented: isPresented) {
            CustomAlertView(
                type: type,
                titleKey,
                isPresented,
                returnedValue: data,
                actionTextKey: actionText,
                cancelButtonTextKey: cancelButtonText,
                action: action,
                message: message
            )
            .presentationBackground(.clear)
        }
        .transaction { transaction in
            if isPresented.wrappedValue {
                // disable the default FullScreenCover animation
                transaction.disablesAnimations = true
                // add custom animation for presenting and dismissing the FullScreenCover
                transaction.animation = .linear(duration: 0.1)
            }
        }
    }
    
    /// Presents an alert with a message when a given condition is true, using a localized string key for a title.
    /// - Parameters:
    ///   - titleKey: The key for the localized string that describes the title of the alert.
    ///   - isPresented: A binding to a Boolean value that determines whether to present the alert.
    ///   - actionText: The key for the localized string that describes the text of alert's action button.
    ///   - action: Returning the alert’s actions.
    ///   - message: A ViewBuilder returning the message for the alert.
    func customAlert<M>(
        _ titleKey: LocalizedStringKey,
        type: AlertType,
        isPresented: Binding<Bool>,
        actionText: LocalizedStringKey,
        cancelButtonText: LocalizedStringKey? = nil,
        action: (() -> ())? = nil,
        @ViewBuilder message: @escaping () -> M
    ) -> some View where M: View {
        fullScreenCover(isPresented: isPresented) {
            CustomAlertView(
                type: type,
                titleKey,
                isPresented,
                actionTextKey: actionText,
                cancelButtonTextKey: cancelButtonText,
                action: action,
                message: message
            )
            .presentationBackground(.clear)
        }
        .transaction { transaction in
            if isPresented.wrappedValue {
                transaction.disablesAnimations = true
                transaction.animation = .linear(duration: 0.1)
            }
        }
    }
}
