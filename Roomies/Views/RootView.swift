import CloudKit
import CoreData
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: HouseholdStore

    // Households arrive from either store, so this picks up both a flat you
    // created and one a flatmate shared with you.
    @FetchRequest(sortDescriptors: [SortDescriptor(\Household.createdAt, order: .forward)])
    private var households: FetchedResults<Household>

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let household = households.first {
            if !store.myName.isEmpty, household.memberNames.contains(store.myName) {
                HouseholdShell(household: household)
            } else {
                // Reached after accepting an invite: pick which flatmate this phone is.
                ClaimNameView(household: household)
            }
        } else {
            WelcomeView()
        }
    }
}

private enum ShellTab: String, CaseIterable, Identifiable {
    case split
    case asks

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .split: return "💶"
        case .asks: return "🤝"
        }
    }

    var label: String {
        switch self {
        case .split: return "Split"
        case .asks: return "Asks"
        }
    }
}

struct HouseholdShell: View {
    @ObservedObject var household: Household
    @EnvironmentObject private var store: HouseholdStore

    // Members are fetched rather than read off the relationship so that a
    // flatmate joining mid-session refreshes the header and pickers.
    @FetchRequest private var members: FetchedResults<Member>
    @FetchRequest private var expenses: FetchedResults<Expense>
    @FetchRequest private var asks: FetchedResults<Ask>

    @State private var tab: ShellTab = .split
    @State private var shareTarget: ShareTarget?
    @State private var isPreparingShare = false
    @State private var confirmingLeave = false

    // Cached rather than queried per redraw: these only change when the flat is
    // shared, unshared, or first appears.
    @State private var isSharedFlat = false
    @State private var isOwnerFlat = true

    init(household: Household) {
        self.household = household
        _members = FetchRequest(
            sortDescriptors: [SortDescriptor(\Member.createdAt, order: .forward)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
        _expenses = FetchRequest(
            sortDescriptors: [SortDescriptor(\Expense.createdAt, order: .reverse)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
        _asks = FetchRequest(
            sortDescriptors: [SortDescriptor(\Ask.createdAt, order: .reverse)],
            predicate: NSPredicate(format: "household == %@", household),
            animation: .default
        )
    }

    private var people: [String] {
        members.compactMap { (member: Member) -> String? in
            guard let name = member.name, !name.isEmpty else { return nil }
            return name
        }
    }
    private var totalSpend: Double { expenses.reduce(0) { $0 + $1.amount } }
    private var openAsks: Int { asks.filter { $0.status != .done }.count }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                header
                    .padding(.bottom, 20)

                switch tab {
                case .split:
                    SplitView(household: household, people: people, expenses: Array(expenses))
                case .asks:
                    AsksView(household: household, people: people, asks: Array(asks))
                }
            }
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 16)

            tabBar
        }
        .onAppear(perform: refreshShareState)
        .sheet(item: $shareTarget, onDismiss: refreshShareState) { target in
            CloudSharingSheet(target: target)
                .ignoresSafeArea()
        }
        .confirmationDialog(
            leaveTitle,
            isPresented: $confirmingLeave,
            titleVisibility: .visible
        ) {
            Button(leaveAction, role: .destructive) {
                Task {
                    await store.stopSharing(household)
                    refreshShareState()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(leaveMessage)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                (Text("room").foregroundStyle(Theme.text) + Text("ies").foregroundStyle(Theme.coral))
                    .font(.display(26))
                    .tracking(-0.5)

                Text(subline)
                    .font(.mono(12))
                    .foregroundStyle(Theme.textMuted)

                inviteRow
            }

            Spacer(minLength: 0)

            HStack(spacing: -10) {
                // Indices rather than enumerated(), so the earliest flatmate
                // stays on top of the overlap.
                ForEach(people.indices, id: \.self) { index in
                    AvatarView(name: people[index], people: people, size: 32)
                        .zIndex(Double(people.count - index))
                }
            }
        }
    }

    private var leaveTitle: String {
        isOwnerFlat ? "Stop sharing this flat?" : "Leave this flat?"
    }

    private var leaveAction: String {
        isOwnerFlat ? "Stop sharing" : "Leave flat"
    }

    private var leaveMessage: String {
        isOwnerFlat
            ? "Your flatmates will lose access. The flat and its history stay on your device."
            : "The flat's expenses and asks will disappear from this phone."
    }

    private var subline: String {
        let flatmates = "\(people.count) flatmate\(people.count == 1 ? "" : "s")"
        switch tab {
        case .split:
            return "\(flatmates) · \(totalSpend.euros) total"
        case .asks:
            return "\(flatmates) · \(openAsks) open ask\(openAsks == 1 ? "" : "s")"
        }
    }

    @ViewBuilder
    private var inviteRow: some View {
        HStack(spacing: 6) {
            Text(household.name ?? "Your flat")
                .font(.mono(11))
                .foregroundStyle(Theme.teal)

            if isOwnerFlat {
                Button {
                    prepareShare()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isSharedFlat ? "person.2.fill" : "person.badge.plus")
                            .font(.system(size: 9))
                        Text(isSharedFlat ? "manage" : "invite")
                            .font(.mono(11))
                    }
                    .foregroundStyle(Theme.teal.opacity(0.85))
                }
                .buttonStyle(.plain)
                .disabled(isPreparingShare)
                .opacity(isPreparingShare ? 0.4 : 1)
            } else {
                Text("shared flat")
                    .font(.mono(11))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .contextMenu {
            Button(isOwnerFlat ? "Stop sharing…" : "Leave flat…", role: .destructive) {
                confirmingLeave = true
            }
        }
    }

    private func prepareShare() {
        isPreparingShare = true
        Task {
            if let (share, container) = await store.share(household) {
                shareTarget = ShareTarget(
                    share: share,
                    container: container,
                    title: household.name ?? "Roomies"
                )
            }
            isPreparingShare = false
            refreshShareState()
        }
    }

    private func refreshShareState() {
        isSharedFlat = store.isShared(household)
        isOwnerFlat = store.isOwner(of: household)
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(ShellTab.allCases) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 2) {
                        Text(item.emoji)
                            .font(.system(size: 20))
                            .opacity(tab == item ? 1 : 0.4)
                            .overlay(alignment: .topTrailing) {
                                if item == .asks, openAsks > 0 {
                                    Text("\(openAsks)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(Theme.onAccent)
                                        .padding(.horizontal, 4)
                                        .frame(minWidth: 16, minHeight: 16)
                                        .background(Theme.coral, in: Capsule())
                                        .offset(x: 10, y: -4)
                                }
                            }
                        Text(item.label)
                            .font(.sans(11, weight: .medium))
                            .foregroundStyle(tab == item ? Theme.text : Theme.textFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(alignment: .top) {
            Theme.cardBorder.frame(height: 1)
        }
        .background(Theme.panel)
    }
}
