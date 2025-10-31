//
//  UserLocationDot.swift
//  Spots
//
//  Created by Pablo Jimenez on 21/9/25.
//


//
//  UserLocationDot.swift
//  Spots
//
//  Created by Pablo Jimenez on 24/9/25.
//

import SwiftUI

struct UserLocationDot: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            // Círculo pulsante (halo exterior)
            Circle()
                .fill(Color.blue.opacity(0.25))
                .frame(width: 49, height: 49)
                .scaleEffect(animate ? 1.4 : 0.8)
                .opacity(animate ? 0.0 : 1.0)
                .animation(
                    Animation.easeOut(duration: 1.5)
                        .repeatForever(autoreverses: false),
                    value: animate
                )

            // Círculo central
            Circle()
                .fill(Color.blue)
                .frame(width: 25, height: 25)
                .overlay(
                    Circle().stroke(Color.white, lineWidth: 3)
                )
        }
        .onAppear { animate = true }
    }
}
