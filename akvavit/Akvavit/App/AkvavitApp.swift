// SPDX-License-Identifier: GPL-3.0-or-later

import AkvavitKit
import SwiftUI

@main
struct AkvavitApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        AkvavitEngine.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
