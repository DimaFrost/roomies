import Foundation
import CloudKit

// MARK: - Field values

/// The CKRecord field types this app actually writes, in a form that survives being written to
/// disk. `CKRecordValue` is an Objective-C protocol and isn't `Codable`, so a queued write can't
/// hold one directly.
enum FieldValue: Codable, Equatable {
    case string(String)
    case double(Double)
    case int(Int)
    case date(Date)
    case stringList([String])
    /// An explicitly cleared field — distinct from "not part of this write".
    case null

    var recordValue: CKRecordValue? {
        switch self {
        case .string(let v): return v as CKRecordValue
        case .double(let v): return v as CKRecordValue
        case .int(let v): return v as CKRecordValue
        case .date(let v): return v as CKRecordValue
        case .stringList(let v): return v.isEmpty ? nil : (v as CKRecordValue)
        case .null: return nil
        }
    }
}

extension FieldValue {
    /// Optional-aware constructors, so call sites read like the direct `record[key] = value`
    /// assignments they replace rather than sprouting `if let` around every nullable field.
    static func string(_ v: String?) -> FieldValue { v.map { FieldValue.string($0) } ?? .null }
    static func double(_ v: Double?) -> FieldValue { v.map { FieldValue.double($0) } ?? .null }
    static func int(_ v: Int?) -> FieldValue { v.map { FieldValue.int($0) } ?? .null }
    static func bool(_ v: Bool) -> FieldValue { .int(v ? 1 : 0) }
}

// MARK: - Pending writes

/// A CloudKit mutation that hasn't reached the server yet.
///
/// The queue exists because the previous behaviour on a failed save was to delete the row the
/// user had just created — on a money-tracking app, over a flaky connection. A write now stays
/// on the device until CloudKit accepts it or permanently refuses it.
struct PendingWrite: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case save, delete }

    /// The record's name, which is also this queue's key: at most one pending write per record.
    var id: String
    var kind: Kind
    var recordType: String
    var fields: [String: FieldValue]
    /// True when this write created the record, so a replay knows to recreate it if the server
    /// never received it. Cleared once the record is known to exist server-side.
    var isNew: Bool
    var queuedAt: Date

    static func save(_ recordType: String, id: String, isNew: Bool, fields: [String: FieldValue]) -> PendingWrite {
        PendingWrite(id: id, kind: .save, recordType: recordType, fields: fields, isNew: isNew, queuedAt: Date())
    }

    static func delete(_ recordType: String, id: String) -> PendingWrite {
        PendingWrite(id: id, kind: .delete, recordType: recordType, fields: [:], isNew: false, queuedAt: Date())
    }

    /// Folds a newer write for the same record into this one, so editing the same expense five
    /// times offline replays as one save rather than five.
    func merging(_ newer: PendingWrite) -> PendingWrite {
        switch newer.kind {
        case .delete:
            // Deleting a record the server never received is a no-op there, and CloudKit reports
            // that as `.unknownItem`, which the replay treats as success.
            var result = newer
            result.queuedAt = queuedAt
            return result
        case .save:
            var result = newer
            result.fields = fields.merging(newer.fields) { _, new in new }
            // A create that hasn't landed yet is still a create, however many edits follow it.
            result.isNew = isNew || newer.isNew
            result.queuedAt = queuedAt
            return result
        }
    }
}

// MARK: - Offline snapshot

/// The last state known to have come from the server, kept so launching without a connection
/// shows the flat as it was rather than an error screen.
struct CachedSnapshot: Codable {
    var state: HouseholdState
    var flat: FlatInfo?
    var myName: String?
    var isOwner: Bool
    /// The household zone, recorded so writes can still be composed and queued offline —
    /// discovering it normally costs a `allRecordZones()` round trip.
    var zoneName: String
    var zoneOwnerName: String
    var savedAt: Date

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: zoneOwnerName)
    }
}

// MARK: - Disk

/// Reads and writes the offline snapshot and the pending-write queue.
///
/// Both live in Application Support as plain JSON. Failures here are deliberately silent: losing
/// a cache is a degraded experience, not a reason to interrupt someone adding an expense.
enum LocalPersistence {
    private static let snapshotFile = "snapshot.json"
    private static let queueFile = "pending-writes.json"

    private static var directory: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let dir = base.appendingPathComponent("AtOurPlace", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func read<T: Decodable>(_ file: String, as type: T.Type) -> T? {
        guard let url = directory?.appendingPathComponent(file),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func write<T: Encodable>(_ value: T, to file: String) {
        guard let url = directory?.appendingPathComponent(file),
              let data = try? JSONEncoder().encode(value) else { return }
        // Atomic, so a crash mid-write can't leave a half-file that fails to decode on launch.
        try? data.write(to: url, options: .atomic)
    }

    private static func remove(_ file: String) {
        guard let url = directory?.appendingPathComponent(file) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func loadSnapshot() -> CachedSnapshot? { read(snapshotFile, as: CachedSnapshot.self) }
    static func saveSnapshot(_ snapshot: CachedSnapshot) { write(snapshot, to: snapshotFile) }

    static func loadPendingWrites() -> [PendingWrite] { read(queueFile, as: [PendingWrite].self) ?? [] }
    static func savePendingWrites(_ writes: [PendingWrite]) { write(writes, to: queueFile) }

    /// Wipes everything local — used when leaving a flat, so the next household never inherits
    /// the previous one's cached rows or unsent writes.
    static func clear() {
        remove(snapshotFile)
        remove(queueFile)
    }
}
