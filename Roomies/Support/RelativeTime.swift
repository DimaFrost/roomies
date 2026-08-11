import Foundation

enum RelativeTime {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()

    /// Short, glanceable age: "just now", "12m ago", "yesterday", then a date.
    static func string(for date: Date?, now: Date = .now) -> String {
        guard let date else { return "" }

        let seconds = Int(now.timeIntervalSince(date))
        guard seconds >= 0 else { return "just now" }
        if seconds < 60 { return "just now" }

        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }

        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }

        let days = hours / 24
        if days == 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }

        return dateFormatter.string(from: date)
    }
}

extension Double {
    /// Amounts are always shown in euros with two decimals, matching the original.
    var euros: String { String(format: "€%.2f", self) }
}
