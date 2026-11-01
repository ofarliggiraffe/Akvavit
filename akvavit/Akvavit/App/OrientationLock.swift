// SPDX-License-Identifier: GPL-3.0-or-later
//
// Landscape only while the controls studio or a game's screen is up: Windows'
// screen is always landscape, and the studio shows the game screen at its
// real size. The rest of the app turns freely. (On an iPad in a resizable
// window iOS doesn't turn the window; it then just fills it.)

import UIKit

@MainActor
enum OrientationLock {
    private static var holders = 0

    /// What the app allows now (AppDelegate answers iOS with it).
    static var allowed: UIInterfaceOrientationMask {
        holders > 0 ? .landscape : UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    /// Landscape until `unlock()` (one unlock per lock).
    static func lock() {
        holders += 1
        if holders == 1 { apply() }
    }

    static func unlock() {
        guard holders > 0 else { return }
        holders -= 1
        if holders == 0 { apply() }
    }

    private static func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                var controller = window.rootViewController
                while let current = controller {
                    current.setNeedsUpdateOfSupportedInterfaceOrientations()
                    controller = current.presentedViewController
                }
            }
            if holders > 0, !scene.effectiveGeometry.interfaceOrientation.isLandscape {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.allowed
    }
}
