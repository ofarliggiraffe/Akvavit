// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct AboutView: View {
    var body: some View {
        Form {
            Section {
                Text("Akvavit runs Windows games with Madeira's engine: FEX-Emu, Wine and DXMT, ported to iOS by the [Madeira project](https://github.com/willfaust/Madeira). Getting Windows games to run on an iPhone is their work, and the credit for it goes to them.")
                Text("Akvavit is an app around that engine. It is free software under the GNU General Public License, version 3 or later.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("About")
    }
}
