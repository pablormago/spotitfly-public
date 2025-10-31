//
//  LinkTextView.swift
//  Spots
//

import SwiftUI
import UIKit

struct LinkTextView: UIViewRepresentable {
    let text: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label
    var maxWidth: CGFloat? = nil

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.isEditable = false
        tv.isSelectable = true
        tv.isScrollEnabled = false   // 👈 muy importante para que haga wrap
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.textContainer.lineBreakMode = .byWordWrapping
        tv.dataDetectorTypes = [.link, .phoneNumber]
        tv.adjustsFontForContentSizeCategory = true
        tv.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue
        ]
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        let attr = NSMutableAttributedString(string: text)
        attr.addAttributes([
            .font: font,
            .foregroundColor: textColor
        ], range: NSRange(location: 0, length: attr.length))
        uiView.attributedText = attr

        if let maxWidth {
            uiView.textContainer.size = CGSize(width: maxWidth, height: .greatestFiniteMagnitude)
        }
    }
}
