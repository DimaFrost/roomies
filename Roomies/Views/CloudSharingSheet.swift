import CloudKit
import SwiftUI

/// The share and container needed to present the system invite sheet.
struct ShareTarget: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
    let title: String
}

/// Apple's invite UI: sends the flat's share link through Messages, Mail, AirDrop, etc.
struct CloudSharingSheet: UIViewControllerRepresentable {
    let target: ShareTarget
    var onStopSharing: () -> Void = {}

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: target.share, container: target.container)
        // Flatmates need to add expenses, so read-write is the only useful permission.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(title: target.title, onStopSharing: onStopSharing)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let title: String
        private let onStopSharing: () -> Void

        init(title: String, onStopSharing: @escaping () -> Void) {
            self.title = title
            self.onStopSharing = onStopSharing
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {}

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            onStopSharing()
        }
    }
}
