//
//  ChatAttachment.swift
//  Spots
//
//  Created by Pablo Jimenez on 29/9/25.
//


import Foundation

struct ChatAttachment: Identifiable, Codable, Equatable {
    var id: String = UUID().uuidString

    /// URL público (Firebase Storage).
    var url: String

    /// Nombre de archivo visible.
    var name: String

    /// MIME detectado (p.ej. image/jpeg).
    var mime: String

    /// Tipo de adjunto (image, video, file).
    var kind: AttachmentKind

    /// Tamaño en bytes.
    var size: Int64

    /// Metadatos opcionales
    var width: Int?
    var height: Int?
    var duration: Double?   // segundos
    var thumbnailURL: String?

    init(url: String,
         name: String,
         mime: String,
         size: Int64,
         width: Int? = nil,
         height: Int? = nil,
         duration: Double? = nil,
         thumbnailURL: String? = nil) {
        self.url = url
        self.name = name
        self.mime = mime
        self.kind = MIME.kind(for: mime)
        self.size = size
        self.width = width
        self.height = height
        self.duration = duration
        self.thumbnailURL = thumbnailURL
    }
}
