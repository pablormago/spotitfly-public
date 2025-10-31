//
//  AutoGrowingTextEditor.swift
//  Spots
//

import SwiftUI

struct AutoGrowingTextEditor: View {
    @Binding var text: String
    var placeholder: String = "Escribe un mensaje…"
    var minHeight: CGFloat = 36
    var maxHeight: CGFloat = 140
    var onSend: () -> Void

    @State private var measuredHeight: CGFloat = 36

    private var clampedHeight: CGFloat {
        min(max(measuredHeight, minHeight), maxHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Editor visible
            TextEditor(text: $text)
                .frame(height: clampedHeight)
                .padding(.horizontal, 0)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
                .autocorrectionDisabled(true)          // ✅ desactivar autocorrección
                .textInputAutocapitalization(.sentences)   // ✅ desactivar autocapitalización
                .onChange(of: text) { _ in
                    // Enter ahora solo añade salto de línea
                }

            // Placeholder (no intercepta toques)
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray.opacity(0.8))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .allowsHitTesting(false)   // ✅ no bloquea pegar ni foco
            }

            // Medidor invisible (mismo padding y fuente)
            Text(text.isEmpty ? " " : text + " ")
                .font(.body)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0)
                .background(
                    GeometryReader { gp in
                        Color.clear
                            .onAppear { measuredHeight = gp.size.height }
                            .onChange(of: text) { _ in measuredHeight = gp.size.height }
                    }
                )
        }
        // Estilo como tu TextField anterior
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(UIColor.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.8), lineWidth: 1)
        )
    }
}
