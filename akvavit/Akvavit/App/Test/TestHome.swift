// SPDX-License-Identifier: GPL-3.0-or-later
//
// TEMPORARY test screens, only for checking AkvavitKit on the device. The real
// interface replaces everything in Test/.

import AkvavitKit
import SwiftUI

struct TestHome: View {
    @State private var showingGame = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        JITSetupView()
                    } label: {
                        JITStatusRow()
                    }
                    NavigationLink("Steam") { SteamTestView(showingGame: $showingGame) }
                }
                TryOutSection(showingGame: $showingGame)
                Section {
                    NavigationLink("About Akvavit") { AboutView() }
                }
            }
            .navigationTitle("Akvavit (test)")
        }
        .fullScreenCover(isPresented: $showingGame) { GameScreen() }
    }
}

struct JITStatusRow: View {
    private let jit = JIT.shared

    var body: some View {
        LabeledContent("JIT") {
            if jit.busy {
                ProgressView()
            } else {
                Text(jit.isOn ? "On" : "Off")
                    .foregroundStyle(jit.isOn ? .green : .secondary)
            }
        }
    }
}
