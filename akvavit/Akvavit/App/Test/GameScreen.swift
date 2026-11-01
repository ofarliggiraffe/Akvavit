// SPDX-License-Identifier: GPL-3.0-or-later
//
// The screen a session runs on: the picture over the whole display, touches as
// the mouse. While it starts, and after it ends, a status shows instead.

import AkvavitKit
import SwiftUI

struct GameSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> GameSurfaceView {
        let view = GameSurfaceView()
        // Test only: four fingers open the test menu over the game.
        view.onFourFingerTap = { GameOverlay.show(UIHostingController(rootView: TestGameMenu())) }
        return view
    }
    func updateUIView(_ view: GameSurfaceView, context: Context) {}
}

/// TEMPORARY in-game test menu, shown in the overlay window above the game.
struct TestGameMenu: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("Test menu").font(.headline)
            Button("Back to game") { GameOverlay.hide() }
                .buttonStyle(.bordered)
            Button("Quit (closes Akvavit)", role: .destructive) { Session.shared.quit() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameScreen: View {
    private let session = Session.shared

    var body: some View {
        ZStack {
            GameSurface().ignoresSafeArea()
            switch session.state {
            case .idle, .running:
                if let problem = session.dockProblem {
                    Text(problem)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            case .starting(let step):
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text(step).foregroundStyle(.white)
                }
            case .ended(let reason):
                VStack(spacing: 16) {
                    Text(reason == nil ? "The program has ended." : "The program stopped.")
                        .font(.headline)
                    if let reason { Text(reason).multilineTextAlignment(.center) }
                    Text("Windows can start once per app run. Close Akvavit to start another.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Close Akvavit") { exit(0) }
                        .buttonStyle(.borderedProminent)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding()
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }
}

/// Starting points for trying the engine, until there is a library.
struct TryOutSection: View {
    @Binding var showingGame: Bool
    private let jit = JIT.shared
    private let session = Session.shared

    var body: some View {
        Section {
            Button("Spinning cube (Direct3D test)") {
                start(LaunchConfig(program: .direct(executable: "cube.exe")))
            }
            Button("Windows desktop with Wine's settings") {
                let (w, h) = Self.desktopSize()
                start(LaunchConfig(program: .desktop(executable: "winecfg.exe"), screenWidth: w, screenHeight: h))
            }
        } header: {
            Text("Try it")
        } footer: {
            if !jit.isOn {
                Text("Enable JIT first.")
            } else if session.needsRestart {
                Text("Windows can start once per app run. Close Akvavit and open it again to start another.")
            }
        }
        .disabled(!jit.isOn || session.needsRestart)
    }

    private func start(_ config: LaunchConfig) {
        session.start(config)
        showingGame = true
    }

    /// A landscape desktop 768 pixels high, in the shape of this window (the
    /// display the app is on: the Duo's inner and outer ones differ).
    static func desktopSize() -> (Int, Int) {
        PlayStart.fittingSize()
    }
}
