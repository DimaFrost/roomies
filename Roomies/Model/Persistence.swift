import CloudKit
import CoreData
import os

/// Owns the Core Data stack and its CloudKit mirroring.
///
/// Two stores are loaded against the same model: the **private** store holds the
/// household you created, the **shared** store holds a household someone else
/// invited you into. Core Data keeps both in sync with CloudKit, so a flatmate's
/// expense lands here without any server of our own.
final class Persistence {
    static let shared = Persistence()

    static let cloudKitContainerIdentifier = "iCloud.com.dimafrost.roomies"

    private static let log = Logger(subsystem: "com.dimafrost.roomies", category: "persistence")

    let container: NSPersistentCloudKitContainer

    /// Store for households this device owns. Assigned during store loading.
    private(set) var privateStore: NSPersistentStore?
    /// Store for households shared with this device by a flatmate.
    private(set) var sharedStore: NSPersistentStore?

    var viewContext: NSManagedObjectContext { container.viewContext }

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "Roomies")

        guard let privateDescription = container.persistentStoreDescriptions.first,
              let defaultURL = privateDescription.url else {
            fatalError("Roomies: the Core Data model has no default store description")
        }

        if inMemory {
            privateDescription.url = URL(fileURLWithPath: "/dev/null")
            privateDescription.cloudKitContainerOptions = nil
            container.persistentStoreDescriptions = [privateDescription]
        } else {
            let directory = defaultURL.deletingLastPathComponent()

            privateDescription.url = directory.appendingPathComponent("private.sqlite")
            Self.enableCloudKit(on: privateDescription, scope: .private)

            guard let sharedDescription = privateDescription.copy() as? NSPersistentStoreDescription else {
                fatalError("Roomies: could not derive the shared store description")
            }
            sharedDescription.url = directory.appendingPathComponent("shared.sqlite")
            Self.enableCloudKit(on: sharedDescription, scope: .shared)

            container.persistentStoreDescriptions = [privateDescription, sharedDescription]
        }

        container.loadPersistentStores { [weak self] description, error in
            if let error {
                Self.log.error("Store failed to load: \(error.localizedDescription, privacy: .public)")
                return
            }
            guard let self, let url = description.url else { return }
            let store = self.container.persistentStoreCoordinator.persistentStore(for: url)
            switch description.cloudKitContainerOptions?.databaseScope {
            case .shared: self.sharedStore = store
            default: self.privateStore = store
            }
        }

        let context = viewContext
        context.automaticallyMergesChangesFromParent = true
        // Last writer wins per property: two flatmates editing different fields of
        // the same expense both keep their change.
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        context.transactionAuthor = "roomies.app"
        try? context.setQueryGenerationFrom(.current)
    }

    private static func enableCloudKit(on description: NSPersistentStoreDescription, scope: CKDatabase.Scope) {
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
        // Both are prerequisites for CloudKit mirroring.
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
    }

    func save() {
        let context = viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            Self.log.error("Save failed: \(error.localizedDescription, privacy: .public)")
            context.rollback()
        }
    }

    // MARK: - Sharing

    /// True when the household is backed by a CKShare — i.e. a flat with invited members.
    func isShared(_ household: Household) -> Bool {
        existingShare(for: household) != nil
    }

    /// True when this device created the household (it lives in the private store).
    func isOwner(of household: Household) -> Bool {
        guard let store = household.objectID.persistentStore else { return true }
        return store != sharedStore
    }

    func existingShare(for household: Household) -> CKShare? {
        try? container.fetchShares(matching: [household.objectID])[household.objectID]
    }

    /// Creates the CKShare for a household, or returns the one it already has.
    /// The returned pair is what `UICloudSharingController` needs to present the invite sheet.
    func share(_ household: Household) async throws -> (CKShare, CKContainer) {
        if let existing = existingShare(for: household) {
            return (existing, CKContainer(identifier: Self.cloudKitContainerIdentifier))
        }

        let result = try await container.share([household], to: nil)
        result.share[CKShare.SystemFieldKey.title] = household.name ?? "Roomies"
        return (result.share, result.container)
    }

    /// Handles an invite link tapped in Messages/Mail. The household then appears
    /// in the shared store and, because the UI fetches across both stores, in the app.
    func acceptShare(metadata: CKShare.Metadata) async throws {
        guard let sharedStore else {
            throw PersistenceError.sharedStoreUnavailable
        }
        try await container.acceptShares(from: [metadata], into: sharedStore)
    }

    /// Stops sharing (owner) or leaves the flat (participant).
    func stopSharing(_ household: Household) async throws {
        guard let share = existingShare(for: household) else { return }
        let ckContainer = CKContainer(identifier: Self.cloudKitContainerIdentifier)
        let database = isOwner(of: household) ? ckContainer.privateCloudDatabase : ckContainer.sharedCloudDatabase
        _ = try await database.modifyRecords(saving: [], deleting: [share.recordID])
    }
}

enum PersistenceError: LocalizedError {
    case sharedStoreUnavailable

    var errorDescription: String? {
        switch self {
        case .sharedStoreUnavailable:
            return "iCloud sharing isn't ready yet. Try again in a moment."
        }
    }
}

extension NSPersistentCloudKitContainer {
    /// Async wrapper over the completion-handler API. Named differently from the
    /// ObjC method it wraps so overload resolution stays unambiguous.
    func acceptShares(from metadata: [CKShare.Metadata], into store: NSPersistentStore) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            acceptShareInvitations(from: metadata, into: store) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
