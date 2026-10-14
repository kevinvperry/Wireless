import SwiftUI
import AVKit

// Copied from Autohop's AudioRoutePickerView and retained as the shared Player
// presentation pattern. The full visible selector opens Apple's route sheet,
// rather than limiting taps to AVRoutePickerView's internal glyph.
private final class ExpandedHitAreaRoutePickerView: AVRoutePickerView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled,
              !isHidden,
              alpha > 0.01,
              self.point(inside: point, with: event) else {
            return nil
        }

        return routeButton(in: self) ?? super.hitTest(point, with: event)
    }

    private func routeButton(in view: UIView) -> UIButton? {
        if let button = view as? UIButton,
           button.isEnabled,
           !button.isHidden,
           button.alpha > 0.01 {
            return button
        }

        for subview in view.subviews {
            if let button = routeButton(in: subview) {
                return button
            }
        }
        return nil
    }
}

struct AudioRoutePickerView: UIViewRepresentable {
    var tintColor: UIColor = .systemPurple

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = ExpandedHitAreaRoutePickerView()
        view.tintColor = tintColor
        view.activeTintColor = tintColor
        view.prioritizesVideoDevices = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        uiView.tintColor = tintColor
        uiView.activeTintColor = tintColor
    }
}
