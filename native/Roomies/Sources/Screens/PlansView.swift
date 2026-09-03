import SwiftUI
import EventKit

private extension EKEvent {
    /// eventIdentifier alone can collide across distinct recurring-event instances on some
    /// calendar sources — pairing it with the start date is enough to keep ForEach ids unique
    /// without needing a real per-occurrence identifier from EventKit.
    var uniqueKey: String {
        "\(eventIdentifier ?? "")|\(startDate?.timeIntervalSince1970 ?? 0)"
    }
}

struct PlansView: View {
    @EnvironmentObject private var store: HouseholdStore
    @StateObject private var calendar = CalendarService()

    @State private var syncing = false
    @State private var pendingAllDay: [EKEvent] = []
    @State private var sharedTitleIDs: Set<String> = []
    @State private var composing = false

    // Manual plan composer
    @State private var title = ""
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(86_400)
    @State private var shareTitle = true
    @State private var invitees: Set<String> = []
    @State private var editTarget: PlanEvent?

    private var people: [String] { store.state.people }
    private var plans: [PlanEvent] { store.state.plans.filter { $0.end >= Date() } }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                calendarCard
                if !pendingAllDay.isEmpty { allDayPrompt }
                if composing { composer } else { newPlanButton }
                upcoming
            }
            .padding(.bottom, 24)
        }
        .onAppear { calendar.refreshAuthorizationStatus() }
        .sheet(item: $editTarget) { plan in
            EditPlanSheet(plan: plan)
        }
    }

    // MARK: - Calendar connection

    private var calendarCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Your calendar")
                switch calendar.access {
                case .granted:
                    Text("Connected — only your busy times are shared, never event names.")
                        .font(Fonts.sans(12)).foregroundColor(Theme.textDim)
                    Button {
                        Task { await syncCalendar() }
                    } label: {
                        Text(syncing ? "Syncing…" : "Sync availability")
                            .font(Fonts.sans(13, weight: .medium))
                            .foregroundColor(Theme.teal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.teal.opacity(0.4), lineWidth: 1))
                    }
                    .disabled(syncing)
                case .denied:
                    Text("Calendar access is off. You can still add plans by hand below, or enable it in Settings → Privacy → Calendars.")
                        .font(Fonts.sans(12)).foregroundColor(Theme.textDim)
                case .unknown:
                    Text("Share when you're busy without revealing what you're doing. Event names stay on your device unless you choose otherwise.")
                        .font(Fonts.sans(12)).foregroundColor(Theme.textDim)
                    Button {
                        Task {
                            if await calendar.requestAccess() { await syncCalendar() }
                        }
                    } label: {
                        Text("Connect calendar")
                            .font(Fonts.sans(13, weight: .medium))
                            .foregroundColor(Theme.coral)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.coral.opacity(0.4), lineWidth: 1))
                    }
                }
            }
        }
    }

    /// All-day events read as travel/away context, which is genuinely useful to flatmates —
    /// so we ask per event whether the name can come along.
    private var allDayPrompt: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Share these names?")
                Text("All-day events often explain where you are. Pick which names your flatmates can see — the rest stay private.")
                    .font(Fonts.sans(12)).foregroundColor(Theme.textDim)

                ForEach(pendingAllDay, id: \.uniqueKey) { event in
                    let id = event.eventIdentifier ?? ""
                    let on = sharedTitleIDs.contains(id)
                    Button {
                        if on { sharedTitleIDs.remove(id) } else { sharedTitleIDs.insert(id) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(on ? "☑︎" : "☐").font(.system(size: 16)).foregroundColor(on ? Theme.teal : Theme.textFaint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title ?? "Untitled")
                                    .font(Fonts.sans(13, weight: .medium)).foregroundColor(Theme.text)
                                Text(dayRange(event.startDate, event.endDate))
                                    .font(Fonts.mono(10)).foregroundColor(Theme.textFaint)
                            }
                            Spacer()
                        }
                    }
                }

                Button {
                    Task { await syncCalendar(confirmingAllDay: true) }
                } label: {
                    Text("Save & share availability")
                        .font(Fonts.sans(13, weight: .medium))
                        .foregroundColor(Theme.teal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.teal.opacity(0.4), lineWidth: 1))
                }
            }
        }
    }

    private func syncCalendar(confirmingAllDay: Bool = false) async {
        syncing = true
        defer { syncing = false }

        let events = calendar.upcomingEvents()

        if !confirmingAllDay {
            // eventIdentifier can be nil for some EKEvent instances (recurring occurrences,
            // certain calendar sources) — excluded here since it's both this list's ForEach id
            // (nil-collision would crash) and what syncCalendarBlocks tracks events by.
            let allDay = events.filter { $0.isAllDay && $0.title?.isEmpty == false && $0.eventIdentifier != nil }
            if !allDay.isEmpty {
                pendingAllDay = allDay
                return
            }
        }

        let blocks = events.compactMap { event -> (externalID: String, title: String, start: Date, end: Date, isAllDay: Bool)? in
            guard let id = event.eventIdentifier, let s = event.startDate, let e = event.endDate else { return nil }
            return (id, event.title ?? "Busy", s, e, event.isAllDay)
        }
        await store.syncCalendarBlocks(blocks, sharedTitleIDs: sharedTitleIDs)
        pendingAllDay = []
    }

    // MARK: - Manual plans

    private var newPlanButton: some View {
        Button { composing = true } label: {
            VStack(spacing: 2) {
                Text("+ Add a plan").font(Fonts.display(15)).foregroundColor(Theme.yellow)
                Text("travel, visitors, nights away").font(Fonts.sans(11)).foregroundColor(Theme.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(Theme.yellow.opacity(0.05))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundColor(Theme.yellow.opacity(0.35)))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    private var composer: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("New plan")
                TextField("What's happening?", text: $title)
                    .textFieldStyle(RoomiesTextFieldStyle())

                DatePicker("From", selection: $start, displayedComponents: [.date, .hourAndMinute])
                    .font(Fonts.sans(13)).foregroundColor(Theme.textSoft)
                DatePicker("Until", selection: $end, in: start..., displayedComponents: [.date, .hourAndMinute])
                    .font(Fonts.sans(13)).foregroundColor(Theme.textSoft)

                Toggle(isOn: $shareTitle) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share the name").font(Fonts.sans(13, weight: .medium)).foregroundColor(Theme.textSoft)
                        Text(shareTitle ? "Flatmates see \"\(title.isEmpty ? "…" : title)\"" : "Flatmates only see that you're away")
                            .font(Fonts.sans(11)).foregroundColor(Theme.textFaint)
                    }
                }
                .tint(Theme.teal)

                if people.count > 1 {
                    Text("Invite along (optional)").font(Fonts.sans(12)).foregroundColor(Color(hex: "666666"))
                    FlowLayout(spacing: 6) {
                        ForEach(people.filter { $0 != store.myName }, id: \.self) { person in
                            let on = invitees.contains(person)
                            Button {
                                if on { invitees.remove(person) } else { invitees.insert(person) }
                            } label: {
                                Text(person)
                                    .font(Fonts.sans(12))
                                    .foregroundColor(on ? Theme.personColor(person, people: people) : Color(hex: "888888"))
                                    .padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(on ? Theme.personColor(person, people: people).opacity(0.15) : Color.clear)
                                    .overlay(Capsule().stroke(on ? Theme.personColor(person, people: people).opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Button { composing = false } label: {
                        Text("Cancel").font(Fonts.sans(14, weight: .medium)).foregroundColor(Color(hex: "888888"))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
                    }
                    Button { post() } label: {
                        Text("Add plan").font(Fonts.display(15))
                            .foregroundColor(title.trimmed.isEmpty ? Color(hex: "444444") : Color(hex: "1a1a2e"))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(title.trimmed.isEmpty ? Color.white.opacity(0.06) : Theme.yellow)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(title.trimmed.isEmpty)
                }
            }
        }
    }

    private func post() {
        guard !title.trimmed.isEmpty else { return }
        store.addPlan(
            title: shareTitle ? title.trimmed : nil,
            start: start,
            end: end,
            isAllDay: false,
            invitees: Array(invitees)
        )
        title = ""
        invitees = []
        shareTitle = true
        composing = false
    }

    // MARK: - Shared availability

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHO'S AWAY").font(Fonts.mono(11)).foregroundColor(Color(hex: "666666")).tracking(1)

            if plans.isEmpty {
                Text("Nothing coming up.\nConnect a calendar or add a plan to share your availability.")
                    .font(Fonts.sans(14))
                    .foregroundColor(Theme.textGhost)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
            }

            ForEach(plans) { plan in
                let editable = plan.owner == store.myName && plan.isManual
                CardView {
                    HStack(spacing: 12) {
                        AvatarView(name: plan.owner, people: people, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(plan.title ?? "Busy")
                                .font(Fonts.sans(14, weight: .medium))
                                .foregroundColor(plan.title == nil ? Theme.textDim : Theme.text)
                                .italic(plan.title == nil)
                            Text("\(plan.owner) · \(dayRange(plan.start, plan.end))\(editable ? " · edit" : "")")
                                .font(Fonts.mono(10)).foregroundColor(Theme.textFaint)
                            if !plan.invitees.isEmpty {
                                Text("with \(plan.invitees.joined(separator: ", "))")
                                    .font(Fonts.mono(10)).foregroundColor(Theme.teal)
                            }
                        }
                        Spacer()
                        if plan.owner == store.myName {
                            Button { store.deletePlan(id: plan.id) } label: {
                                Text("✕").font(Fonts.sans(13)).foregroundColor(Theme.textFaint)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if editable { editTarget = plan } }
            }
        }
    }
}

func dayRange(_ start: Date?, _ end: Date?) -> String {
    guard let start else { return "" }
    let formatter = DateFormatter()
    formatter.dateFormat = "d MMM"
    let startText = formatter.string(from: start)
    guard let end, !Calendar.current.isDate(start, inSameDayAs: end) else { return startText }
    return "\(startText) – \(formatter.string(from: end))"
}
