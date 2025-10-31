//
//  SupportInboxView.swift
//  Spots
//

import SwiftUI
import FirebaseAuth

struct SupportInboxView: View {
    @StateObject private var vm = SupportInboxVM()

    var body: some View {
        List {
            if vm.chats.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "lifepreserver").font(.largeTitle)
                    Text("Sin hilos de soporte").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                // compacta un poco el alto de la primera fila
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            } else {
                ForEach(vm.chats) { chat in
                    NavigationLink {
                        // Al entrar, marcamos leído
                        ChatDetailView(chat: chat, backLabel: "Soporte", supportMode: true)
                            .onAppear { vm.markAsRead(chatId: chat.id) }
                    } label: {
                        row(chat: chat)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(PlainListStyle()) // equivalente a .plain
        // Título "inline" usando la API antigua (evita error de inferencia)
        .navigationBarTitle(Text("Soporte"), displayMode: .inline)
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: - Row

    private func row(chat: Chat) -> some View {
        let uid = Auth.auth().currentUser?.uid ?? ""
        let unread = vm.hasUnread(chat, uid: uid)

        return HStack(spacing: 12) {
            Image(systemName: "lifepreserver").font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.displayName ?? "Soporte")
                    .font(.subheadline)
                    .fontWeight(unread ? .bold : .regular)   // negrita si no leído
                    .lineLimit(1)

                if let last = chat.lastMessage {
                    Text(last)
                        .font(.caption)
                        .foregroundColor(unread ? .primary : .secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                if let date = chat.updatedAt {
                    Text(DateFormatter.shortTimeOrDate.string(from: date))
                        .font(.caption2).foregroundColor(.secondary)
                }

                if unread {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("No leído")
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16)) // compáctalo un poco
    }
}

fileprivate extension DateFormatter {
    static let shortTimeOrDate: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.timeStyle = .short
        df.dateStyle = .short
        return df
    }()
}
