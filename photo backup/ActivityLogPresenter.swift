import UIKit

/// Presents the system share sheet for exported log text (iPad-safe popover).
enum ActivityLogPresenter {
    @MainActor
    static func presentShareSheet(text: String) {
        guard
            let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
            let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return
        }
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let pop = activityVC.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(
                x: root.view.bounds.midX - 1,
                y: root.view.safeAreaInsets.top + 44,
                width: 2,
                height: 2
            )
            pop.permittedArrowDirections = [.up, .down]
        }
        root.present(activityVC, animated: true)
    }
}
