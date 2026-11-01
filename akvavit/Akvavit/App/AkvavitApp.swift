// SPDX-License-Identifier: GPL-3.0-or-later

import AkvavitKit
import SwiftUI

@main
struct AkvavitApp: App {
    init() {
        AkvavitEngine.start()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

struct HomeView: View {
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
                }
                TryOutSection(showingGame: $showingGame)
                Section {
                    NavigationLink("About Akvavit") { AboutView() }
                }
            }
            .navigationTitle("Akvavit")
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
