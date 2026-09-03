import Foundation
import EventKit

/// Reads the phone's calendar locally. Nothing here is ever uploaded directly — the store
/// decides what (if anything) to publish, and by default that's busy times without titles.
@MainActor
final class CalendarService: ObservableObject {
    enum Access: Equatable {
        case unknown
        case granted
        case denied
    }

    @Published var access: Access = .unknown

    private let eventStore = EKEventStore()

    func refreshAuthorizationStatus() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
        case .denied, .restricted, .writeOnly:
            access = .denied
        case .notDetermined:
            access = .unknown
        @unknown default:
            access = .unknown
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            access = granted ? .granted : .denied
            return granted
        } catch {
            access = .denied
            return false
        }
    }

    /// Events between now and `daysAhead` days out, across every calendar on the device.
    func upcomingEvents(daysAhead: Int = 60) -> [EKEvent] {
        guard access == .granted else { return [] }
        let start = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: daysAhead, to: start) else { return [] }
        let predicate = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
        return eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }
    }
}
