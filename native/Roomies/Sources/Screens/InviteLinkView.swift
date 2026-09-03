import SwiftUI
import CloudKit

/// Shows the flat's invite link as plain copyable text instead of the system share sheet.
///
/// `UICloudSharingController`'s Messages integration renders `icloud.com/share` links as a
/// special tappable "Join" card — tapping it routes through iOS's share-accept flow, which
/// checks the app's availability on the public App Store before handing off to us. That check
/// fails for a TestFlight-only build even when the recipient already has the app installed and
/// up to date. Sharing the link as plain text sidesteps that: the recipient pastes it into
/// "Join a flat" instead, where `HouseholdStore.acceptInvite` accepts it directly via
/// `CKContainer.shareMetadata(for:)` / `.accept(_:)`, with no OS dialog involved.
struct InviteLinkView: View {
    @EnvironmentObject private var store: HouseholdStore
    @Environment(\.dismiss) private var dismiss
    let share: CKShare

    @State private var copied = false

    private var linkText: String { share.url?.absoluteString ?? "" }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "Invite link", canSave: true, onCancel: { dismiss() }, onSave: { dismiss() })

            ScrollView {
                VStack(spacing: 16) {
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel("Send this to your flatmate")
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
                        }
                    }

                    Text("Send it any way you like — text, email, whatever. They'll paste it into Roomies under \"Join a flat,\" not tap it directly.")
                        .font(Fonts.sans(12))
                        .foregroundColor(Theme.textFaint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
