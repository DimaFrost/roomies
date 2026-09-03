import SwiftUI

enum Tab: String, CaseIterable {
    case split, asks, plans, flat

    var emoji: String {
        switch self {
        case .split: return "💶"
        case .asks: return "🤝"
        case .plans: return "🗓"
        case .flat: return "🏠"
        }
    }

    var label: String {
        switch self {
        case .split: return "Split"
        case .asks: return "Asks"
        case .plans: return "Plans"
        case .flat: return "Flat"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: HouseholdStore
    @State private var tab: Tab = .split

    var totalSpend: Double { store.state.expenses.reduce(0) { $0 + $1.amount } }
    var openAsks: Int { store.state.asks.filter { $0.status != .done }.count }

    var body: some View {
        Group {
            switch store.phase {
            case .loading:
                Theme.bg.ignoresSafeArea()
            case .error:
                errorView
            case .needsHousehold:
                OnboardingView()
            case .needsName:
                JoinNameView()
            case .ready:
                readyView
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var errorView: some View {
        VStack(spacing: 10) {
            Text("Can't reach the flat ☁️")
                .font(Fonts.display(17))
                .foregroundColor(Theme.text)
            Text(store.error ?? "")
                .font(Fonts.sans(13))
                .foregroundColor(Theme.textDim)
                .multilineTextAlignment(.center)
            Button {
                Task { await store.bootstrap() }
            } label: {
                Text("Try again")
                    .font(Fonts.display(14))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Theme.coral)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var readyView: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                header
                Group {
                    switch tab {
                    case .split: ExpensesView()
                    case .asks: AsksView()
                    case .plans: PlansView()
                    case .flat: SettingsView()
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)

            tabBar
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                (Text("at our ").foregroundColor(Theme.text) + Text("place").foregroundColor(Theme.coral))
                    .font(Fonts.display(26, weight: .black))
                Text(subline)
                    .font(Fonts.mono(12))
                    .foregroundColor(Color(hex: "666666"))
                if let flat = store.flat {
                    Text(flat.name)
                        .font(Fonts.mono(11))
                        .foregroundColor(Theme.teal)
                }
            }
            Spacer()
            HStack(spacing: -10) {
                ForEach(store.state.people, id: \.self) { person in
                    AvatarView(name: person, people: store.state.people, size: 32)
                }
            }
        }
        .padding(.top, 16)
    }

    private var subline: String {
        let people = store.state.people
        let peopleLabel = "\(people.count) flatmate\(people.count == 1 ? "" : "s")"
        switch tab {
        case .split:
            return "\(peopleLabel) · €\(String(format: "%.2f", totalSpend)) total"
        case .asks:
            return "\(peopleLabel) · \(openAsks) open ask\(openAsks == 1 ? "" : "s")"
        case .plans:
            let upcoming = store.state.plans.filter { $0.end >= Date() }.count
            return "\(peopleLabel) · \(upcoming) upcoming"
        case .flat:
            if let rent = store.flat?.rentAmount {
                return "rent €\(String(format: "%.2f", rent))\(store.flat?.rentDueDay.map { " · due the \($0)\(ordinalSuffix($0))" } ?? "")"
            }
            return peopleLabel
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    tab = t
                } label: {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Text(t.emoji)
                                .font(.system(size: 20))
                                .opacity(tab == t ? 1 : 0.4)
                            if t == .asks && openAsks > 0 {
                                Text("\(openAsks)")
                                    .font(Fonts.sans(10, weight: .bold))
                                    .foregroundColor(Color(hex: "1a1a2e"))
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 16, minHeight: 16)
                                    .background(Theme.coral)
                                    .clipShape(Capsule())
                                    .offset(x: 10, y: -4)
                            }
                        }
                        Text(t.label)
                            .font(Fonts.sans(11, weight: .medium))
                            .foregroundColor(tab == t ? Theme.text : Theme.textFaint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Theme.panel)
        .overlay(Rectangle().fill(Theme.cardBorder).frame(height: 1), alignment: .top)
    }
}
