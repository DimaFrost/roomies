import SwiftUI
import CloudKit

/// Invites one named flatmate, then shows the link that only they can use.
///
/// The link is an address, not a key: access comes from being an explicit participant on the
/// share, bound by CloudKit to the Apple Account behind the email or phone number entered here.
/// Forwarding the URL to someone else gets them nothing, and removing a flatmate later actually
/// revokes their access — neither of which was true while the link itself granted entry.
///
/// The recipient still pastes the link into "Join a flat" rather than tapping it.
/// `UICloudSharingController`'s tappable Join card routes through iOS's share-accept flow, which
/// checks the App Store for the app before handing off and so fails for a TestFlight build even
/// when both people already have it installed.
struct InviteLinkView: View {
    @EnvironmentObject private var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let share: CKShare

    @State private var contact = ""
    @State private var sending = false
    @State private var invited: String?
    @State private var errorText: String?
    @State private var copied = false
    @State private var closingLink = false

    private var linkText: String { (store.pendingShare ?? share).url?.absoluteString ?? "" }
    private var onOpenLink: [String] { store.flatmatesOnOpenLink }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Invite a flatmate", canSave: true, onCancel: { dismiss() }, onSave: { dismiss() })

            ScrollView {
                VStack(spacing: 16) {
                    inviteCard
                    if invited != nil { linkCard }
                    if !onOpenLink.isEmpty { openLinkCard }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private var inviteCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Their email or phone")
                TextField("The one their Apple Account uses", text: $contact)
                    .textFieldStyle(RoomiesTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)

                if let errorText {
                    Text(errorText)
                        .font(Fonts.sans(13))
                        .foregroundColor(Theme.coral)
                }

                Button {
                    Task { await send() }
                } label: {
                    Text(sending ? "Inviting…" : "Invite")
                        .font(Fonts.display(15))
                        .foregroundColor(canSend ? .white : Color(hex: "444444"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(canSend ? Theme.coral : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!canSend)

                Text("Has to be an address or number Apple can find them by — the invite is locked to that account, so nobody else can use the link.")
                    .font(Fonts.sans(12))
                    .foregroundColor(Theme.textFaint)
            }
        }
    }

    private var linkCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("\(invited ?? "They") can now join — send them this")
                Text(linkText.isEmpty ? "Preparing your link…" : linkText)
                    .font(Fonts.mono(12))
                    .foregroundColor(Theme.textSoft)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.card)
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius).stroke(Theme.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))

                Button {
                    UIPasteboard.general.string = linkText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Text(copied ? "✓ Copied" : "Copy Invite Link")
                        .font(Fonts.display(15))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.coral)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(linkText.isEmpty)

                if !linkText.isEmpty {
                    ShareLink(item: linkText) {
                        Text("Share via…")
                            .font(Fonts.sans(14, weight: .medium))
                            .foregroundColor(Theme.teal)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.teal.opacity(0.4), lineWidth: 1))
                    }
                }

                Text("They paste it into Roomies under \"Join a flat\" — not tap it.")
                    .font(Fonts.sans(12))
                    .foregroundColor(Theme.textFaint)
            }
        }
    }

    /// Only shown while somebody's access still depends on the old open link, since closing it
    /// would put them out of the flat.
    private var openLinkCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("This flat's old link still works for anyone")
                Text("\(onOpenLink.joined(separator: ", ")) joined through a link that lets in whoever holds it. Closing it means inviting \(onOpenLink.count == 1 ? "them" : "each of them") by email or phone again.")
                    .font(Fonts.sans(13))
                    .foregroundColor(Theme.textDim)

                Button {
                    Task { await closeLink() }
                } label: {
                    Text(closingLink ? "Closing…" : "Close the old link")
                        .font(Fonts.sans(14, weight: .medium))
                        .foregroundColor(Theme.coral)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.coral.opacity(0.4), lineWidth: 1))
                }
                .disabled(closingLink)
            }
        }
    }

    private var canSend: Bool { !contact.trimmed.isEmpty && !sending }

    private func send() async {
        guard canSend else { return }
        sending = true
        errorText = nil
        let target = contact.trimmed
        if let failure = await store.inviteFlatmate(contact: target) {
            errorText = failure
        } else {
            invited = target
            contact = ""
        }
        sending = false
    }

    private func closeLink() async {
        closingLink = true
        errorText = await store.closeOpenInviteLink()
        closingLink = false
    }
}
