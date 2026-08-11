import CloudKit
import SwiftUI
import os

@main
struct RoomiesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = HouseholdStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, Persistence.shared.viewContext)
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit pushes silent notifications when a flatmate changes something;
        // Core Data turns those into store updates for us.
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

/// Exists solely to catch accepted share invitations, which arrive as a scene callback.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    private static let log = Logger(subsystem: "com.dimafrost.roomies", category: "sharing")

    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            do {
                try await Persistence.shared.acceptShare(metadata: cloudKitShareMetadata)
            } catch {
                Self.log.error("Could not accept invite: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
