import Foundation
import UIKit

class UserSession: ObservableObject {
    @Published var uid: String?
    @Published var email: String?
    
    @Published var username: String? {
        didSet {
            if let username {
                UserDefaults.standard.set(username, forKey: "username")
            } else {
                UserDefaults.standard.removeObject(forKey: "username")
            }
        }
    }
    
    @Published var profileImageUrl: String? {
        didSet {
            UserDefaults.standard.set(profileImageUrl, forKey: "profileImageUrl")
        }
    }
    
    @Published var avatarBustToken: String {
        didSet {
            UserDefaults.standard.set(avatarBustToken, forKey: "avatarBustToken")
        }
    }

    // 🆕 Avatar local cacheado en disco
    @Published var localAvatar: UIImage?

    var isLoggedIn: Bool {
        uid != nil
    }

    init() {
        // Cargar valores guardados
        self.username = UserDefaults.standard.string(forKey: "username")
        self.profileImageUrl = UserDefaults.standard.string(forKey: "profileImageUrl")
        self.avatarBustToken = UserDefaults.standard.string(forKey: "avatarBustToken") ?? UUID().uuidString

        // Intentar cargar avatar local desde disco
        if let img = Self.loadLocalAvatar() {
            self.localAvatar = img
        }
    }

    func clear() {
        uid = nil
        email = nil
        username = nil
        profileImageUrl = nil
        avatarBustToken = UUID().uuidString
        localAvatar = nil

        // Limpiar UserDefaults
        UserDefaults.standard.removeObject(forKey: "username")
        UserDefaults.standard.removeObject(forKey: "profileImageUrl")
        UserDefaults.standard.set(avatarBustToken, forKey: "avatarBustToken")

        // Borrar del disco
        Self.deleteLocalAvatar()
    }

    // MARK: - Avatar local en disco
    private static var avatarFileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("profile_avatar.jpg")
    }

    static func saveLocalAvatar(image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        try? data.write(to: avatarFileURL, options: .atomic)
    }

    static func loadLocalAvatar() -> UIImage? {
        guard FileManager.default.fileExists(atPath: avatarFileURL.path) else { return nil }
        return UIImage(contentsOfFile: avatarFileURL.path)
    }

    static func deleteLocalAvatar() {
        try? FileManager.default.removeItem(at: avatarFileURL)
    }
}
