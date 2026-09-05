import Foundation
import CloudKit
import Combine

enum Phase: Equatable {
    case loading
    /// No household on this device yet, and no share was accepted — only "create" is offered.
    case needsHousehold
    /// A household/zone was found (we accepted a share, or this is a fresh reinstall) but this
    /// device doesn't have a Member record yet — prompt for a display name.
    case needsName
    case ready
    case error
}

@MainActor
final class HouseholdStore: ObservableObject {
    /// Bridges the UIApplicationDelegate's CKShare-acceptance callback to the running store.
    static var current: HouseholdStore?

    @Published var phase: Phase = .loading
    @Published var state = HouseholdState()
    @Published var flat: FlatInfo?
    @Published var myName: String?
    @Published var error: String?
    /// Set whenever there's a share link to show the user (after creating a household, or from
    /// "Invite a flatmate"). We present our own copy-the-link UI rather than the system share
    /// sheet — see `InviteLinkView`.
    @Published var pendingShare: CKShare?
    /// Writes composed on this device that CloudKit hasn't accepted yet.
    @Published private(set) var pendingWrites: [PendingWrite] = []
    /// True when what's on screen came from the offline snapshot rather than a live fetch.
    @Published private(set) var isStale = false

    private let container = CKContainer(identifier: "iCloud.com.madebyfrost.roomies")
    private var database: CKDatabase?
    private var zoneID: CKRecordZone.ID?
    private(set) var isOwner = false
    private var myUserRecordID: CKRecord.ID?
    private var subscriptionRegistered = false
    /// Guards against two flushes running at once — they would race over the same queue entries.
    private var isFlushing = false

    private static let householdRecordType = "Household"
    private static let memberRecordType = "Member"
    private static let expenseRecordType = "Expense"
    private static let askRecordType = "Ask"
    private static let billRecordType = "Bill"
    private static let planRecordType = "PlanEvent"
    private static let zoneName = "Household"
    private static let householdRecordName = "household"
    private static let subscriptionSavedKey = "roomies.cloudkit.subscriptionSaved"
    private static let myMemberRecordKey = "roomies.myMemberRecordName"
    private static let leftZonesKey = "roomies.leftZones"

    init() {
        HouseholdStore.current = self
        pendingWrites = LocalPersistence.loadPendingWrites()
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        phase = .loading
        error = nil

        // Show the last known state straight away and let the fetch below catch it up. Without
        // this, opening the app with no signal means an error screen — or worse, an indefinite
        // blank one — with every balance already sitting on the device.
        let hasUsableCache = restoreSnapshot()
        if hasUsableCache {
            isStale = true
            phase = .ready
        }
        startBootstrapWatchdog()

        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                error = "Sign in to iCloud in Settings to sync your flat."
                phase = .error
                return
            }
            myUserRecordID = try await container.userRecordID()

            if let shared = try await findZone(in: container.sharedCloudDatabase) {
                isOwner = false
                database = container.sharedCloudDatabase
                zoneID = shared
            } else if let owned = try await findZone(named: HouseholdStore.zoneName, in: container.privateCloudDatabase) {
                isOwner = true
                database = container.privateCloudDatabase
                zoneID = owned
            } else {
                phase = .needsHousehold
                return
            }

