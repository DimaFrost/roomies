import SwiftUI

struct AsksView: View {
    @ObservedObject var household: Household
    let people: [String]
    let asks: [Ask]

    @EnvironmentObject private var store: HouseholdStore

    @State private var composing = false
    @State private var title = ""
    @State private var note = ""
    @State private var askedBy = ""
    /// nil means anyone in the flat can pick the ask up.
    @State private var target: String?
    @State private var pendingDelete: Ask?

    private var open: [Ask] { asks.filter { $0.status == .open } }
    private var inProgress: [Ask] { asks.filter { $0.status == .accepted } }
    private var done: [Ask] { Array(asks.filter { $0.status == .done }.prefix(5)) }

    private var canPost: Bool { !title.trimmed.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if composing {
                    composer
                } else {
                    newAskButton
                }

                if asks.isEmpty, !composing {
                    Text("No asks yet.\nNeed a favour? Post one and your flatmate will see it.")
                        .font(.sans(14))
                        .foregroundStyle(Theme.textGhost)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }

                if !open.isEmpty {
                    section("Open (\(open.count))") {
                        ForEach(open, id: \.objectID) { ask in
                            askCard(ask) {
                                HStack(spacing: 8) {
                                    ForEach(claimants(for: ask), id: \.self) { person in
                                        Button {
                                            store.accept(ask, by: person)
                                        } label: {
                                            Text("\(person): I'm on it")
                                                .font(.sans(12, weight: .medium))
                                                .foregroundStyle(Theme.personColor(person, in: people))
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .overlay {
                                                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                                        .strokeBorder(Theme.personColor(person, in: people).opacity(0.4))
                                                }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.top, 10)
                            }
                        }
                    }
                }

                if !inProgress.isEmpty {
                    section("In progress (\(inProgress.count))") {
                        ForEach(inProgress, id: \.objectID) { ask in
                            askCard(ask) {
                                HStack(spacing: 8) {
                                    Text("\(ask.acceptedBy ?? "Someone") is on it")
                                        .font(.sans(12))
                                        .foregroundStyle(Theme.textDim)
                                    Spacer(minLength: 0)
                                    Button {
                                        store.complete(ask)
                                    } label: {
                                        Text("Done ✓")
                                            .font(.sans(12, weight: .medium))
                                            .foregroundStyle(Theme.teal)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background {
                                                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                                    .fill(Theme.teal.opacity(0.1))
                                            }
                                            .overlay {
                                                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                                                    .strokeBorder(Theme.teal.opacity(0.5))
                                            }
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 10)
                            }
                        }
                    }
                }

                if !done.isEmpty {
                    section("Recently done") {
                        ForEach(done, id: \.objectID) { ask in
                            askCard(ask, muted: true) {
                                Text(completionSummary(for: ask))
                                    .font(.sans(11))
                                    .foregroundStyle(Theme.textFaint)
                                    .padding(.top, 6)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: ensureDefaults)
        .onChange(of: people) { _, _ in ensureDefaults() }
        .confirmationDialog(
            "Remove ask?",
            isPresented: presenting($pendingDelete),
            titleVisibility: .visible
        ) {
            if let ask = pendingDelete {
                Button("Remove", role: .destructive) { store.delete(ask) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let ask = pendingDelete {
                Text("\"\(ask.displayTitle)\"")
            }
        }
    }

    private func ensureDefaults() {
        if askedBy.isEmpty || !people.contains(askedBy) {
            askedBy = people.contains(store.myName) ? store.myName : (people.first ?? "")
        }
        if let target, !people.contains(target) || target == askedBy {
            self.target = nil
        }
    }

    /// Who can claim an ask: the named flatmate, or anyone but the requester.
    private func claimants(for ask: Ask) -> [String] {
        if let assigned = ask.target { return [assigned] }
        return people.filter { $0 != ask.requester }
    }

    private func completionSummary(for ask: Ask) -> String {
        var text = "✓ done by \(ask.acceptedBy ?? "someone")"
        let when = RelativeTime.string(for: ask.completedAt)
        if !when.isEmpty { text += " · \(when)" }
        return text
    }

    // MARK: - Composer

    private var newAskButton: some View {
        Button {
            composing = true
        } label: {
            VStack(spacing: 2) {
                Text("+ Post an ask")
                    .font(.display(15))
                    .foregroundStyle(Theme.yellow)
                Text("water the plants, grab milk, anything")
                    .font(.sans(11))
                    .foregroundStyle(Theme.textFaint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.yellow.opacity(0.05))
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.yellow.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .buttonStyle(.plain)
    }

    private var composer: some View {
        CardView(verticalPadding: 16, spacing: 12) {
            SectionLabel("New ask")

            FlowLayout(spacing: 6) {
                ForEach(quickAsks, id: \.self) { suggestion in
                    ChipButton(label: suggestion, isActive: title == suggestion, activeColor: Theme.yellow) {
                        title = suggestion
                    }
                }
            }

            TextField("What do you need?", text: $title)
                .roomiesField()

            TextField("Details (optional)", text: $note)
                .roomiesField()

            VStack(alignment: .leading, spacing: 8) {
                Text("Who's asking?")
                    .font(.sans(12))
                    .foregroundStyle(Theme.textMuted)
                PersonPicker(options: people, people: people, selected: askedBy, avatarSize: 26) { person in
                    askedBy = person
                    if target == person { target = nil }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Who should do it?")
                    .font(.sans(12))
                    .foregroundStyle(Theme.textMuted)

                HStack(spacing: 8) {
                    Button {
                        target = nil
                    } label: {
                        VStack(spacing: 4) {
                            Text("🙋").font(.system(size: 16))
                            Text("Anyone")
                                .font(.sans(12, weight: .medium))
                                .foregroundStyle(target == nil ? Theme.yellow : Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(target == nil ? Theme.yellow.opacity(0.1) : .clear)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .strokeBorder(target == nil ? Theme.yellow.opacity(0.5) : Theme.cardBorder)
                        }
                    }
                    .buttonStyle(.plain)

                    PersonPicker(
                        options: people.filter { $0 != askedBy },
                        people: people,
                        selected: target,
                        avatarSize: 22
                    ) { target = $0 }
                    .frame(maxWidth: .infinity)
                }
            }

            HStack(spacing: 8) {
                Button {
                    composing = false
                } label: {
                    Text("Cancel")
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Theme.cardBorder)
                        }
                }
                .buttonStyle(.plain)

                PrimaryButton(
                    title: "Post Ask",
                    color: Theme.yellow,
                    titleColor: Theme.onAccent,
                    isEnabled: canPost
                ) {
                    post()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func post() {
        guard canPost else { return }
        store.addAsk(
            to: household,
            title: title,
            note: note,
            askedBy: askedBy,
            assignedTo: target
        )
        title = ""
        note = ""
        target = nil
        composing = false
    }

    // MARK: - Cards

    private func section<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.mono(11))
                .tracking(1)
                .foregroundStyle(Theme.textMuted)
                .padding(.top, 6)
            content()
        }
    }

    private func askCard<Footer: View>(
        _ ask: Ask,
        muted: Bool = false,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        CardView(spacing: 0) {
            HStack(spacing: 12) {
                AvatarView(name: ask.requester, people: people, size: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ask.displayTitle)
                        .font(.sans(14, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    Text("\(ask.requester) asked \(ask.target ?? "anyone") · \(RelativeTime.string(for: ask.createdAt))")
                        .font(.mono(10))
                        .foregroundStyle(Theme.textFaint)
                }

                Spacer(minLength: 0)
            }

            if let note = ask.note, !note.isEmpty {
                Text(note)
                    .font(.sans(13))
                    .foregroundStyle(Theme.textDim)
                    .padding(.top, 8)
            }

            footer()
        }
        .opacity(muted ? 0.55 : 1)
        .contextMenu {
            Button(role: .destructive) {
                pendingDelete = ask
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}
