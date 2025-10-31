//
//  AppConfig.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//


//
//  AppConfig.swift
//  Spots
//

import Foundation

/// Configuración global simple para toggles de features.
/// Lo inyectas en tu @main y ya puedes usarlo con @EnvironmentObject.
final class AppConfig: ObservableObject {
    static let shared = AppConfig()

    /// Activa/desactiva la función de reportes.
    @Published var reportsEnabled: Bool = true
}
