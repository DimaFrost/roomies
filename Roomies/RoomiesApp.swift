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
    private static let log = Logger(subsystem: "madebyfrost.roomies", category: "sharing")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // CloudKit pushes silent notifications when a flatmate changes something;
        // Core Data turns those into store updates for us.
        application.registerForRemoteNotifications()
        return true
    }

    /// Fires when an invite link is opened. Handled on the app delegate rather
    /// than a custom scene delegate, which would mean taking over the scene
    /// configuration that SwiftUI's `WindowGroup` sets up for us.
    func application(
        _ application: UIApplication,
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
