//
//  FeatureFlags.swift
//  Spots
//
//  Created by Pablo Jimenez on 29/9/25.
//


import Foundation

enum FeatureFlags {
    /// Activa/desactiva el envío de archivos en chats.
    static let fileSharingEnabled: Bool = false

    /// Tamaño máximo (MB) aceptado antes de subir.
    static let maxUploadMB: Double = 50.0

    /// Límite de píxeles largos para imágenes (resize manteniendo aspecto).
    static let imageMaxLongSide: Int = 2048

    /// Preset de export de vídeo (calidad razonable).
    static let videoExportPreset: String = "AVAssetExportPreset1280x720"
    
    // 🆕 DEBUG: Oráculo overlays
    static let oracleEnabled: Bool = true
    
    // Overscan solo para Infraestructura
        static let infraOverscanFactor: Double = 1.6   // prueba 1.6; si aún falta, sube a 2.0
        static let infraMinPadDeg: Double = 0.010      // mínimo ~1.1 km en lat; sube a 0.015 si hace falta
}
