//
//  PermissionsExplainerView.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//


import SwiftUI
import PhotosUI
import AVFoundation
import CoreLocation
import UniformTypeIdentifiers
import UserNotifications


struct PermissionsExplainerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var requesting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permisos necesarios")
                .font(.title2.bold())

            GroupBox {
                PermRow(icon: "location", title: "Ubicación",
                        text: "Para mostrarte spots cercanos y calcular rutas.")
            }
            GroupBox {
                PermRow(icon: "camera", title: "Cámara y Fotos",
                        text: "Para enviar fotos y vídeos en los chats.")
            }
            GroupBox {
                PermRow(icon: "mic", title: "Micrófono",
                        text: "Para grabar vídeos con audio si decides adjuntarlos.")
            }
            GroupBox {
                PermRow(icon: "doc", title: "Archivos",
                        text: "Para adjuntar documentos en los chats.")
            }
            GroupBox {
                PermRow(icon: "bell", title: "Notificaciones",
                        text: "Para avisarte de respuestas en chats y actividad en tus spots.")
            }


            if let e = errorMessage {
                Text(e).font(.footnote).foregroundColor(.red)
            }

            Button {
                Task { await requestAll() }
            } label: {
                HStack {
                    if requesting { ProgressView().padding(.trailing, 6) }
                    Text("Continuar")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(requesting)

            Button("Ahora no") { dismiss() }
                .padding(.top, 4)
        }
        .padding()
        .presentationDetents([.medium, .large])
    }

    private func requestPhotos() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
    }

    private func requestCamera() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
    }

    private func requestMicrophone() async throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }

    private func requestLocation() async throws {
        await LocationPermissionHelper.shared.requestWhenInUse()
    }
    @MainActor
    private func registerForRemoteNotifications() {
        // Llamar siempre en MainActor
        UIApplication.shared.registerForRemoteNotifications()
    }

    private func requestNotifications() async throws {
        let center = UNUserNotificationCenter.current()
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run { registerForRemoteNotifications() }
            }
        case .denied:
            // No forzamos nada aquí; el botón “Continuar” no falla si está denegado
            break
        case .authorized, .provisional, .ephemeral:
            await MainActor.run { registerForRemoteNotifications() }
        @unknown default:
            break
        }
    }


    private func requestAllImpl() async {
        try? await requestLocation()
        try? await requestPhotos()
        try? await requestCamera()
        try? await requestMicrophone()
        try? await requestNotifications() 
    }

    private func requestAll() async {
        guard !requesting else { return }
        requesting = true
        errorMessage = nil
        defer { requesting = false }

        await requestAllImpl()
        await MainActor.run { dismiss() }
    }
}

private struct PermRow: View {
    let icon: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "\(icon).fill")
                .frame(width: 22)
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.bold())
                Text(text).font(.footnote).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
