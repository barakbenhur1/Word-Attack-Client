//
//  ShareSheet.swift
//  WordZap
//
//  Created by Barak Ben Hur on 30/09/2025.
//

import SwiftUI

struct ShareSheet: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let itemSource: UIActivityItemSource
    var anchorRectInScreen: CGRect? = nil   // from .global
    
    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isShowing = false
        var parent: ShareSheet
        init(_ parent: ShareSheet) { self.parent = parent }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            // user swiped down or tapped outside
            Task { @MainActor in self.parent.isPresented = false }
        }
    }
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .clear
        return vc
    }
    
    func updateUIViewController(_ presentingVC: UIViewController, context: Context) {
        if isPresented && !context.coordinator.isShowing {
            let activity = UIActivityViewController(activityItems: [itemSource], applicationActivities: nil)
            
            // iPad popover anchor
            if let pop = activity.popoverPresentationController {
                pop.sourceView = presentingVC.view
                if let screenRect = anchorRectInScreen {
                    let rect = presentingVC.view.convert(screenRect, from: nil)
                    pop.sourceRect = rect
                    pop.permittedArrowDirections = [.up, .down]
                } else {
                    pop.sourceRect = CGRect(x: presentingVC.view.bounds.midX,
                                            y: presentingVC.view.bounds.midY,
                                            width: 1, height: 1)
                    pop.permittedArrowDirections = []
                }
            }
            
            activity.presentationController?.delegate = context.coordinator
            activity.completionWithItemsHandler = { _,_,_,_ in
                Task { @MainActor in
                    context.coordinator.isShowing = false
                    self.isPresented = false
                }
            }
            
            DispatchQueue.main.async {
                presentingVC.present(activity, animated: true)
                context.coordinator.isShowing = true
            }
        } else if !isPresented && context.coordinator.isShowing {
            presentingVC.dismiss(animated: true)
            context.coordinator.isShowing = false
        }
    }
}
