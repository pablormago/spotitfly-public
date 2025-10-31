//
//  AdminReportedUsersView.swift
//  Spots
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

@MainActor
struct AdminReportedUsersView: View {
    @State private var items: [AdminReportedUserItem] = []
    @State private var loading = true
    @State private var working: Set<String> = []
    @State private var blocked: Set<String> = []

    private let db = Firestore.firestore()

    var body: some View {
        List {
            Section("Usuarios reportados") {
                if items.isEmpty {
                    Text("Sin usuarios reportados").foregroundColor(.secondary)
                } else {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(item.username).font(.subheadline.bold()).lineLimit(1)
                                if blocked.contains(item.id) {
                                    Text("Bloqueado").font(.caption2)
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.15))
                                        .cornerRadius(6)
                                }
                            }

                            Text("Reportes: \(item.reportersCount) · Último: \(item.lastReason)")
                            
                                .font(.caption).foregroundColor(.secondary).lineLimit(1)

                            HStack(spacing: 8) {
                                Button {
                                    Task { await block(targetUid: item.id) }
                                } label: {
                                    Label("Bloquear", systemImage: "hand.raised.fill")
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                                .disabled(working.contains(item.id))

                                Button {
                                    Task { await unblock(targetUid: item.id) }
                                } label: {
                                    Label("Desbloquear", systemImage: "hand.raised")
                                }
                                .buttonStyle(.bordered)
                                .disabled(working.contains(item.id))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bloqueos")
        .task {
            await loadReportedUsers()
            await loadBlockedSet()
        }
        .refreshable {
            await loadReportedUsers()
            await loadBlockedSet()
        }
    }

    // MARK: - Data

    private func loadReportedUsers() async {
        await MainActor.run { loading = true }
        defer { Task { @MainActor in loading = false } }

        do {
            // reports: { type:"user", reporterId, targetId, reason, createdAt, ... }
            let q = try await db.collection("reports")
                .whereField("type", isEqualTo: "user").getDocuments()

            // targetUid -> (reasons[], reporters Set)
            var bucket: [String: (reasons: [String], reporters: Set<String>)] = [:]

            for d in q.documents {
                let targetUid = (d.get("targetId") as? String)
                    ?? (d.get("reportedUserId") as? String)
                    ?? ""
                guard !targetUid.isEmpty else { continue }

                let reason = (d.get("reason") as? String) ?? "—"
                let reporter = (d.get("reporterId") as? String) ?? "anon"

                var entry = bucket[targetUid] ?? ([], [])
                entry.reasons.append(reason)
                entry.reporters.insert(reporter)
                bucket[targetUid] = entry
            }

            // Resolver usernames
            var result: [AdminReportedUserItem] = []
            for (uid, data) in bucket {
                var username = uid
                if let snap = try? await db.collection("users").document(uid).getDocument() {
                    username = (snap.get("username") as? String) ?? username
                }
                result.append(AdminReportedUserItem(
                    id: uid,
                    username: username,
                    reportersCount: data.reporters.count,
                    lastReason: data.reasons.last ?? "—"
                ))
            }

            await MainActor.run {
                items = result.sorted { $0.reportersCount > $1.reportersCount }
            }
        } catch {
            print("❌ load users reports:", error.localizedDescription)
        }
    }

    private func loadBlockedSet() async {
        guard let my = Auth.auth().currentUser?.uid else { return }
        do {
            let u = try await db.collection("users").document(my).getDocument()
            if let arr = u.get("blockedUsers") as? [String] {
                await MainActor.run { blocked = Set(arr) }
            } else {
                await MainActor.run { blocked = [] }
            }
        } catch {
            print("❌ load blocked:", error.localizedDescription)
        }
    }

    // MARK: - Actions (bloqueo local del admin)

    private func block(targetUid: String) async {
        guard let my = Auth.auth().currentUser?.uid else { return }
        await MainActor.run { working.insert(targetUid) }
        defer { Task { @MainActor in working.remove(targetUid) } }

        do {
            try await db.collection("users").document(my)
                .setData(["blockedUsers": FieldValue.arrayUnion([targetUid])], merge: true)
            await loadBlockedSet()
        } catch {
            print("❌ block error:", error.localizedDescription)
        }
    }

    private func unblock(targetUid: String) async {
        guard let my = Auth.auth().currentUser?.uid else { return }
        await MainActor.run { working.insert(targetUid) }
        defer { Task { @MainActor in working.remove(targetUid) } }

        do {
            try await db.collection("users").document(my)
                .setData(["blockedUsers": FieldValue.arrayRemove([targetUid])], merge: true)
            // BEGIN INSERT — limpiar reportes en backend si eres admin/support
            do {
                try await AdminAPI.unblockUserAsAdmin(userId: targetUid)
            } catch {
                // Si el usuario actual no es admin/support, ignoramos el error de permisos.
            }
            // END INSERT — limpiar reportes en backend si eres admin/support

            await loadBlockedSet()
        } catch {
            print("❌ unblock error:", error.localizedDescription)
        }
    }
}
