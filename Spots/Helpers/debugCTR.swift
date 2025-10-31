import Foundation

extension ENAIRECollection {
    /// Imprime en consola todas las features que contengan "CTR" en alguna propiedad
    func debugPrintCTRs() {
        print("🔎 Buscando CTR en \(features.count) features...")
        for f in features {
            let id = f.properties?.identifier ?? "Sin ID"
            let name = f.properties?.name ?? "Sin nombre"
            let msg = f.properties?.message ?? ""
            let other = f.properties?.otherReason ?? ""

            // Buscar "CTR" en cualquier campo
            if id.uppercased().contains("CTR") ||
                name.uppercased().contains("CTR") ||
                msg.uppercased().contains("CTR") ||
                other.uppercased().contains("CTR") {
                print("✅ CTR detectado → id=\(id), name=\(name), msg=\(msg), other=\(other)")
            }
        }
    }
}
