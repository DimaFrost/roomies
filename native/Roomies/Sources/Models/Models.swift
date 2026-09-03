import Foundation

enum SplitType: String, Codable {
    case even
    case full
}

struct Expense: Identifiable, Codable, Equatable {
    var id: String
    var description: String
    var amount: Double
    var category: String
    var paidBy: String
    var split: SplitType
    /// Who owes the full amount when split is `.full`.
    var forPerson: String?
    var createdAt: Date
}

enum AskStatus: String, Codable {
    case open
    case accepted
    case done
}

struct Ask: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var note: String?
    var askedBy: String
    /// Specific flatmate the ask is directed at; nil = anyone.
    var assignedTo: String?
    var status: AskStatus
    var acceptedBy: String?
    var createdAt: Date
    var completedAt: Date?
}

struct HouseholdState: Codable, Equatable {
    var people: [String] = []
    var expenses: [Expense] = []
    var asks: [Ask] = []
    var bills: [Bill] = []
    var plans: [PlanEvent] = []
}

struct FlatInfo: Codable, Equatable {
    var name: String
    /// iCloud share URL flatmates use to join.
    var shareURL: URL?
    /// Household "ground truth" — the shared facts everyone should agree on.
    var rentAmount: Double?
    /// Day of month rent is due (1–31).
    var rentDueDay: Int?
}

/// A recurring shared cost (utilities, internet, …) that isn't a one-off expense.
struct Bill: Identifiable, Codable, Equatable {
    var id: String
    var title: String
    var amount: Double
    /// Day of month it's due (1–31).
    var dueDay: Int
    var paidBy: String?
    var createdAt: Date
}

/// A block of time a flatmate is busy or away.
///
/// Privacy model: `title` is nil unless its owner explicitly chose to share it, so imported
/// calendar entries publish only *when* someone is unavailable, never what they're doing.
struct PlanEvent: Identifiable, Codable, Equatable {
    var id: String
    var owner: String
    var title: String?
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// Entered by hand in Roomies rather than imported from the phone's calendar.
    var isManual: Bool
    /// Flatmates explicitly invited along — manual events only.
    var invitees: [String]
    /// Identifier of the originating EKEvent, so re-syncing updates instead of duplicating.
    var externalID: String?
    var createdAt: Date
}

let SETTLE_UP_CATEGORY = "🤝 Settle-up"
