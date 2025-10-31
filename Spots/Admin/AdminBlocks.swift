//
//  BlockRow.swift
//  Spots
//
//  Created by Pablo Jimenez on 2/10/25.
//


//
//  AdminBlocksVM.swift
//  Spots
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

struct BlockRow: Identifiable, Equatable {
    let id: String    // uid bloqueado
    let name: String?
}

@MainActor
final class AdminBlocksVM: ObservableObject {
    @Published var rows: [BlockRow] = []
    @Published var loading: Bool = false
    
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    
    func start() {
        guard listener == nil else { return }
        guard let my = Auth.auth().currentUser?.uid else { return }
        loading = true
        listener = db.collection("users").document(my)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let arr = (snap?.data()?["blockedUsers"] as? [String]) ?? []
                Task {
                    var out: [BlockRow] = []
                    for uid in arr {
                        let name = await UserService.shared.username(for: uid)
                        out.append(BlockRow(id: uid, name: name))
                    }
                    await MainActor.run {
                        self.rows = out.sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }
                        self.loading = false
                    }
                }
            }
    }
    
    func stop() {
        listener?.remove()
        listener = nil
    }
    
    func unblock(_ uid: String) async {
        guard let my = Auth.auth().currentUser?.uid else { return }
        do {
            try await db.collection("users").document(my)
                .setData(["blockedUsers": FieldValue.arrayRemove([uid])], merge: true)
            // BEGIN INSERT — limpiar reportes en backend si eres admin/support
            do {
                try await AdminAPI.unblockUserAsAdmin(userId: uid)
            } catch {
                // Si no eres admin/support, esta callable puede devolver permission-denied.
                // Lo ignoramos a propósito; el desbloqueo local ya se aplicó correctamente.
            }
            // END INSERT — limpiar reportes en backend si eres admin/support
        } catch {
            print("❌ unblock error:", error.localizedDescription)
        }
    }
}
