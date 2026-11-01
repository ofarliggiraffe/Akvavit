// SPDX-License-Identifier: GPL-3.0-or-later
//
// The screen a session runs on: the picture over the whole display, touches as
// the mouse, the chosen controls over it. While it starts the loading screen
// covers it (until the game is up); after it ends, a status shows instead.

import AkvavitKit
import SwiftUI

struct GameSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> GameSurfaceView {
        let view = GameSurfaceView()
        // Test only: four fingers open the test menu over the game.
        view.onFourFingerTap = { ControlsOverlay.shared.showMenu() }
        return view
    }
    func updateUIView(_ view: GameSurfaceView, context: Context) {}
}

/// TEMPORARY in-game test menu, shown over the controls above the game. It
/// also chooses the controls' layout until games choose theirs.
struct TestGameMenu: View {
    let close: () -> Void
    private let store = ControlLayoutStore.shared
    private let runtime = ControlsRuntime.shared

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Controls").font(.headline)
                ForEach(store.all) { layout in
                    Button { TestLayoutChoice.choose(layout) } label: {
                        HStack {
                            Text(layout.name)
                            Spacer()
                            if runtime.layout?.id == layout.id { Image(systemName: "checkmark") }
                        }
                        .frame(width: 220)
                    }
                    .buttonStyle(.bordered)
                }
                // Not saved: the studio's layout menu sets it for good.
                Toggle("Touch on the game as mouse", isOn: Binding(
                    get: { runtime.touchAsMouse },
                    set: { on in
                        guard var layout = runtime.layout else { return }
                        layout.gameTouch = on ? .mouse : .off
                        runtime.use(layout)
                    }))
                .frame(width: 252)
                if !StartProgress.shared.gameIsUp {
                    // A way out if the loading screen misses a game's window.
                    Toggle("Show Windows' screen", isOn: Binding(
                        get: { StartProgress.shared.showingWindows },
                        set: { StartProgress.shared.setShowingWindows($0) }))
                    .frame(width: 252)
                }
            }
            VStack(spacing: 12) {
                Text("Test menu").font(.headline)
                Button("Back to game", action: close)
                    .buttonStyle(.bordered)
                Button("Show keyboard") {
                    close()
                    TextBridge.shared.show()
                }
                .buttonStyle(.bordered)
                Button("Quit (closes Akvavit)", role: .destructive) { Session.shared.quit() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct GameScreen: View {
    private let session = Session.shared
    private let progress = StartProgress.shared

    var body: some View {
        ZStack {
            GameSurface().ignoresSafeArea()
            switch session.state {
            case .idle, .starting, .running:
                // The loading screen itself is in the overlay window, above
                // Windows' screen (ControlsOverlay); its background here too,
                // for the moment before that window shows.
                if progress.covers {
                    ThemeBackground().ignoresSafeArea().allowsHitTesting(false)
                } else if let problem = session.dockProblem {
                    Text(problem)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding()
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            case .ended where progress.covers:
                // A problem before the game was up: the loading screen says it.
                ThemeBackground().ignoresSafeArea().allowsHitTesting(false)
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
        // Windows' screen is landscape, and so are the controls (as in the studio).
        .onAppear {
            OrientationLock.lock()
            // The overlay window at once: the loading screen is in it, and the
            // controls show there once the game is up.
            ControlsOverlay.shared.show()
        }
        .onDisappear { OrientationLock.unlock() }
        .animation(.easeOut(duration: 0.5), value: progress.covers)
        .onChange(of: session.state, initial: true) { _, state in
            switch state {
            case .running: ControlsOverlay.shared.show()
            // The overlay stays while the loading screen shows a problem.
            case .ended where !progress.covers: ControlsOverlay.shared.hide()
            case .ended, .idle, .starting: break
            }
        }
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
