//
//  ModerationDecision.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//


import Foundation

enum ModerationDecision {
    case allow
    case warn(String)   // mensaje para el usuario
    case block(String)  // mensaje para el usuario
}

struct ModerationService {
    // Palabras/expresiones de ejemplo. Ajusta según tus necesidades/idioma.
    // Importante: mantenlo pequeño y razonable para evitar falsos positivos.
    private static let blocklist: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\b(nazi|hitler|violación|violar|incesto)\b"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"(?:suicídate|mátate|kill yourself)"#, options: [.caseInsensitive])
    ]

    private static let warnlist: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: #"\b(puta|gilipollas|imbécil|mierda)\b"#, options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: #"(?:te voy a (?:pegar|matar))"#, options: [.caseInsensitive])
    ]

    static func evaluate(_ text: String) -> ModerationDecision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .allow }

        // BLOQUEAR si coincide con blocklist
        for re in blocklist {
            if re.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
                return .block("Tu mensaje infringe las normas de la comunidad y no puede enviarse.")
            }
        }

        // AVISAR si coincide con warnlist
        for re in warnlist {
            if re.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil {
                return .warn("Tu mensaje podría incumplir las normas. ¿Seguro que quieres enviarlo?")
            }
        }

        return .allow
    }
}
