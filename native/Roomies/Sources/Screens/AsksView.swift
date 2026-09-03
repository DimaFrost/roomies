import SwiftUI

private let QUICK_ASKS = ["🌱 Water my plants", "🛒 Pick something up", "🗑 Take out the trash", "🍳 Cook tonight", "📦 Accept a delivery", "🔑 Let someone in"]
private let ANYONE = "anyone"

struct AsksView: View {
    @EnvironmentObject private var store: HouseholdStore
    @State private var composing = false
    @State private var title = ""
    @State private var note = ""
    @State private var askedBy: String?
    @State private var target = ANYONE
    @State private var deleteTarget: Ask?
    @State private var editTarget: Ask?

    private var people: [String] { store.state.people }
    private var asks: [Ask] { store.state.asks }
    private var open: [Ask] { asks.filter { $0.status == .open } }
    private var inProgress: [Ask] { asks.filter { $0.status == .accepted } }
    private var done: [Ask] { Array(asks.filter { $0.status == .done }.prefix(5)) }
    private var resolvedAskedBy: String { askedBy ?? store.myName ?? people.first ?? "" }
    private var canPost: Bool { !title.trimmed.isEmpty }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if !composing {
                    Button { composing = true } label: {
                        VStack(spacing: 2) {
                            Text("+ Post an ask").font(Fonts.display(15)).foregroundColor(Theme.yellow)
                            Text("water the plants, grab milk, anything").font(Fonts.sans(11)).foregroundColor(Theme.textFaint)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.yellow.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4])).foregroundColor(Theme.yellow.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                    }
                } else {
                    composer
                }

                if asks.isEmpty && !composing {
                    Text("No asks yet.\nNeed a favour? Post one and your flatmate will see it.")
                        .font(Fonts.sans(14))
                        .foregroundColor(Theme.textGhost)
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 40)
                }

                if !open.isEmpty { section("Open (\(open.count))") { openSection } }
                if !inProgress.isEmpty { section("In progress (\(inProgress.count))") { inProgressSection } }
                if !done.isEmpty { section("Recently done") { doneSection } }
            }
            .padding(.bottom, 24)
        }
        .onAppear { if askedBy == nil { askedBy = store.myName ?? people.first } }
        .alert("Remove ask?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Remove", role: .destructive) {
                if let t = deleteTarget { store.deleteAsk(id: t.id) }
                deleteTarget = nil
            }
        } message: {
            if let t = deleteTarget { Text("\"\(t.title)\"") }
        }
        .sheet(item: $editTarget) { ask in
            EditAskSheet(ask: ask)
        }
    }

    private func section<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased()).font(Fonts.mono(11)).foregroundColor(Color(hex: "666666")).tracking(1)
            content()
        }
    }

    private var composer: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("New ask")
                FlowLayout(spacing: 6) {
                    ForEach(QUICK_ASKS, id: \.self) { q in
                        Button { title = q } label: {
                            Text(q).font(Fonts.sans(12)).foregroundColor(Color(hex: "888888"))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                    }
                }
                TextField("What do you need?", text: $title).textFieldStyle(RoomiesTextFieldStyle())
                TextField("Details (optional)", text: $note).textFieldStyle(RoomiesTextFieldStyle())

                VStack(alignment: .leading, spacing: 8) {
                    Text("Who's asking?").font(Fonts.sans(12)).foregroundColor(Color(hex: "666666"))
                    PersonPickerView(options: people, people: people, selected: resolvedAskedBy, onSelect: { p in
                        askedBy = p
                        if target == p { target = ANYONE }
                    }, avatarSize: 26)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Who should do it?").font(Fonts.sans(12)).foregroundColor(Color(hex: "666666"))
                    HStack(spacing: 8) {
                        Button { target = ANYONE } label: {
                            VStack(spacing: 4) {
                                Text("🙋").font(.system(size: 16))
                                Text("Anyone").font(Fonts.sans(12, weight: .medium)).foregroundColor(target == ANYONE ? Theme.yellow : Color(hex: "666666"))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(target == ANYONE ? Theme.yellow.opacity(0.1) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(target == ANYONE ? Theme.yellow.opacity(0.5) : Theme.cardBorder, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
                        }
                        .frame(maxWidth: .infinity)

                        PersonPickerView(
                            options: people.filter { $0 != resolvedAskedBy },
                            people: people,
                            selected: target == ANYONE ? nil : target,
                            onSelect: { target = $0 },
                            avatarSize: 22
                        )
                        .frame(maxWidth: .infinity)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        composing = false
                    } label: {
                        Text("Cancel").font(Fonts.sans(14, weight: .medium)).foregroundColor(Color(hex: "888888"))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.cardBorder, lineWidth: 1))
                    }
                    Button {
                        handlePost()
                    } label: {
                        Text("Post Ask").font(Fonts.display(15)).foregroundColor(canPost ? Color(hex: "1a1a2e") : Color(hex: "444444"))
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(canPost ? Theme.yellow : Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canPost)
                }
            }
        }
    }

    private func handlePost() {
        guard canPost else { return }
        store.addAsk(title: title.trimmed, note: note.trimmed.isEmpty ? nil : note.trimmed, askedBy: resolvedAskedBy, assignedTo: target == ANYONE ? nil : target)
        title = ""
        note = ""
        target = ANYONE
        composing = false
    }

    private var openSection: some View {
        ForEach(open) { ask in
            askCard(ask) {
                let candidates = ask.assignedTo.map { [$0] } ?? people.filter { $0 != ask.askedBy }
                HStack(spacing: 8) {
                    ForEach(candidates, id: \.self) { p in
                        Button { store.acceptAsk(id: ask.id, by: p) } label: {
                            Text("\(p): I'm on it")
                                .font(Fonts.sans(12, weight: .medium))
                                .foregroundColor(Theme.personColor(p, people: people))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .overlay(Capsule().stroke(Theme.personColor(p, people: people).opacity(0.4), lineWidth: 1))
                        }
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var inProgressSection: some View {
        ForEach(inProgress) { ask in
            askCard(ask) {
                HStack(spacing: 8) {
                    Text("\(ask.acceptedBy ?? "") is on it").font(Fonts.sans(12)).foregroundColor(Theme.textDim)
                    Spacer()
                    Button { store.completeAsk(id: ask.id) } label: {
                        Text("Done ✓").font(Fonts.sans(12, weight: .medium)).foregroundColor(Theme.teal)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.teal.opacity(0.1))
                            .overlay(Capsule().stroke(Theme.teal.opacity(0.5), lineWidth: 1))
                    }
                }
                .padding(.top, 10)
            }
        }
    }

    private var doneSection: some View {
        ForEach(done) { ask in
            askCard(ask, muted: true) {
                Text("✓ done by \(ask.acceptedBy ?? "someone")\(ask.completedAt != nil ? " · \(timeAgo(ask.completedAt!))" : "")")
                    .font(Fonts.sans(11))
                    .foregroundColor(Theme.textFaint)
                    .padding(.top, 6)
            }
        }
    }

    private func askCard<Content: View>(_ ask: Ask, muted: Bool = false, @ViewBuilder extra: () -> Content) -> some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    AvatarView(name: ask.askedBy, people: people, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ask.title).font(Fonts.sans(14, weight: .medium)).foregroundColor(Theme.text).lineLimit(2)
                        Text("\(ask.askedBy) asked \(ask.assignedTo ?? "anyone") · \(timeAgo(ask.createdAt))\(ask.askedBy == store.myName ? " · edit" : "")")
                            .font(Fonts.mono(10)).foregroundColor(Theme.textFaint)
                    }
                    Spacer()
                }
                if let note = ask.note {
                    Text(note).font(Fonts.sans(13)).foregroundColor(Theme.textDim).padding(.top, 8)
                }
                extra()
            }
        }
        .opacity(muted ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture { if ask.askedBy == store.myName { editTarget = ask } }
        .onLongPressGesture { deleteTarget = ask }
    }
}
