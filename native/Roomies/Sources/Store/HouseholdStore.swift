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

    private let container = CKContainer(identifier: "iCloud.com.madebyfrost.roomies")
    private var database: CKDatabase?
    private var zoneID: CKRecordZone.ID?
    private(set) var isOwner = false
    private var myUserRecordID: CKRecord.ID?
    private var subscriptionRegistered = false

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

    init() {
        HouseholdStore.current = self
    }

    // MARK: - Bootstrap

    func bootstrap() async {
        phase = .loading
        error = nil
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
            try await refreshAll()
        } catch {
            self.error = error.localizedDescription
            phase = .error
        }
    }

    private func findZone(in db: CKDatabase) async throws -> CKRecordZone.ID? {
        let zones = try await db.allRecordZones()
        return zones.first(where: { $0.zoneID.zoneName == HouseholdStore.zoneName })?.zoneID
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
            // .readWrite because whoever has the link *is* the invite — there's no separate
            // per-participant permission step anymore now that we accept shares ourselves via
            // shareMetadata(for:)/accept(_:) instead of UICloudSharingController's own UI (which
            // used to grant write access through its own flow regardless of this property).
            // Leaving this at .none — the default before that removal — silently limited every
            // link-based joiner to no write access, so their first save (their own Member
            // record) failed with "Create operation not permitted."
            share.publicPermission = .readWrite

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
        try? await refreshAll()
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
        guard let db = database, let zoneID = zoneID else { return }
        flat?.name = newName
        Task {
            do {
                let id = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
                let record = try await db.record(for: id)
                record["name"] = newName as CKRecordValue
                _ = try await db.save(record)
            } catch {
                self.error = "Rename didn't sync: \(error.localizedDescription)"
            }
        }
    }

    func saveRentSettings(amount: Double?, dueDay: Int?) {
        guard let db = database, let zoneID = zoneID else { return }
        flat?.rentAmount = amount
        flat?.rentDueDay = dueDay
        Task {
            do {
                let id = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
                let record = try await db.record(for: id)
                record["rentAmount"] = amount as? CKRecordValue
                record["rentDueDay"] = dueDay as? CKRecordValue
                _ = try await db.save(record)
            } catch {
                self.error = "Rent settings didn't sync: \(error.localizedDescription)"
            }
        }
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
        do {
            if isOwner {
                _ = try await db.deleteRecordZone(withID: zoneID)
            } else {
                // Best-effort: remove our Member record if we ever got one. Not fatal if this
                // fails or there isn't one (e.g. leaving from the stuck-at-name-entry state).
                if let recordName = UserDefaults.standard.string(forKey: HouseholdStore.myMemberRecordKey) {
                    _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: recordName, zoneID: zoneID))
                }
                // A participant can't delete the owner's zone — CloudKit rightly refuses that,
                // it would let any invited guest destroy the whole household's data. The actual
                // way to leave is removing our own entry from the share's participant list;
                // CloudKit specifically permits self-removal even without general write access
                // to the share record. This is what makes it stick across relaunches — without
                // it, bootstrap() just re-discovers the same shared zone next launch.
                let householdID = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
                let household = try await db.record(for: householdID)
                if let shareRef = household.share,
                   let share = try await db.record(for: shareRef.recordID) as? CKShare {
                    try await removeParticipantSafely(share.currentUserParticipant, from: share, db: db)
                }
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
        UserDefaults.standard.removeObject(forKey: HouseholdStore.myMemberRecordKey)
        phase = .needsHousehold
    }

    /// Re-presents the existing invite share so more flatmates can be added later.
    func presentInvite() async {
        guard let db = database, let zoneID = zoneID else { return }
        do {
            let householdID = CKRecord.ID(recordName: HouseholdStore.householdRecordName, zoneID: zoneID)
            let household = try await db.record(for: householdID)

            // Re-open the live share if there is one — self-healing the permission if this
            // share predates the .readWrite fix, so an old broken invite gets fixed by simply
            // opening it again rather than needing Stop Sharing + a whole new link.
            if let shareRef = household.share,
               let existingShare = try? await db.record(for: shareRef.recordID) as? CKShare {
                if existingShare.publicPermission != .readWrite {
                    existingShare.publicPermission = .readWrite
                    _ = try? await db.modifyRecords(saving: [existingShare], deleting: [])
                }
                pendingShare = existingShare
                return
            }

            // No live share — either one was never created, or a previous one was stopped
            // (which permanently kills it; old links can't be revived, only replaced).
            let share = CKShare(rootRecord: household)
            share[CKShare.SystemFieldKey.title] = (flat?.name ?? (household["name"] as? String) ?? "Our flat") as CKRecordValue
            // .readWrite because whoever has the link *is* the invite — there's no separate
            // per-participant permission step anymore now that we accept shares ourselves via
            // shareMetadata(for:)/accept(_:) instead of UICloudSharingController's own UI (which
            // used to grant write access through its own flow regardless of this property).
            // Leaving this at .none — the default before that removal — silently limited every
            // link-based joiner to no write access, so their first save (their own Member
            // record) failed with "Create operation not permitted."
            share.publicPermission = .readWrite
            _ = try await db.modifyRecords(saving: [household, share], deleting: [])
            pendingShare = share
        } catch {
            self.error = "Couldn't open the invite: \(error.localizedDescription)"
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
        } catch {
            return "Couldn't join: \(error.localizedDescription)"
        }
    }

    // MARK: - Writes: bills

    func addBill(title: String, amount: Double, dueDay: Int, paidBy: String?) {
        guard let db = database, let zoneID = zoneID else { return }
        let id = makeId()
        let createdAt = Date()
        state.bills.append(Bill(id: id, title: title, amount: amount, dueDay: dueDay, paidBy: paidBy, createdAt: createdAt))
        state.bills.sort { $0.dueDay < $1.dueDay }

        let record = CKRecord(recordType: HouseholdStore.billRecordType, recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
        record["title"] = title as CKRecordValue
        record["amount"] = amount as CKRecordValue
        record["dueDay"] = dueDay as CKRecordValue
        if let paidBy { record["paidBy"] = paidBy as CKRecordValue }
        record["createdAt"] = createdAt as CKRecordValue

        Task {
            do {
                _ = try await db.save(record)
            } catch {
                self.error = "Bill didn't sync: \(error.localizedDescription)"
                state.bills.removeAll { $0.id == id }
            }
        }
    }

    func deleteBill(id: String) {
        guard let db = database, let zoneID = zoneID else { return }
        state.bills.removeAll { $0.id == id }
        Task {
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: id, zoneID: zoneID))
        }
    }

    // MARK: - Writes: plans

    func addPlan(title: String?, start: Date, end: Date, isAllDay: Bool, invitees: [String]) {
        guard let db = database, let zoneID = zoneID, let owner = myName else { return }
        let id = makeId()
        let createdAt = Date()
        state.plans.append(PlanEvent(id: id, owner: owner, title: title, start: start, end: end, isAllDay: isAllDay, isManual: true, invitees: invitees, externalID: nil, createdAt: createdAt))
        state.plans.sort { $0.start < $1.start }

        let record = CKRecord(recordType: HouseholdStore.planRecordType, recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
        record["owner"] = owner as CKRecordValue
        if let title { record["title"] = title as CKRecordValue }
        record["start"] = start as CKRecordValue
        record["end"] = end as CKRecordValue
        record["isAllDay"] = (isAllDay ? 1 : 0) as CKRecordValue
        record["isManual"] = 1 as CKRecordValue
        if !invitees.isEmpty { record["invitees"] = invitees as CKRecordValue }
        record["createdAt"] = createdAt as CKRecordValue

        Task {
            do {
                _ = try await db.save(record)
            } catch {
                self.error = "Plan didn't sync: \(error.localizedDescription)"
                state.plans.removeAll { $0.id == id }
            }
        }
    }

    func deletePlan(id: String) {
        guard let db = database, let zoneID = zoneID else { return }
        state.plans.removeAll { $0.id == id }
        Task {
            _ = try? await db.deleteRecord(withID: CKRecord.ID(recordName: id, zoneID: zoneID))
        }
    }

    /// Owner-only, and manual plans only — a calendar-imported block gets overwritten by the
    /// next sync anyway, so hand-editing it would just be undone.
    func updatePlan(id: String, title: String?, start: Date, end: Date, invitees: [String]) {
        guard let db = database, let zoneID = zoneID else { return }
        if let idx = state.plans.firstIndex(where: { $0.id == id }) {
            state.plans[idx].title = title
            state.plans[idx].start = start
            state.plans[idx].end = end
            state.plans[idx].invitees = invitees
            state.plans.sort { $0.start < $1.start }
        }
        Task {
            do {
                let record = try await db.record(for: CKRecord.ID(recordName: id, zoneID: zoneID))
                record["title"] = title.map { $0 as CKRecordValue }
                record["start"] = start as CKRecordValue
                record["end"] = end as CKRecordValue
                record["invitees"] = invitees.isEmpty ? nil : (invitees as CKRecordValue)
                _ = try await db.save(record)
            } catch {
                self.error = "Edit didn't sync: \(error.localizedDescription)"
                try? await refreshAll()
            }
        }
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
        guard let db = database, let zoneID = zoneID else { return }
        let id = makeId()
        let createdAt = date
        let full = Expense(id: id, description: description, amount: amount, category: category, paidBy: paidBy, split: split, forPerson: forPerson, createdAt: createdAt)
        state.expenses.insert(full, at: 0)

        let record = CKRecord(recordType: HouseholdStore.expenseRecordType, recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
        record["desc"] = description as CKRecordValue
        record["amount"] = amount as CKRecordValue
        record["category"] = category as CKRecordValue
        record["paidBy"] = paidBy as CKRecordValue
        record["split"] = split.rawValue as CKRecordValue
        if let forPerson { record["forPerson"] = forPerson as CKRecordValue }
        record["createdAt"] = createdAt as CKRecordValue

        Task {
            do {
                _ = try await db.save(record)
            } catch {
                self.error = "Expense didn't sync: \(error.localizedDescription)"
                state.expenses.removeAll { $0.id == id }
            }
        }
    }

    func deleteExpense(id: String) {
        guard let db = database, let zoneID = zoneID else { return }
        state.expenses.removeAll { $0.id == id }
        Task {
            do {
                _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: id, zoneID: zoneID))
            } catch {
                self.error = "Delete didn't sync: \(error.localizedDescription)"
            }
        }
    }

    /// paidBy is fixed on edit — it's also the edit permission gate, and reassigning who paid
    /// after the fact is more likely a mistake than an intent.
    func updateExpense(id: String, description: String, amount: Double, category: String, split: SplitType, forPerson: String?, date: Date) {
        guard let db = database, let zoneID = zoneID else { return }
        if let idx = state.expenses.firstIndex(where: { $0.id == id }) {
            state.expenses[idx].description = description
            state.expenses[idx].amount = amount
            state.expenses[idx].category = category
            state.expenses[idx].split = split
            state.expenses[idx].forPerson = forPerson
            state.expenses[idx].createdAt = date
            state.expenses.sort { $0.createdAt > $1.createdAt }
        }
        Task {
            do {
                let record = try await db.record(for: CKRecord.ID(recordName: id, zoneID: zoneID))
                record["desc"] = description as CKRecordValue
                record["amount"] = amount as CKRecordValue
                record["category"] = category as CKRecordValue
                record["split"] = split.rawValue as CKRecordValue
                record["forPerson"] = forPerson.map { $0 as CKRecordValue }
                record["createdAt"] = date as CKRecordValue
                _ = try await db.save(record)
            } catch {
                self.error = "Edit didn't sync: \(error.localizedDescription)"
                try? await refreshAll()
            }
        }
    }

    func recordSettlement(from: String, to: String, amount: Double) {
        addExpense(description: "\(from) paid back \(to)", amount: amount, category: SETTLE_UP_CATEGORY, paidBy: from, split: .full, forPerson: to)
    }

    // MARK: - Writes: asks

    func addAsk(title: String, note: String?, askedBy: String, assignedTo: String?) {
        guard let db = database, let zoneID = zoneID else { return }
        let id = makeId()
        let createdAt = Date()
        let full = Ask(id: id, title: title, note: note, askedBy: askedBy, assignedTo: assignedTo, status: .open, acceptedBy: nil, createdAt: createdAt, completedAt: nil)
        state.asks.insert(full, at: 0)

        let record = CKRecord(recordType: HouseholdStore.askRecordType, recordID: CKRecord.ID(recordName: id, zoneID: zoneID))
        record["title"] = title as CKRecordValue
        if let note { record["note"] = note as CKRecordValue }
        record["askedBy"] = askedBy as CKRecordValue
        if let assignedTo { record["assignedTo"] = assignedTo as CKRecordValue }
        record["status"] = AskStatus.open.rawValue as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue

        Task {
            do {
                _ = try await db.save(record)
            } catch {
                self.error = "Ask didn't sync: \(error.localizedDescription)"
                state.asks.removeAll { $0.id == id }
            }
        }
    }

    private func patchAsk(id: String, apply: @escaping (inout Ask) -> Void, recordPatch: @escaping (CKRecord) -> Void) {
        guard let db = database, let zoneID = zoneID else { return }
        if let idx = state.asks.firstIndex(where: { $0.id == id }) {
            apply(&state.asks[idx])
        }
        Task {
            do {
                let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
                let record = try await db.record(for: recordID)
                recordPatch(record)
                _ = try await db.save(record)
            } catch {
                self.error = "Update didn't sync: \(error.localizedDescription)"
            }
        }
    }

    /// askedBy is fixed on edit — it's the edit permission gate.
    func updateAsk(id: String, title: String, note: String?, assignedTo: String?) {
        patchAsk(id: id, apply: { $0.title = title; $0.note = note; $0.assignedTo = assignedTo }, recordPatch: { r in
            r["title"] = title as CKRecordValue
            r["note"] = note.map { $0 as CKRecordValue }
            r["assignedTo"] = assignedTo.map { $0 as CKRecordValue }
        })
    }

    func acceptAsk(id: String, by: String) {
        patchAsk(id: id, apply: { $0.status = .accepted; $0.acceptedBy = by }, recordPatch: { r in
            r["status"] = AskStatus.accepted.rawValue as CKRecordValue
            r["acceptedBy"] = by as CKRecordValue
        })
    }

    func completeAsk(id: String) {
        let completedAt = Date()
        patchAsk(id: id, apply: { $0.status = .done; $0.completedAt = completedAt }, recordPatch: { r in
            r["status"] = AskStatus.done.rawValue as CKRecordValue
            r["completedAt"] = completedAt as CKRecordValue
        })
    }

    func deleteAsk(id: String) {
        guard let db = database, let zoneID = zoneID else { return }
        state.asks.removeAll { $0.id == id }
        Task {
            do {
                _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: id, zoneID: zoneID))
            } catch {
                self.error = "Delete didn't sync: \(error.localizedDescription)"
            }
        }
    }
}
