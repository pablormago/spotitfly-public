//
//  AdminBlocksView.swift
//  Spots
//
//  Created by Pablo Jimenez on 2/10/25.
//


//
//  AdminBlocksView.swift
//  Spots
//

import SwiftUI

struct AdminBlocksView: View {
    @StateObject private var vm = AdminBlocksVM()
    @State private var working: Set<String> = []

    var body: some View {
        List {
            Section {
                if vm.rows.isEmpty && !vm.loading {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.raised.slash")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary)
                        Text("No tienes usuarios bloqueados")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ForEach(vm.rows) { row in
                        HStack {
                            ZStack {
                                Circle().fill(Color.red.opacity(0.12))
                                Text(initials(for: row.name ?? row.id))
                                    .font(.caption.bold())
                                    .foregroundColor(.red)
                            }
                            .frame(width: 36, height: 36)

                            VStack(alignment: .leading) {
                                Text(row.name ?? row.id)
                                    .font(.headline)
                                Text(row.id).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if working.contains(row.id) {
                                ProgressView().scaleEffect(0.8)
                            } else {
                                Button("Desbloquear") {
                                    Task {
                                        await MainActor.run { working.insert(row.id) }
                                        defer { Task { @MainActor in working.remove(row.id) } }
                                        await vm.unblock(row.id)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .tint(.blue)
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Bloqueos (tuyos)")
                    if vm.loading { Spacer(); ProgressView().scaleEffect(0.7) }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Bloqueos")
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    private func initials(for name: String) -> String {
        String(name.prefix(2)).uppercased()
    }
}
