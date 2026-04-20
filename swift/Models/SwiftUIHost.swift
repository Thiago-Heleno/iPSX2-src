// SwiftUIHost.swift — ObjC-callable helper to create SwiftUI hosting controllers
// SPDX-License-Identifier: GPL-3.0+

import SwiftUI
import UIKit

/// Custom hosting controller that respects fullScreen state for status bar hiding
class iPSX2HostingController<Content: View>: UIHostingController<Content> {
    override var prefersStatusBarHidden: Bool {
        AppState.shared.hideStatusBar
    }
    override var prefersHomeIndicatorAutoHidden: Bool {
        AppState.shared.hideStatusBar
    }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        .fade
    }
}

@objc public class SwiftUIHost: NSObject {
    @MainActor
    @objc public static func createMenuController() -> UIViewController {
        let hostingController = iPSX2HostingController(rootView: RootView())
        hostingController.view.backgroundColor = .clear
        hostingController.view.isOpaque = false
        return hostingController
    }
}
