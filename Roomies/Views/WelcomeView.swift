import SwiftUI

struct WelcomeView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case create
        case join

        var id: String { rawValue }

        var label: String {
            switch self {
            case .create: return "Start a flat"
            case .join: return "Join a flat"
            }
        }
    }

    @EnvironmentObject private var store: HouseholdStore

    @State private var mode: Mode = .create
    @State private var flatName = ""
    @State private var name = ""

    private var canSubmit: Bool {
        !name.trimmed.isEmpty && !flatName.trimmed.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 40)

                (Text("room").foregroundStyle(Theme.text) + Text("ies").foregroundStyle(Theme.coral))
                    .font(.display(40))
                    .tracking(-1)

                Text("your flat, one app")
                    .font(.mono(13))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.top, 6)

                modeBar
                    .padding(.top, 28)

                switch mode {
                case .create: createCard
                case .join: joinCard
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(Mode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.label)
                        .font(.sans(13, weight: .medium))
                        .foregroundStyle(mode == item ? .white : Theme.textFaint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(mode == item ? Color.white.opacity(0.1) : .clear)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var createCard: some View {
        VStack(spacing: 16) {
            CardView(verticalPadding: 18, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Name your flat")
                    TextField("e.g. Sonnenallee 42", text: $flatName)
                        .textInputAutocapitalization(.words)
                        .roomiesField()
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Your name")
                    TextField("What your flatmates call you", text: $name)
                        .textInputAutocapitalization(.words)
                        .roomiesField()
                }
            }

            PrimaryButton(title: "Create Flat", isEnabled: canSubmit) {
                store.createHousehold(named: flatName, memberName: name)
            }

            Text("Then invite your flatmates — the flat syncs over iCloud, no account needed.")
                .font(.sans(12))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    private var joinCard: some View {
        VStack(spacing: 16) {
            CardView(verticalPadding: 18, spacing: 12) {
                SectionLabel("Joining is by invite")

                Label {
                    Text("Ask whoever set up the flat to tap **invite** in the app and send you the link.")
                        .font(.sans(14))
                        .foregroundStyle(Theme.textSoft)
                } icon: {
                    Image(systemName: "link")
                        .foregroundStyle(Theme.teal)
                }

                Label {
                    Text("Open that link on this iPhone and the flat appears here — expenses, asks and all.")
                        .font(.sans(14))
                        .foregroundStyle(Theme.textSoft)
                } icon: {
                    Image(systemName: "iphone.and.arrow.forward")
                        .foregroundStyle(Theme.teal)
                }
            }

            Text("Invites travel over iCloud, so both phones need to be signed in to iCloud.")
                .font(.sans(12))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }
}

/// Shown once, right after accepting an invite: which flatmate is this phone?
struct ClaimNameView: View {
    @ObservedObject var household: Household
    @EnvironmentObject private var store: HouseholdStore

    @State private var name = ""

    private var existing: [String] { household.memberNames }

    private var canSubmit: Bool {
        let trimmed = name.trimmed
        return !trimmed.isEmpty && !existing.contains(trimmed)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer(minLength: 40)

                Text("You're in 🎉")
                    .font(.display(24))
                    .foregroundStyle(Theme.text)

                Text(household.name ?? "Your flat")
                    .font(.mono(13))
                    .foregroundStyle(Theme.teal)

                CardView(verticalPadding: 18, spacing: 12) {
                    SectionLabel("Your name")
                    TextField("What your flatmates call you", text: $name)
                        .textInputAutocapitalization(.words)
                        .roomiesField()

                    if !existing.isEmpty {
                        Text("Already here: \(existing.joined(separator: ", "))")
                            .font(.sans(12))
                            .foregroundStyle(Theme.textFaint)
                    }

                    if !name.trimmed.isEmpty, existing.contains(name.trimmed) {
                        Text("That name is taken in this flat.")
                            .font(.sans(12))
                            .foregroundStyle(Theme.coral)
                    }
                }

                PrimaryButton(title: "Join Flat", color: Theme.teal, titleColor: Theme.onAccent, isEnabled: canSubmit) {
                    store.claimName(name, in: household)
                }

                Spacer(minLength: 40)
            }
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }
}
