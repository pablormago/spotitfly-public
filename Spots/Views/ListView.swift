import SwiftUI

struct ListView: View {
    @EnvironmentObject var vm: RestriccionesViewModel   // 👈 ya no se crea, se reutiliza
    @EnvironmentObject var notamVM: NOTAMViewModel
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var userSession: UserSession

    var body: some View {
        VStack {
            if vm.isLoading {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding(.bottom, 8)
                    Text("Cargando Restricciones…")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if let error = vm.errorMessage {
                VStack {
                    Text("❌ Error: \(error)")
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.restricciones) { feature in
                        NavigationLink(
                            destination: RestriccionDetailView(feature: feature)
                                .environmentObject(notamVM)
                        ) {
                            RestriccionRow(
                                feature: feature,
                                hasNotam: notamVM.hasNotam(for: feature)
                            )
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .padding(.top, 10)
            }
        }
        .navigationTitle("Restricciones")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let username = userSession.username {
                    Text(username)
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                }
            }
        }
        .task {
            await vm.fetchRestricciones()   // ✅ ya no se reinicia cada vez
            /*if notamVM.notams.isEmpty {
                await notamVM.fetchNotams()
            }*/
        }
    }
}
