import SwiftUI
import FirebaseAuth
import FirebaseFirestore


struct StarRatingView: View {
    let spot: Spot
    let userId: String
    let starSize: CGFloat   // 👈 obligatorio
    var onRated: (() -> Void)? = nil   // 👈 callback opcional
    
    @EnvironmentObject var spotsVM: SpotsViewModel
    
    @State private var userRating: Int? = nil
    @State private var average: Double = 0.0
    @State private var ratingsCount: Int = 0
    @State private var loading = true
    @State private var animateIndex: Int? = nil
    
    private let db = Firestore.firestore()
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: (userRating ?? Int(round(average))) >= i ? "star.fill" : "star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: starSize, height: starSize)
                    .foregroundColor(.yellow)
                    .scaleEffect(animateIndex == i ? 1.3 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.45), value: animateIndex)
                    .onTapGesture {
                        Task { await setRating(i) }
                    }
            }
        }
        .onAppear {
            Task { await loadRating() }
        }
        .task(id: spot.id) {
            await loadRating()
        }
    }
    
    // MARK: - Firestore
    
    private func loadRating() async { /* igual que lo tienes */ }
    
    private func setRating(_ newValue: Int) async {
        guard !userId.isEmpty else { return }
        let ref = db.collection("spots").document(spot.id)
        
        do {
            try await db.runTransaction { transaction, errorPointer in
                let snap: DocumentSnapshot
                do {
                    snap = try transaction.getDocument(ref)
                } catch let fetchError as NSError {
                    errorPointer?.pointee = fetchError
                    return nil
                }
                
                var data = snap.data() ?? [:]
                var ratings = data["ratings"] as? [String: Int] ?? [:]
                ratings[userId] = newValue
                
                let values = Array(ratings.values)
                let avg = Double(values.reduce(0, +)) / Double(values.count)
                
                data["ratings"] = ratings
                data["rating"] = Int(round(avg))
                transaction.setData(data, forDocument: ref, merge: true)
                return nil
            }
            
            await MainActor.run {
                self.userRating = newValue
                withAnimation { self.animateIndex = newValue }
                
                Task { try? await spotsVM.setMyRating(spotId: spot.id, value: newValue) }
                
                // 🔔 Avisamos al padre SIEMPRE, aunque la media no cambie
                onRated?()
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self.animateIndex = nil
                }
            }
        } catch {
            print("❌ Error guardando rating: \(error.localizedDescription)")
        }
    }
}
