//
//  AirspaceOracleHUD.swift
//  Spots
//
//  Created by Pablo Jimenez on 16/10/25.
//


//
//  AirspaceOracleHUD.swift
//  Spots
//

import SwiftUI

#if DEBUG
struct AirspaceOracleHUD: View {
    @ObservedObject private var oracle = AirspaceOracle.shared

    var body: some View {
        Group {
            if FeatureFlags.oracleEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text("🔮 Oráculo").font(.caption).bold()
                    Text("session: \(oracle.sessionId.prefix(8))").font(.caption2).foregroundColor(.secondary)
                    Text("tile: \(oracle.lastTileKey)").font(.caption2)
                    Text(String(format: "overscan: %.2f", oracle.lastOverscan)).font(.caption2)
                    Text("pub: \(oracle.lastPublished)").font(.caption2)
                    Text("vp: \(oracle.lastViewportExpected)").font(.caption2)   // 🆕
                    Text("painted: \(oracle.lastPainted)").font(.caption2)
                }
                .padding(8)
                .background(.ultraThinMaterial)
                .cornerRadius(10)
                .shadow(radius: 2)
            }
        }
        .allowsHitTesting(false)
    }
}



#endif