            await registerSubscriptionIfNeeded()
            // Push before pulling: a refresh that ran first would overwrite the local rows behind
            // any queued writes with server state that doesn't contain them yet.
            await flushPendingWrites()
            try await refreshAll()
            isStale = false
        } catch {
            if hasUsableCache {
                // A stale flat beats an error screen — it's readable, and new expenses queue
                // until the connection is back.
                isStale = true
                phase = .ready
            } else {
                self.error = error.localizedDescription
                phase = .error
            }
        }
    }

    private func findZone(in db: CKDatabase) async throws -> CKRecordZone.ID? {
        let zones = try await db.allRecordZones()
        let left = HouseholdStore.leftZones()
        // Skip a zone we deliberately left. Removing ourselves from the share is the only way to
        // stop CloudKit handing the zone back, and it isn't always permitted — without this,
        // "Start over" reset the local state and the very next launch rediscovered the same
        // shared zone and dropped the user straight back into the join screen, permanently.
        return zones.first(where: {
            $0.zoneID.zoneName == HouseholdStore.zoneName && !left.contains(HouseholdStore.zoneKey($0.zoneID))
        })?.zoneID
    }

    private static func zoneKey(_ id: CKRecordZone.ID) -> String {
        "\(id.zoneName)|\(id.ownerName)"
    }

    private static func leftZones() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: leftZonesKey) ?? [])
    }

    private static func markZoneLeft(_ id: CKRecordZone.ID) {
        var left = leftZones()
        left.insert(zoneKey(id))
        UserDefaults.standard.set(Array(left), forKey: leftZonesKey)
    }

    private static func unmarkZoneLeft(_ id: CKRecordZone.ID) {
        var left = leftZones()
        left.remove(zoneKey(id))
        UserDefaults.standard.set(Array(left), forKey: leftZonesKey)
    }

    private func findZone(named name: String, in db: CKDatabase) async throws -> CKRecordZone.ID? {
        let zones = try await db.allRecordZones()
        return zones.first(where: { $0.zoneID.zoneName == name })?.zoneID
    }

    // MARK: - Household setup

    /// Creates a new zone + CKShare + Household record, and a Member record for this device.
    /// Sets `pendingShare` so the UI can present the system share sheet.
    func createHousehold(flatName: String, memberName: String) async -> String? {
        do {
            let db = container.privateCloudDatabase
            let zone = CKRecordZone(zoneName: HouseholdStore.zoneName)
            _ = try await db.save(zone)

            let zoneID = zone.zoneID
            let householdID = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
            let household = CKRecord(recordType: HouseholdStore.householdRecordType, recordID: householdID)
            household["name"] = flatName as CKRecordValue

            let share = CKShare(rootRecord: household)
            share[CKShare.SystemFieldKey.title] = flatName as CKRecordValue
            // Closed by default: the link is an address, not a key. Access comes from being an
            // explicit participant, added by iCloud identity in `inviteFlatmate`. With
            // `.readWrite` here the URL itself granted full access to anyone holding it —
            // permanently, and to anyone they forwarded it to — which made single-use invites
            // impossible and `removeMember` cosmetic, since an evicted flatmate just used the
            // old link again.
            share.publicPermission = .none

            let memberID = CKRecord.ID(recordName: makeId(), zoneID: zoneID)
            let member = CKRecord(recordType: HouseholdStore.memberRecordType, recordID: memberID)
            member["name"] = memberName as CKRecordValue

            _ = try await db.modifyRecords(saving: [household, share, member], deleting: [])
            UserDefaults.standard.set(memberID.recordName, forKey: HouseholdStore.myMemberRecordKey)

            self.database = db
            self.zoneID = zoneID
            self.isOwner = true
            self.myUserRecordID = try await container.userRecordID()

            await registerSubscriptionIfNeeded()
            try await refreshAll()
            pendingShare = share
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Called once a CKShare invite has been accepted (from the app delegate callback) and this
    /// device has a shared zone but no Member record of its own yet.
    func joinHousehold(memberName: String) async -> String? {
        guard let db = database, let zoneID = zoneID else {
            return "No shared flat found yet — try opening the invite link again."
        }
        do {
            let memberID = CKRecord.ID(recordName: makeId(), zoneID: zoneID)
            let member = CKRecord(recordType: HouseholdStore.memberRecordType, recordID: memberID)
            member["name"] = memberName as CKRecordValue
            _ = try await db.save(member)
            UserDefaults.standard.set(memberID.recordName, forKey: HouseholdStore.myMemberRecordKey)
            try await refreshAll()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Invoked by the app delegate right after the system finishes accepting a CKShare.
    func handleAcceptedShare(metadata: CKShare.Metadata) async {
        do {
            _ = try await container.sharedCloudDatabase.record(for: metadata.share.recordID)
        } catch {
            // The share metadata already carries what we need even if this lookup fails.
        }
        database = container.sharedCloudDatabase
        zoneID = metadata.share.recordID.zoneID
        isOwner = false
        // Accepting an invite to a flat we previously left is a deliberate rejoin.
        HouseholdStore.unmarkZoneLeft(metadata.share.recordID.zoneID)
        await bootstrap()
    }

    // MARK: - Refresh

    func refreshAll() async throws {
        guard let db = database, let zoneID = zoneID else { return }

        let records = try await fetchZoneRecords(db: db, zoneID: zoneID)

        let householdRec = records.first { $0.recordType == HouseholdStore.householdRecordType }
        let memberRecs = records.filter { $0.recordType == HouseholdStore.memberRecordType }
        let expenseRecs = records.filter { $0.recordType == HouseholdStore.expenseRecordType }
        let askRecs = records.filter { $0.recordType == HouseholdStore.askRecordType }
        let billRecs = records.filter { $0.recordType == HouseholdStore.billRecordType }
        let planRecs = records.filter { $0.recordType == HouseholdStore.planRecordType }

        // A zone with no Household record means a prior `createHousehold` attempt created the
        // zone but failed before saving the Household/Share/Member batch (e.g. schema wasn't
        // deployed yet). Only an owner can be in this state — a participant's zone always has a
        // Household record, since sharing only happens after the owner's batch save succeeds.
        guard let householdRec else {
            if isOwner {
                phase = .needsHousehold
            } else {
                error = "This invite doesn't have a flat set up yet — ask whoever shared it to try again."
                phase = .error
            }
            return
        }

        let byOldest = memberRecs.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }

        // One Member per name: a retried setup can leave duplicates behind, and a flat has one
        // person per name by definition. Oldest wins so ids stay stable across refreshes.
        var seenNames = Set<String>()
        var canonical: [CKRecord] = []
        var duplicates: [CKRecord] = []
        for record in byOldest {
            guard let name = record["name"] as? String else { continue }
            if seenNames.insert(name).inserted {
                canonical.append(record)
            } else {
                duplicates.append(record)
            }
        }

        let people = canonical.compactMap { $0["name"] as? String }

        // Identify our own Member record by the id we saved locally when creating it. We can't
        // rely on `creatorUserRecordID`: in a private database it comes back as the sentinel
        // `__defaultOwner__` rather than the id `userRecordID()` returns, so a direct comparison
        // never matches for the household owner.
        let storedMemberName = UserDefaults.standard.string(forKey: HouseholdStore.myMemberRecordKey)
        let myRecord = byOldest.first { $0.recordID.recordName == storedMemberName }
            ?? byOldest.first { isMe($0.creatorUserRecordID) }
        let name = myRecord?["name"] as? String

        // Re-point our stored id at the surviving record, so a duplicate we're about to delete
        // never stays as our identity.
        if let name, let surviving = canonical.first(where: { ($0["name"] as? String) == name }) {
            UserDefaults.standard.set(surviving.recordID.recordName, forKey: HouseholdStore.myMemberRecordKey)
        }

        if !duplicates.isEmpty {
            let ids = duplicates.map(\.recordID)
            Task { [weak self] in
                _ = try? await db.modifyRecords(saving: [], deleting: ids)
                _ = self
            }
        }

        let expenses: [Expense] = expenseRecs.compactMap(Self.expense(from:)).sorted { $0.createdAt > $1.createdAt }
        let asks: [Ask] = askRecs.compactMap(Self.ask(from:)).sorted { $0.createdAt > $1.createdAt }
        let bills: [Bill] = billRecs.compactMap(Self.bill(from:)).sorted { $0.dueDay < $1.dueDay }
        let plans: [PlanEvent] = planRecs.compactMap(Self.plan(from:)).sorted { $0.start < $1.start }

        state = HouseholdState(people: people, expenses: expenses, asks: asks, bills: bills, plans: plans)
        flat = FlatInfo(
            name: (householdRec["name"] as? String) ?? "Your flat",
            shareURL: nil,
            rentAmount: householdRec["rentAmount"] as? Double,
            rentDueDay: householdRec["rentDueDay"] as? Int
        )

        if let name {
            myName = name
            phase = .ready
        } else {
            myName = nil
            phase = .needsName
        }

        isStale = false
        persistSnapshot()
    }

    /// Fetches every record in the zone directly (no CKQuery involved), so this never depends on
    /// a field being marked queryable in the schema — unlike `CKQuery`, which requires a queryable
    /// index even for a match-everything predicate.
    private func isMe(_ creator: CKRecord.ID?) -> Bool {
        guard let creator else { return false }
        return creator.recordName == CKCurrentUserDefaultName || creator == myUserRecordID
    }

    private func fetchZoneRecords(db: CKDatabase, zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        try await withCheckedThrowingContinuation { continuation in
            var records: [CKRecord] = []
            let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
            config.previousServerChangeToken = nil
            let operation = CKFetchRecordZoneChangesOperation(
                recordZoneIDs: [zoneID],
                configurationsByRecordZoneID: [zoneID: config]
            )
            operation.fetchAllChanges = true
            operation.recordWasChangedBlock = { _, result in
                if case .success(let record) = result {
                    records.append(record)
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            db.add(operation)
        }
    }

    // MARK: - Push-triggered refresh

    private func registerSubscriptionIfNeeded() async {
        guard let db = database else { return }
        let key = HouseholdStore.subscriptionSavedKey + (isOwner ? ".private" : ".shared")
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: "roomies-\(isOwner ? "private" : "shared")")
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info
        do {
            _ = try await db.save(subscription)
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            // Non-fatal: falls back to foreground/pull-to-refresh syncing.
        }
    }

    func handleRemoteNotification() async {
        await syncNow()
    }

    // MARK: - Offline sync

    /// A write that can't be attempted yet because the zone isn't resolved — treated as
    /// temporary, since bootstrap will resolve it.
    private enum SyncError: Error { case notReady }

    /// `CKContainer.accountStatus()` does not reliably fail when the account is unusable — it can
    /// sit there indefinitely refreshing authorization (reproducible on a simulator with no
    /// iCloud account signed in), and `bootstrap` awaits it as its very first call. Without a
    /// deadline the app shows an empty screen for as long as the user is willing to look at it.
    private func startBootstrapWatchdog() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self, self.phase == .loading else { return }
            self.error = "Can't reach iCloud. Check your connection and try again."
            self.phase = .error
        }
    }

    func dismissError() { error = nil }

    /// Pushes anything queued, then pulls. The foreground and push entry point.
    func syncNow() async {
        await flushPendingWrites()
        do {
            try await refreshAll()
        } catch {
            isStale = true
        }
    }

    /// Loads the offline snapshot into live state. Returns whether there was enough to show the
    /// flat without touching the network.
    @discardableResult
    private func restoreSnapshot() -> Bool {
        guard let snapshot = LocalPersistence.loadSnapshot() else { return false }
        state = snapshot.state
        flat = snapshot.flat
        myName = snapshot.myName
        isOwner = snapshot.isOwner
        // Restoring the zone is what lets writes still be composed and queued while offline;
        // discovering it normally costs an `allRecordZones()` round trip.
        zoneID = snapshot.zoneID
        database = snapshot.isOwner ? container.privateCloudDatabase : container.sharedCloudDatabase
        return snapshot.myName != nil && snapshot.flat != nil
    }

    private func persistSnapshot() {
        guard let zoneID, myName != nil else { return }
        LocalPersistence.saveSnapshot(CachedSnapshot(
            state: state,
            flat: flat,
            myName: myName,
            isOwner: isOwner,
            zoneName: zoneID.zoneName,
            zoneOwnerName: zoneID.ownerName,
            savedAt: Date()
        ))
    }

    private func enqueue(_ write: PendingWrite) {
        if let idx = pendingWrites.firstIndex(where: { $0.id == write.id }) {
            pendingWrites[idx] = pendingWrites[idx].merging(write)
        } else {
            pendingWrites.append(write)
        }
        LocalPersistence.savePendingWrites(pendingWrites)
    }

    /// Sends a write to CloudKit, keeping the optimistic local row either way.
    ///
    /// If it fails for a reason that could pass later — no signal, rate limiting, a busy zone —
    /// the write goes on the queue rather than being thrown away. Only a permanent refusal
    /// discards it, and then we re-read the server so the UI stops showing a row that will
    /// never exist.
    private func commit(_ write: PendingWrite, describing subject: String) {
        persistSnapshot()
        Task {
            do {
                try await perform(write, replaying: false)
                persistSnapshot()
            } catch {
                if Self.isRetryable(error) {
                    enqueue(write)
                } else {
                    self.error = "\(subject) couldn't be saved: \(error.localizedDescription)"
                    try? await refreshAll()
                }
            }
        }
    }

    private func perform(_ write: PendingWrite, replaying: Bool) async throws {
        guard let db = database, let zoneID else { throw SyncError.notReady }
        let recordID = CKRecord.ID(recordName: write.id, zoneID: zoneID)

        switch write.kind {
        case .delete:
            do {
                _ = try await db.deleteRecord(withID: recordID)
            } catch let error as CKError where error.code == .unknownItem {
                // Already gone, or it never reached the server. Either way there's nothing to do.
            }
        case .save:
            let record: CKRecord
            if write.isNew && !replaying {
                record = CKRecord(recordType: write.recordType, recordID: recordID)
            } else {
                // Apply onto the server's current version. A replayed write is racing every other
                // device's edits, and saving a locally-built record would fail the etag check
                // instead of merging.
                do {
                    record = try await db.record(for: recordID)
                } catch let error as CKError where error.code == .unknownItem {
                    guard write.isNew else { throw error }
                    record = CKRecord(recordType: write.recordType, recordID: recordID)
                }
            }
            for (key, value) in write.fields { record[key] = value.recordValue }
            _ = try await db.save(record)
        }
    }

    /// Replays queued writes oldest-first, stopping at the first temporary failure — if the
    /// connection is down the rest will fail identically, and stopping keeps them in order.
    ///
    /// The queue is mutated entry by entry rather than swapped out at the end. Taking a copy and
    /// assigning it back would silently discard anything the user queued *during* the flush —
    /// the same lose-the-user's-expense bug this queue exists to fix.
    func flushPendingWrites() async {
        guard !isFlushing, !pendingWrites.isEmpty, database != nil, zoneID != nil else { return }
        isFlushing = true
        defer { isFlushing = false }

        var dropped = 0

        while let write = pendingWrites.min(by: { $0.queuedAt < $1.queuedAt }) {
            do {
                try await perform(write, replaying: true)
            } catch {
                if Self.isRetryable(error) { break }
                // CloudKit will never accept this one; retrying forever would just hide it.
                dropped += 1
            }

            // Only retire the entry if it's unchanged. An edit made while the request was in
            // flight merged into it and still needs sending.
            guard let idx = pendingWrites.firstIndex(where: { $0.id == write.id }),
                  pendingWrites[idx] == write else { continue }
            pendingWrites.remove(at: idx)
            LocalPersistence.savePendingWrites(pendingWrites)
        }

        if dropped > 0 {
            error = dropped == 1
                ? "One change couldn't be saved to iCloud and was discarded."
                : "\(dropped) changes couldn't be saved to iCloud and were discarded."
        }
    }

    /// Whether a failed write is worth keeping. Deliberately conservative: anything not listed
    /// counts as a permanent refusal, because a write CloudKit will never accept would otherwise
    /// sit in the queue being retried forever.
    private static func isRetryable(_ error: Error) -> Bool {
        if error is SyncError { return true }
        guard let ckError = error as? CKError else {
            return (error as NSError).domain == NSURLErrorDomain
        }
        switch ckError.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
             .zoneBusy, .notAuthenticated, .accountTemporarilyUnavailable, .internalError,
             // The next attempt fetches the server's version first, so a conflict resolves itself.
             .serverRecordChanged:
            return true
        case .partialFailure:
            return ckError.partialErrorsByItemID?.values.contains { isRetryable($0) } ?? false
        default:
            return false
        }
    }

    // MARK: - Row <-> record mapping

    private static func expense(from r: CKRecord) -> Expense? {
        guard
            let desc = r["desc"] as? String,
            let amount = r["amount"] as? Double,
            let category = r["category"] as? String,
            let paidBy = r["paidBy"] as? String,
            let splitRaw = r["split"] as? String,
            let split = SplitType(rawValue: splitRaw),
            let createdAt = r["createdAt"] as? Date
        else { return nil }
        return Expense(
            id: r.recordID.recordName,
            description: desc,
            amount: amount,
            category: category,
            paidBy: paidBy,
            split: split,
            forPerson: r["forPerson"] as? String,
            createdAt: createdAt
        )
    }

    private static func ask(from r: CKRecord) -> Ask? {
        guard
            let title = r["title"] as? String,
            let askedBy = r["askedBy"] as? String,
            let statusRaw = r["status"] as? String,
            let status = AskStatus(rawValue: statusRaw),
            let createdAt = r["createdAt"] as? Date
        else { return nil }
        return Ask(
            id: r.recordID.recordName,
            title: title,
            note: r["note"] as? String,
            askedBy: askedBy,
            assignedTo: r["assignedTo"] as? String,
            status: status,
            acceptedBy: r["acceptedBy"] as? String,
            createdAt: createdAt,
            completedAt: r["completedAt"] as? Date
        )
    }

    private static func bill(from r: CKRecord) -> Bill? {
        guard
            let title = r["title"] as? String,
            let amount = r["amount"] as? Double,
            let dueDay = r["dueDay"] as? Int,
            let createdAt = r["createdAt"] as? Date
        else { return nil }
        return Bill(
            id: r.recordID.recordName,
            title: title,
            amount: amount,
            dueDay: dueDay,
            paidBy: r["paidBy"] as? String,
            createdAt: createdAt
        )
    }

    private static func plan(from r: CKRecord) -> PlanEvent? {
        guard
            let owner = r["owner"] as? String,
            let start = r["start"] as? Date,
            let end = r["end"] as? Date,
            let createdAt = r["createdAt"] as? Date
        else { return nil }
        return PlanEvent(
            id: r.recordID.recordName,
            owner: owner,
            title: r["title"] as? String,
            start: start,
            end: end,
            isAllDay: (r["isAllDay"] as? Int64 ?? 0) == 1,
            isManual: (r["isManual"] as? Int64 ?? 0) == 1,
            invitees: (r["invitees"] as? [String]) ?? [],
            externalID: r["externalID"] as? String,
            createdAt: createdAt
        )
    }

    // MARK: - Household management

    func renameHousehold(_ newName: String) {
        flat?.name = newName
        commit(.save(HouseholdStore.householdRecordType, id: HouseholdStore.householdRecordName, isNew: false, fields: [
            "name": .string(newName)
        ]), describing: "The new flat name")
    }

    func saveRentSettings(amount: Double?, dueDay: Int?) {
        flat?.rentAmount = amount
        flat?.rentDueDay = dueDay
        commit(.save(HouseholdStore.householdRecordType, id: HouseholdStore.householdRecordName, isNew: false, fields: [
            "rentAmount": .double(amount),
            "rentDueDay": .int(dueDay)
        ]), describing: "The rent settings")
    }

    /// Removes a flatmate from the household. Their expenses and asks are left intact so the
    /// financial history stays honest — only their membership goes away.
    func removeMember(name: String) {
        guard let db = database, let zoneID = zoneID else { return }
        state.people.removeAll { $0 == name }
        Task {
            do {
                let records = try await fetchZoneRecords(db: db, zoneID: zoneID)
                let targets = records.filter { $0.recordType == HouseholdStore.memberRecordType && ($0["name"] as? String) == name }
                let ids = targets.map(\.recordID)
                guard !ids.isEmpty else { return }
                _ = try await db.modifyRecords(saving: [], deleting: ids)
                if name == myName {
                    UserDefaults.standard.removeObject(forKey: HouseholdStore.myMemberRecordKey)
                }

                // Also drop their CKShare access — without this, a "removed" flatmate keeps
                // zone access at the CloudKit level even though their Member record (and our
                // own UI) says they're gone.
                let householdID = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
                let household = try await db.record(for: householdID)
                if let shareRef = household.share,
                   let share = try await db.record(for: shareRef.recordID) as? CKShare,
                   let creatorID = targets.first?.creatorUserRecordID {
                    let participant = share.participants.first { $0.userIdentity.userRecordID == creatorID }
                    try await removeParticipantSafely(participant, from: share, db: db)
                }

                try await refreshAll()
            } catch {
                self.error = "Couldn't remove \(name): \(error.localizedDescription)"
            }
        }
    }

    /// Removes a participant from a share, guarding against a real crash risk: CloudKit raises
    /// an uncatchable Objective-C exception (not a Swift `Error` — `do`/`catch` cannot stop it)
    /// if you attempt to remove the share's owner. A state mismatch anywhere upstream (stale
    /// `isOwner`, wrong participant matched) would otherwise crash the app with no error message
    /// or log — exactly what happened here. This precondition is the only real defense.
    private func removeParticipantSafely(_ participant: CKShare.Participant?, from share: CKShare, db: CKDatabase) async throws {
        guard let participant, participant.role != .owner else { return }
        // `removeParticipant` also raises an uncatchable exception when the participant isn't
        // actually in the share's list. Everyone joins this app through the public link
        // (`publicPermission = .readWrite`), and a public participant is not in `participants` —
        // so the unguarded call crashed for essentially every flatmate who tried to leave.
        guard let identity = participant.userIdentity.userRecordID,
              share.participants.contains(where: { $0.userIdentity.userRecordID == identity })
        else { return }
        share.removeParticipant(participant)
        _ = try await db.modifyRecords(saving: [share], deleting: [])
    }

    /// Leaves the current household and returns to the create/join screen.
    ///
    /// Asymmetric by necessity: a regular member just removes their own Member record — the
    /// household keeps living in the owner's private database, unaffected. The owner *is* the
    /// data host, though, so there's no such thing as "the owner leaves but the flat survives";
    /// leaving means deleting the zone (and with it, the share and everyone's access).
    func leaveHousehold() async -> String? {
        guard let db = database, let zoneID = zoneID else {
            // No zone info at all (e.g. aborting from the name-entry screen before a share ever
            // fully resolved) — nothing server-side to clean up, just reset and bail.
            resetLocalState()
            return nil
        }
        // Leaving as a participant always succeeds locally. Every server-side step here is a
        // courtesy — releasing the share, tidying our Member record — and none of it is worth
        // trapping someone in a flat they've said they want out of. An owner is different: their
        // zone holds the household's data, so a failure there has to be reported, not swallowed.
        if !isOwner {
            if let recordName = UserDefaults.standard.string(forKey: HouseholdStore.myMemberRecordKey) {
                _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
            }
            let householdID = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
            if let household = try? await db.record(for: householdID),
               let shareRef = household.share,
               let share = try? await db.record(for: shareRef.recordID) as? CKShare {
                try? await removeParticipantSafely(share.currentUserParticipant, from: share, db: db)
            }
            HouseholdStore.markZoneLeft(zoneID)
            resetLocalState()
            return nil
        }

        do {
            if isOwner {
                _ = try await db.deleteRecordZone(withID: zoneID)
            }
            resetLocalState()
            return nil
        } catch {
            return "Couldn't leave: \(error.localizedDescription)"
        }
    }

    private func resetLocalState() {
        database = nil
        zoneID = nil
        isOwner = false
        flat = nil
        myName = nil
        state = HouseholdState()
        isStale = false
        // Drop the cache and any unsent writes too, so the next household never inherits the
        // previous one's rows.
        pendingWrites = []
        LocalPersistence.clear()
        UserDefaults.standard.removeObject(forKey: HouseholdStore.myMemberRecordKey)
        phase = .needsHousehold
    }

    /// Re-presents the existing invite share so more flatmates can be added later.
    func presentInvite() async {
        guard let db = database, let zoneID = zoneID else { return }
        do {
            let householdID = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
            let household = try await db.record(for: householdID)

            if let shareRef = household.share,
               let existingShare = try? await db.record(for: shareRef.recordID) as? CKShare {
                pendingShare = existingShare
                return
            }

            // No live share — either one was never created, or a previous one was stopped
            // (which permanently kills it; old links can't be revived, only replaced).
            let share = CKShare(rootRecord: household)
            share[CKShare.SystemFieldKey.title] = (flat?.name ?? (household["name"] as? String) ?? "Our flat") as CKRecordValue
            // Closed by default: the link is an address, not a key. Access comes from being an
            // explicit participant, added by iCloud identity in `inviteFlatmate`. With
            // `.readWrite` here the URL itself granted full access to anyone holding it —
            // permanently, and to anyone they forwarded it to — which made single-use invites
            // impossible and `removeMember` cosmetic, since an evicted flatmate just used the
            // old link again.
            share.publicPermission = .none
            _ = try await db.modifyRecords(saving: [household, share], deleting: [])
            pendingShare = share
        } catch {
            self.error = "Couldn't open the invite: \(error.localizedDescription)"
        }
    }

    /// Flatmates who are in the flat *only* because the link is open, and would therefore lose
    /// access the moment it closes.
    ///
    /// Someone who accepted an open link joins as a `.publicUser`, and that role's access comes
    /// from `publicPermission` rather than from being named on the share. CloudKit offers no way
    /// to promote them in place, so closing the link around them would silently evict people
    /// from a household they're already living in. Their names are surfaced instead, and the
    /// link stays open until the owner decides.
    func strandedByClosing(_ share: CKShare) -> [String] {
        share.participants
            .filter { $0.role == .publicUser }
            .compactMap { participant in
                let name = participant.userIdentity.nameComponents
                    .map { PersonNameComponentsFormatter().string(from: $0) }
                    .flatMap { $0.isEmpty ? nil : $0 }
                return name ?? participant.userIdentity.lookupInfo?.emailAddress ?? "a flatmate"
            }
    }

    /// Names of everyone still relying on the open link, for the flat's owner to act on.
    var flatmatesOnOpenLink: [String] {
        guard let share = pendingShare else { return [] }
        return strandedByClosing(share)
    }

    /// Invites one person by their iCloud identity, so the link works only for them.
    ///
    /// This is what makes an invite single-use: CloudKit binds access to the account behind the
    /// email or phone number, so forwarding the URL gets the next person nothing, and removing
    /// them later actually revokes it.
    func inviteFlatmate(contact rawContact: String) async -> String? {
        guard isOwner else { return "Only the person who created the flat can invite flatmates." }
        guard let db = database, let zoneID else { return "Still connecting to iCloud — try again in a moment." }
        let contact = rawContact.trimmed
        guard !contact.isEmpty else { return "Enter their email address or phone number." }

        do {
            let householdID = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
            let household = try await db.record(for: householdID)

            let share: CKShare
            if let shareRef = household.share,
               let existing = try? await db.record(for: shareRef.recordID) as? CKShare {
                share = existing
            } else {
                let fresh = CKShare(rootRecord: household)
                fresh[CKShare.SystemFieldKey.title] = (flat?.name ?? "Our flat") as CKRecordValue
                fresh.publicPermission = .none
                _ = try await db.modifyRecords(saving: [household, fresh], deleting: [])
                share = fresh
            }

            let participant: CKShare.Participant
            do {
                participant = contact.contains("@")
                    ? try await container.shareParticipant(forEmailAddress: contact)
                    : try await container.shareParticipant(forPhoneNumber: contact)
            } catch {
                return "No iCloud account uses \(contact). Ask them which address or number their Apple Account is under — it has to be one Apple can find them by."
            }

            // `addParticipant` raises an uncatchable exception on someone already on the share,
            // so an accidental second invite has to be caught here rather than trapped.
            if let existingID = participant.userIdentity.userRecordID,
               share.participants.contains(where: { $0.userIdentity.userRecordID == existingID }) {
                pendingShare = share
                return nil
            }

            participant.permission = .readWrite
            share.addParticipant(participant)
            // Deliberately does *not* close an already-open link. Someone the owner sent it to
            // who hasn't accepted yet is invisible here — `share.participants` only lists people
            // who already joined — so closing it as a side effect would break an invite that's
            // still in flight. Flats created from now on start closed; an existing one is closed
            // only when the owner says so, via `closeOpenInviteLink`.
            _ = try await db.modifyRecords(saving: [share], deleting: [])
            pendingShare = share
            return nil
        } catch {
            return "Couldn't send that invite: \(error.localizedDescription)"
        }
    }

    /// Closes an already-open invite link, accepting that anyone still on it has to be
    /// re-invited by name. Owner's call, never automatic.
    func closeOpenInviteLink() async -> String? {
        guard isOwner, let db = database, let zoneID else { return "Only the flat's owner can do that." }
        do {
            let householdID = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
            let household = try await db.record(for: householdID)
            guard let shareRef = household.share,
                  let share = try? await db.record(for: shareRef.recordID) as? CKShare else {
                return "There's no invite link to close."
            }
            share.publicPermission = .none
            _ = try await db.modifyRecords(saving: [share], deleting: [])
            pendingShare = share
            try? await refreshAll()
            return nil
        } catch {
            return "Couldn't close the link: \(error.localizedDescription)"
        }
    }

    /// Accepts a share by fetching and accepting its metadata directly, instead of relying on
    /// the OS's tap-a-link flow — that flow checks the app's availability on the public App
    /// Store before it will hand off to us, which fails for a TestFlight-only build even when
    /// the app is already installed and up to date on both ends.
    func acceptInvite(pastedText: String) async -> String? {
        let text = pastedText.trimmed
        guard !text.isEmpty else { return "Paste the invite link first." }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        let match = detector?.firstMatch(in: text, range: range)
        guard let url = match?.url ?? URL(string: text) else {
            return "That doesn't look like a valid invite link."
        }

        do {
            let metadata = try await container.shareMetadata(for: url)
            _ = try await container.accept(metadata)
            await handleAcceptedShare(metadata: metadata)
            return nil
        } catch let error as CKError where
                    error.code == .participantMayNeedVerification
                    || error.code == .permissionFailure
                    || error.code == .unknownItem {
            // Invites are now bound to the iCloud account they were sent to, so a link that
            // reached the wrong account — forwarded, or sent to a different address than the one
            // this device signs in with — fails here rather than letting anyone in.
            return "This invite wasn't sent to your iCloud account. Ask them to invite the email address or phone number your Apple Account uses."
        } catch {
            return "Couldn't join: \(error.localizedDescription)"
        }
    }

    // MARK: - Writes: bills

    func addBill(title: String, amount: Double, dueDay: Int, paidBy: String?) {
        let id = makeId()
        let createdAt = Date()
        state.bills.append(Bill(id: id, title: title, amount: amount, dueDay: dueDay, paidBy: paidBy, createdAt: createdAt))
        state.bills.sort { $0.dueDay < $1.dueDay }

        commit(.save(HouseholdStore.billRecordType, id: id, isNew: true, fields: [
            "title": .string(title),
            "amount": .double(amount),
            "dueDay": .int(dueDay),
            "paidBy": .string(paidBy),
            "createdAt": .date(createdAt)
        ]), describing: "That bill")
    }

    func deleteBill(id: String) {
        state.bills.removeAll { $0.id == id }
        commit(.delete(HouseholdStore.billRecordType, id: id), describing: "That deleted bill")
    }

    // MARK: - Writes: plans

    func addPlan(title: String?, start: Date, end: Date, isAllDay: Bool, invitees: [String]) {
        guard let owner = myName else { return }
        let id = makeId()
        let createdAt = Date()
        state.plans.append(PlanEvent(id: id, owner: owner, title: title, start: start, end: end, isAllDay: isAllDay, isManual: true, invitees: invitees, externalID: nil, createdAt: createdAt))
        state.plans.sort { $0.start < $1.start }

        commit(.save(HouseholdStore.planRecordType, id: id, isNew: true, fields: [
            "owner": .string(owner),
            "title": .string(title),
            "start": .date(start),
            "end": .date(end),
            "isAllDay": .bool(isAllDay),
            "isManual": .bool(true),
            "invitees": .stringList(invitees),
            "createdAt": .date(createdAt)
        ]), describing: "That plan")
    }

    func deletePlan(id: String) {
        state.plans.removeAll { $0.id == id }
        commit(.delete(HouseholdStore.planRecordType, id: id), describing: "That deleted plan")
    }

    /// Owner-only, and manual plans only — a calendar-imported block gets overwritten by the
    /// next sync anyway, so hand-editing it would just be undone.
    func updatePlan(id: String, title: String?, start: Date, end: Date, invitees: [String]) {
        if let idx = state.plans.firstIndex(where: { $0.id == id }) {
            state.plans[idx].title = title
            state.plans[idx].start = start
            state.plans[idx].end = end
            state.plans[idx].invitees = invitees
            state.plans.sort { $0.start < $1.start }
        }
        commit(.save(HouseholdStore.planRecordType, id: id, isNew: false, fields: [
            "title": .string(title),
            "start": .date(start),
            "end": .date(end),
            "invitees": .stringList(invitees)
        ]), describing: "That plan edit")
    }

    /// Publishes busy blocks imported from this device's calendar.
    ///
    /// Only start/end times leave the device by default. A title is included only for entries
    /// whose `externalID` the owner explicitly opted into sharing.
    func syncCalendarBlocks(_ blocks: [(externalID: String, title: String, start: Date, end: Date, isAllDay: Bool)], sharedTitleIDs: Set<String>) async {
        guard let db = database, let zoneID = zoneID, let owner = myName else { return }

        let existing = state.plans.filter { $0.owner == owner && !$0.isManual }
        var existingByExternalID: [String: PlanEvent] = [:]
        for plan in existing {
            if let ext = plan.externalID { existingByExternalID[ext] = plan }
        }

        var toSave: [CKRecord] = []
        for block in blocks {
            let shareTitle = sharedTitleIDs.contains(block.externalID)
            let recordName = existingByExternalID[block.externalID]?.id ?? makeId()
            let record = CKRecord(recordType: HouseholdStore.planRecordType, recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
            record["owner"] = owner as CKRecordValue
            if shareTitle { record["title"] = block.title as CKRecordValue }
            record["start"] = block.start as CKRecordValue
            record["end"] = block.end as CKRecordValue
            record["isAllDay"] = (block.isAllDay ? 1 : 0) as CKRecordValue
            record["isManual"] = 0 as CKRecordValue
            record["externalID"] = block.externalID as CKRecordValue
            record["createdAt"] = Date() as CKRecordValue
            toSave.append(record)
        }

        // Drop blocks whose source event is gone from the calendar.
        let liveIDs = Set(blocks.map(\.externalID))
        let staleIDs = existing
            .filter { plan in plan.externalID.map { !liveIDs.contains($0) } ?? true }
            .map { CKRecord.ID(recordName: $0.id, zoneID: zoneID) }

        do {
            _ = try await db.modifyRecords(saving: toSave, deleting: staleIDs, savePolicy: .allKeys)
            try await refreshAll()
        } catch {
            self.error = "Calendar sync failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Writes: expenses

    func addExpense(description: String, amount: Double, category: String, paidBy: String, split: SplitType, forPerson: String?, date: Date = Date()) {
        let id = makeId()
        let createdAt = date
        let full = Expense(id: id, description: description, amount: amount, category: category, paidBy: paidBy, split: split, forPerson: forPerson, createdAt: createdAt)
        state.expenses.insert(full, at: 0)

        commit(.save(HouseholdStore.expenseRecordType, id: id, isNew: true, fields: [
            "desc": .string(description),
            "amount": .double(amount),
            "category": .string(category),
            "paidBy": .string(paidBy),
            "split": .string(split.rawValue),
            "forPerson": .string(forPerson),
            "createdAt": .date(createdAt)
        ]), describing: "That expense")
    }

    func deleteExpense(id: String) {
        state.expenses.removeAll { $0.id == id }
        commit(.delete(HouseholdStore.expenseRecordType, id: id), describing: "That deleted expense")
    }

    /// paidBy is fixed on edit — it's also the edit permission gate, and reassigning who paid
    /// after the fact is more likely a mistake than an intent.
    func updateExpense(id: String, description: String, amount: Double, category: String, split: SplitType, forPerson: String?, date: Date) {
        if let idx = state.expenses.firstIndex(where: { $0.id == id }) {
            state.expenses[idx].description = description
            state.expenses[idx].amount = amount
            state.expenses[idx].category = category
            state.expenses[idx].split = split
            state.expenses[idx].forPerson = forPerson
            state.expenses[idx].createdAt = date
            state.expenses.sort { $0.createdAt > $1.createdAt }
        }
        commit(.save(HouseholdStore.expenseRecordType, id: id, isNew: false, fields: [
            "desc": .string(description),
            "amount": .double(amount),
            "category": .string(category),
            "split": .string(split.rawValue),
            "forPerson": .string(forPerson),
            "createdAt": .date(date)
        ]), describing: "That expense edit")
    }

    func recordSettlement(from: String, to: String, amount: Double) {
        addExpense(description: "\(from) paid back \(to)", amount: amount, category: SETTLE_UP_CATEGORY, paidBy: from, split: .full, forPerson: to)
    }

    // MARK: - Writes: asks

    func addAsk(title: String, note: String?, askedBy: String, assignedTo: String?) {
        let id = makeId()
        let createdAt = Date()
        let full = Ask(id: id, title: title, note: note, askedBy: askedBy, assignedTo: assignedTo, status: .open, acceptedBy: nil, createdAt: createdAt, completedAt: nil)
        state.asks.insert(full, at: 0)

        commit(.save(HouseholdStore.askRecordType, id: id, isNew: true, fields: [
            "title": .string(title),
            "note": .string(note),
            "askedBy": .string(askedBy),
            "assignedTo": .string(assignedTo),
            "status": .string(AskStatus.open.rawValue),
            "createdAt": .date(createdAt)
        ]), describing: "That ask")
    }

    private func patchAsk(id: String, apply: (inout Ask) -> Void, fields: [String: FieldValue]) {
        if let idx = state.asks.firstIndex(where: { $0.id == id }) {
            apply(&state.asks[idx])
        }
        commit(.save(HouseholdStore.askRecordType, id: id, isNew: false, fields: fields), describing: "That ask update")
    }

    /// askedBy is fixed on edit — it's the edit permission gate.
    func updateAsk(id: String, title: String, note: String?, assignedTo: String?) {
        patchAsk(id: id, apply: { $0.title = title; $0.note = note; $0.assignedTo = assignedTo }, fields: [
            "title": .string(title),
            "note": .string(note),
            "assignedTo": .string(assignedTo)
        ])
    }

    func acceptAsk(id: String, by: String) {
        patchAsk(id: id, apply: { $0.status = .accepted; $0.acceptedBy = by }, fields: [
            "status": .string(AskStatus.accepted.rawValue),
            "acceptedBy": .string(by)
        ])
    }

    func completeAsk(id: String) {
        let completedAt = Date()
        patchAsk(id: id, apply: { $0.status = .done; $0.completedAt = completedAt }, fields: [
            "status": .string(AskStatus.done.rawValue),
            "completedAt": .date(completedAt)
        ])
    }

    func deleteAsk(id: String) {
        state.asks.removeAll { $0.id == id }
        commit(.delete(HouseholdStore.askRecordType, id: id), describing: "That deleted ask")
    }
}
