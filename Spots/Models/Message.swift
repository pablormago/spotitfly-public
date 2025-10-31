//
//  Message.swift
//  Spots
//

import Foundation
import FirebaseFirestore

struct Message: Identifiable, Codable, Equatable {
    var id: String
    var chatId: String
    var senderId: String
    var text: String
    var createdAt: Date
    var readBy: [String]
    
    var mentions: [String]?    // UIDs mencionados (opcional)

    
    // 🧩 Respuesta (quote)
    var replyToMessageId: String?
    
    // ✏️ Edición
    var editedAt: Date?
    
    // 🆕 Soporte para archivos
    var type: String?            // "text", "file"
    var fileUrl: String?         // URL del archivo subido
    var fileName: String?        // Nombre del archivo
    var fileSize: Int64?         // Tamaño en bytes
    var fileType: String?        // MIME type
    var thumbnailUrl: String?    // 🆕 Miniatura remota opcional (para vídeos / imágenes)
    
    // Progreso local de subida (no se guarda en Firestore)
    var uploadProgress: Double?
    
    init(
        id: String,
        chatId: String,
        senderId: String,
        text: String,
        createdAt: Date,
        readBy: [String] = [],
        replyToMessageId: String? = nil,
        editedAt: Date? = nil,
        type: String? = nil,
        fileUrl: String? = nil,
        fileName: String? = nil,
        fileSize: Int64? = nil,
        fileType: String? = nil,
        thumbnailUrl: String? = nil,
        uploadProgress: Double? = nil
    ) {
        self.id = id
        self.chatId = chatId
        self.senderId = senderId
        self.text = text
        self.createdAt = createdAt
        self.readBy = readBy
        self.replyToMessageId = replyToMessageId
        self.editedAt = editedAt
        self.type = type
        self.fileUrl = fileUrl
        self.fileName = fileName
        self.fileSize = fileSize
        self.fileType = fileType
        self.thumbnailUrl = thumbnailUrl
        self.uploadProgress = uploadProgress
    }
    
    init?(id: String, chatId: String, data: [String: Any]) {
        self.id = id
        self.chatId = chatId
        self.senderId = data["senderId"] as? String ?? ""
        self.text = data["text"] as? String ?? ""
        
        // 🧩 Respuesta (quote)
        self.replyToMessageId = data["replyToMessageId"] as? String
        
        // Preferimos createdAt (server), si no, createdAtClient (local), si no, fallback.
        if let ts = data["createdAt"] as? Timestamp {
            self.createdAt = ts.dateValue()
        } else if let tsClient = data["createdAtClient"] as? Timestamp {
            self.createdAt = tsClient.dateValue()
        } else if let ms = data["createdAt"] as? Double {
            self.createdAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else {
            self.createdAt = Date()
        }
        
        // ✏️ Editado
        if let ets = data["editedAt"] as? Timestamp {
            self.editedAt = ets.dateValue()
        } else if let ems = data["editedAt"] as? Double {
            self.editedAt = Date(timeIntervalSince1970: ems / 1000.0)
        } else {
            self.editedAt = nil
        }
        
        
        if let readArray = data["readBy"] as? [String] {
            self.readBy = readArray
        } else if let legacyArray = data["readBy"] as? [Any] {
            self.readBy = legacyArray.compactMap { $0 as? String }
        } else {
            self.readBy = []
        }
        
        // 🆕 Menciones (opcional)
        if let arr = data["mentions"] as? [String] {
            self.mentions = arr
        } else if let any = data["mentions"] as? [Any] {
            self.mentions = any.compactMap { $0 as? String }
        } else {
            self.mentions = nil
        }

        
        // 🆕 Campos de archivo
        self.type = data["type"] as? String
        self.fileUrl = data["fileUrl"] as? String
        self.fileName = data["fileName"] as? String
        self.fileSize = data["fileSize"] as? Int64
        ?? (data["fileSize"] as? NSNumber)?.int64Value
        self.fileType = data["fileType"] as? String
        self.thumbnailUrl = data["thumbnailUrl"] as? String
        
        // Progreso nunca viene de Firestore
        self.uploadProgress = nil
    }
}
