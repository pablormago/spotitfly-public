//
//  AppDelegate.swift
//  Spots
//
//  Created by Pablo Jimenez on 11/10/25.
//


import UIKit
import UserNotifications
import FirebaseMessaging
import FirebaseFirestore
import FirebaseCore       // ya lo usas en SpotsApp
import FirebaseAuth       // Auth.auth().currentUser
import UserNotifications  // permisos + delegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        Messaging.messaging().isAutoInitEnabled = true

        // Fallback: si los permisos ya están concedidos, registra en cada arranque
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            default:
                break
            }
        }
        return true
    }


    // Tap en notificación (app foreground/background)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        if let link = userInfo["link"] as? String, let url = URL(string: link) {
            NotificationCenter.default.post(name: .openSpotsDeepLink, object: url)
        }
        completionHandler()
    }

    // Mostrar banners también en foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    // FCM token listo / rotado
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("🔔 FCM token = \(token)")

        if let uid = Auth.auth().currentUser?.uid {
            let ref = Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(token)
            ref.setData([
                "platform": "ios",
                "updatedAt": FieldValue.serverTimestamp(),
                "language": Locale.preferredLanguages.first ?? "es-ES"
            ], merge: true) { error in
                if let error {
                    print("⚠️ Could not save FCM token (delegate):", error.localizedDescription)
                } else {
                    print("✅ Saved FCM token (delegate):", token)
                }
            }
        }
    }



    // (ya tenías estos dos; los dejamos tal cual)
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("📲 APNS token = \(tokenString)")

        // Enlaza APNs → FCM ya mismo
        Messaging.messaging().apnsToken = deviceToken

        // Si hay sesión, pide FCM y guarda en Firestore inmediatamente (ya no habrá error de "No APNS token specified")
        if let uid = Auth.auth().currentUser?.uid {
            Messaging.messaging().token { token, error in
                if let token {
                    let ref = Firestore.firestore()
                        .collection("users").document(uid)
                        .collection("devices").document(token)
                    ref.setData([
                        "platform": "ios",
                        "updatedAt": FieldValue.serverTimestamp(),
                        "language": Locale.preferredLanguages.first ?? "es-ES"
                    ], merge: true) { err in
                        if let err {
                            print("⚠️ Could not save FCM token after APNs:", err.localizedDescription)
                        } else {
                            print("✅ Saved FCM token after APNs:", token)
                        }
                    }
                } else if let error {
                    print("⚠️ Could not fetch FCM token after APNs:", error.localizedDescription)
                }
            }
        }
    }


    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ APNS registration failed:", error.localizedDescription)
    }
}
