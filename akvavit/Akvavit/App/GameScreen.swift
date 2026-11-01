// SPDX-License-Identifier: GPL-3.0-or-later
//
// The screen a session runs on: the picture over the whole display, touches as
// the mouse. While it starts, and after it ends, a status shows instead.

import AkvavitKit
import SwiftUI

struct GameSurface: UIViewRepresentable {
    func makeUIView(context: Context) -> GameSurfaceView { GameSurfaceView() }
    func updateUIView(_ view: GameSurfaceView, context: Context) {}
}

struct GameScreen: View {
    private let session = Session.shared

    var body: some View {
        ZStack {
            GameSurface().ignoresSafeArea()
            switch session.state {
            case .idle, .running:
                EmptyView()
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
                let (w, h) = desktopSize()
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
    private func desktopSize() -> (Int, Int) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let size = scene?.effectiveGeometry.coordinateSpace.bounds.size ?? CGSize(width: 4, height: 3)
        let aspect = max(size.width, size.height) / max(min(size.width, size.height), 1)
        let width = Int((768 * aspect / 8).rounded()) * 8
        return (width, 768)
    }
}
