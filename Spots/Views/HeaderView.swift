import SwiftUI

struct HeaderView: View {
    @EnvironmentObject var userSession: UserSession

    var body: some View {
        VStack(spacing: 6) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 70, height: 70)

            Image("Texto")
                .resizable()
                .scaledToFit()
                .frame(height: 50)

            if let username = userSession.username, !username.isEmpty {
                Text("👋 Hola, \(username)")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground).opacity(0.95))
    }
}
