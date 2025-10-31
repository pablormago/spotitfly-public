//
//  GrowingTextView.swift
//  Spots
//

import SwiftUI
import UIKit

struct GrowingTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    var availableWidth: CGFloat
    var placeholder: String
    var onSend: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.isScrollEnabled = false
        tv.backgroundColor = UIColor.systemGray6
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.layer.cornerRadius = 8
        tv.layer.borderWidth = 1
        tv.layer.borderColor = UIColor.gray.withAlphaComponent(0.8).cgColor
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        tv.delegate = context.coordinator

        // Placeholder inicial
        tv.text = placeholder
        tv.textColor = UIColor.gray

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if text.isEmpty {
            if uiView.text != placeholder {
                uiView.text = placeholder
                uiView.textColor = UIColor.gray
            }
        } else {
            if uiView.text == placeholder {
                uiView.text = ""
                uiView.textColor = UIColor.label
            }
            if uiView.text != text {
                uiView.text = text
                uiView.textColor = UIColor.label
            }
        }

        // Ajustar altura dinámicamente
        let newSize = uiView.sizeThatFits(
            CGSize(width: availableWidth, height: .greatestFiniteMagnitude)
        )
        if dynamicHeight != newSize.height {
            DispatchQueue.main.async {
                self.dynamicHeight = newSize.height
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextView

        init(_ parent: GrowingTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            if textView.textColor == UIColor.gray, textView.text == parent.placeholder {
                parent.text = ""
            } else {
                parent.text = textView.text
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.textColor == UIColor.gray, textView.text == parent.placeholder {
                textView.text = ""
                textView.textColor = UIColor.label
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = UIColor.gray
            }
        }

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            if text == "\n" { // enter
                if let onSend = parent.onSend {
                    onSend()
                    return false
                }
            }
            return true
        }
    }
}
