import SwiftUI

@main
struct RoomiesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var store = HouseholdStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .task { await store.bootstrap() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active, store.phase == .ready {
                        Task { await store.syncNow() }
                    }
                }
        }
    }
}
