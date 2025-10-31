//
//  AdminModerationView.swift
//  Spots
//

import SwiftUI
import FirebaseFirestore

struct AdminModerationView: View {
    enum Mode { case spots, comments }
    let mode: Mode

    @State private var spotAggs: [ReportAgg] = []
    @State private var commentAggs: [ReportAgg] = []
    @State private var loading = true
    @State private var working: Set<String> = []

    private let db = Firestore.firestore()

    var body: some View {
        List {
            if mode == .spots {
                Section("Spots reportados") {
                    if spotAggs.isEmpty {
                        Text("Sin reportes de spots").foregroundColor(.secondary)
                    } else {
                        ForEach(spotAggs) { agg in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(agg.displayTitle ?? "Spot \(agg.targetId)")
                                        .font(.subheadline.bold())
                                        .lineLimit(1)
                                    Text("Reportes: \(agg.count) • Estado: \(agg.state ?? "—")")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button("Hacer público") { Task { await setSpotState(agg, to: "public") } }
                                    Button("Revisión")      { Task { await setSpotState(agg, to: "review") } }
                                    Button("Ocultar")       { Task { await setSpotState(agg, to: "hidden") } }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .disabled(working.contains(agg.id))
                            }
                        }
                    }
                }
            } else {
                Section("Comentarios reportados") {
                    if commentAggs.isEmpty {
                        Text("Sin reportes de comentarios").foregroundColor(.secondary)
                    } else {
                        ForEach(commentAggs) { agg in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(agg.displayTitle ?? "Comentario \(agg.commentId ?? "")")
                                    .font(.subheadline.bold())
                                    .lineLimit(2)

                                if let sub = agg.displaySubtitle {
                                    Text(sub).font(.caption).foregroundColor(.secondary).lineLimit(1)
                                }

                                Text("Reportes: \(agg.count) • Estado: \(agg.state ?? "—")")
                                    .font(.caption).foregroundColor(.secondary)

                                HStack {
                                    Button("Visible")  { Task { await setCommentState(agg, to: "visible") } }
                                    Button("Ocultar")  { Task { await setCommentState(agg, to: "hidden") } }
                                    Button("Borrar")   { Task { await setCommentState(agg, to: "deleted") } }
                                }
                                .buttonStyle(.bordered)
                                .disabled(working.contains(agg.id))
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(mode == .spots ? "Moderación · Spots" : "Moderación · Comentarios")
        .overlay { if loading { ProgressView().controlSize(.large) } }
        .task { await loadAggs() }
        .refreshable { await loadAggs() }
    }

    // MARK: - Data

    private func loadAggs() async {
        await MainActor.run { loading = true }
        defer { Task { @MainActor in loading = false } }

        do {
            var spots: [ReportAgg] = []
            var comments: [ReportAgg] = []

            // 1) Intentamos leer de "reportAggregates"
            do {
                let q = try await db.collection("reportAggregates").getDocuments()
                for d in q.documents {
                    let id = d.documentID
                    let count = (d.get("count") as? NSNumber)?.intValue ?? 0
                    let state = d.get("targetState") as? String

                    if id.hasPrefix("spot:") {
                        let spotId = String(id.dropFirst("spot:".count))
                        spots.append(ReportAgg(id: id, kind: .spot, targetId: spotId, count: count, state: state, spotId: spotId, commentId: nil, displayTitle: nil, displaySubtitle: nil))
                    } else if id.hasPrefix("comment:") {
                        let parts = id.split(separator: ":")
                        let sId = parts.count > 1 ? String(parts[1]) : nil
                        let cId = parts.count > 2 ? String(parts[2]) : nil
                        comments.append(ReportAgg(id: id, kind: .comment, targetId: id, count: count, state: state, spotId: sId, commentId: cId, displayTitle: nil, displaySubtitle: nil))
                    }
                }
            } catch {
                // seguimos con fallback
            }

            // 2) Fallback: si arriba vino vacío o mal, agregamos desde "reports"
            if spots.isEmpty || comments.isEmpty {
                do {
                    // Spots
                    let rs = try await db.collection("reports")
                        .whereField("type", isEqualTo: "spot")
                        .getDocuments()
                    var bucketS: [String: Int] = [:]
                    for d in rs.documents {
                        let sid = (d.get("targetId") as? String) ?? (d.get("spotId") as? String) ?? ""
                        if !sid.isEmpty { bucketS[sid, default: 0] += 1 }
                    }
                    spots = bucketS.map { (sid, cnt) in
                        ReportAgg(id: "spot:\(sid)", kind: .spot, targetId: sid, count: cnt, state: nil, spotId: sid, commentId: nil, displayTitle: nil, displaySubtitle: nil)
                    }
                } catch {}

                do {
                    // Comments
                    let rc = try await db.collection("reports")
                        .whereField("type", isEqualTo: "comment")
                        .getDocuments()
                    var bucketC: [String: (sid: String, cid: String, cnt: Int)] = [:]
                    for d in rc.documents {
                        let sid = (d.get("spotId") as? String) ?? ""
                        let cid = (d.get("commentId") as? String) ?? (d.get("targetId") as? String) ?? ""
                        guard !sid.isEmpty, !cid.isEmpty else { continue }
                        let key = "\(sid)|\(cid)"
                        let curr = bucketC[key] ?? (sid, cid, 0)
                        bucketC[key] = (sid, cid, curr.cnt + 1)
                    }
                    comments = bucketC.values.map { v in
                        ReportAgg(id: "comment:\(v.sid):\(v.cid)", kind: .comment, targetId: "\(v.sid):\(v.cid)", count: v.cnt, state: nil, spotId: v.sid, commentId: v.cid, displayTitle: nil, displaySubtitle: nil)
                    }
                } catch {}
            }

            // Resolver nombres (spots) y textos (comentarios) + estado real (visibility)
            try await resolveDisplay(for: &spots, comments: &comments)

            await MainActor.run {
                self.spotAggs = spots
                self.commentAggs = comments
            }
        } catch {
            print("❌ loadAggs error:", error.localizedDescription)
        }
    }

    private func resolveDisplay(for spots: inout [ReportAgg], comments: inout [ReportAgg]) async throws {
        // Spots → name/title + estado real
        for i in spots.indices {
            guard let sid = spots[i].spotId else { continue }
            do {
                let snap = try await db.collection("spots").document(sid).getDocument()
                let name = (snap.get("name") as? String) ?? (snap.get("title") as? String)
                spots[i].displayTitle = name ?? "Spot \(sid)"
                if let realVis = snap.get("visibility") as? String {
                    spots[i].state = realVis
                }
            } catch {
                print("⚠️ spot fetch failed for \(sid): \(error.localizedDescription)")
            }
        }

        // Comments → text + spot name para subtítulo + estado real (con fallback)
        for i in comments.indices {
            guard let sid = comments[i].spotId, let cid = comments[i].commentId else { continue }

            // Comentario
            do {
                let cSnap = try await db.collection("spots").document(sid)
                    .collection("comments").document(cid).getDocument()
                let text = (cSnap.get("text") as? String) ?? "Comentario \(cid)"
                comments[i].displayTitle = text

                if let realVis = cSnap.get("visibility") as? String {
                    comments[i].state = realVis
                } else if let del = cSnap.get("deleted") as? Bool, del == true {
                    comments[i].state = "hidden"
                } else {
                    comments[i].state = "public" // fallback para antiguos
                }
            } catch {
                print("⚠️ comment fetch failed for \(sid)/\(cid): \(error.localizedDescription)")
            }

            // Nombre del spot
            do {
                let sSnap = try await db.collection("spots").document(sid).getDocument()
                let sname = (sSnap.get("name") as? String) ?? (sSnap.get("title") as? String) ?? sid
                comments[i].displaySubtitle = "En \(sname)"
            } catch {
                comments[i].displaySubtitle = "En \(sid)"
            }
        }
    }

    // MARK: - Actions (optimista + refresh)

    private func setSpotState(_ agg: ReportAgg, to state: String) async {
        guard let sid = agg.spotId else { return }
        await MainActor.run {
            working.insert(agg.id)
            if let idx = spotAggs.firstIndex(where: { $0.id == agg.id }) {
                spotAggs[idx].state = state
            }
        }
        defer { Task { @MainActor in working.remove(agg.id) } }

        do {
            try await AdminAPI.setSpotState(spotId: sid, state: state)
            await loadAggs()
        } catch {
            print("❌ setSpotState error:", error.localizedDescription)
        }
    }

    private func setCommentState(_ agg: ReportAgg, to status: String) async {
        guard let sid = agg.spotId, let cid = agg.commentId else { return }
        await MainActor.run {
            working.insert(agg.id)
            if let idx = commentAggs.firstIndex(where: { $0.id == agg.id }) {
                commentAggs[idx].state = status
            }
        }
        defer { Task { @MainActor in working.remove(agg.id) } }

        do {
            try await AdminAPI.setCommentState(spotId: sid, commentId: cid, status: status)
            await loadAggs()
        } catch {
            print("❌ setCommentState error:", error.localizedDescription)
        }
    }
}

// MARK: - Model

private struct ReportAgg: Identifiable {
    enum Kind { case spot, comment }
    let id: String
    let kind: Kind
    let targetId: String
    let count: Int
    var state: String?
    var spotId: String?
    var commentId: String?
    var displayTitle: String?
    var displaySubtitle: String?
}
