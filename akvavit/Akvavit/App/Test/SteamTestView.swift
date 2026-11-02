// SPDX-License-Identifier: GPL-3.0-or-later
//
// TEMPORARY test screen for AkvavitKit's Steam model: sign-in, games,
// downloads, Valve's client files.

import AkvavitKit
import SwiftUI

struct SteamTestView: View {
    @Binding var showingGame: Bool
    private let steam = Steam.shared
    @State private var account = ""
    @State private var password = ""
    @State private var code = ""
    @State private var clientError: String?
    @State private var reducedX87 = true
    private let jit = JIT.shared
    private let session = Session.shared

    var body: some View {
        List {
            signInSection
            if case .signedIn = steam.signIn {
                clientSection
                Section("Starting games") {
                    Toggle("Reduced-precision x87 (fast Direct3D 8)", isOn: $reducedX87)
                    if !jit.isOn { Text("Enable JIT first.").foregroundStyle(.secondary) }
                    if session.needsRestart { Text("Windows can start once per app run.").foregroundStyle(.secondary) }
                }
                gamesSection
            }
        }
        .navigationTitle("Steam (test)")
    }

    @ViewBuilder private var signInSection: some View {
        Section("Sign-in") {
            switch steam.signIn {
            case .signedIn(let name):
                LabeledContent("Signed in", value: name)
                Button("Sign out", role: .destructive) { steam.signOut() }
            case .busy:
                ProgressView()
                Button("Cancel") { steam.cancelSignIn() }
            case .qrCode(let image):
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit().frame(maxWidth: 240)
                Button("Cancel") { steam.cancelSignIn() }
            case .steamGuard(let needsCode, let canApprove, let emailHint):
                if canApprove { Text("Approve the sign-in in the Steam app, or:") }
                if needsCode {
                    TextField(emailHint.map { "Code sent to \($0)" } ?? "Steam Guard code", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    Button("Send code") { steam.submitSteamGuardCode(code) }
                }
                Button("Cancel") { steam.cancelSignIn() }
            case .signedOut:
                TextField("Account name", text: $account)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                SecureField("Password", text: $password)
                Button("Sign in") { steam.signIn(account: account, password: password); password = "" }
                Button("Sign in with a QR code") { steam.signInWithQRCode() }
            }
            if let error = steam.signInError { Text(error).foregroundStyle(.red) }
        }
    }

    @ViewBuilder private var clientSection: some View {
        Section("Valve's client files (for Dock)") {
            if steam.clientReady {
                Text("Ready").foregroundStyle(.green)
            } else if let progress = steam.clientProgress {
                HStack { ProgressView(); Text(progress) }
            } else {
                Button("Download") {
                    clientError = nil
                    Task {
                        do { try await steam.prepareClient() } catch { clientError = error.localizedDescription }
                    }
                }
            }
            if let clientError { Text(clientError).foregroundStyle(.red) }
        }
    }

    @ViewBuilder private var gamesSection: some View {
        Section {
            if steam.loadingGames { ProgressView() }
            if let error = steam.gamesError { Text(error).foregroundStyle(.red) }
            ForEach(steam.games) { game in
                gameRow(game)
            }
        } header: {
            HStack {
                Text("Games")
                Spacer()
                Button("Refresh") { Task { await steam.refreshGames() } }
            }
        }
        .task { if steam.games.isEmpty { await steam.refreshGames() } }
    }

    @ViewBuilder private func gameRow(_ game: SteamGame) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(game.name)
                Spacer()
                Text("\(game.id)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if let download = Downloads.shared["steam:\(game.id)"] {
                switch download.phase {
                case .failed(let why):
                    Text(why).foregroundStyle(.red).font(.caption)
                    Button("Try again") { Downloads.shared.install("steam:\(game.id)") }
                default:
                    ProgressView(value: download.fraction)
                    Text(describe(download)).font(.caption).foregroundStyle(.secondary)
                    Button("Stop") { Downloads.shared.cancelDownload("steam:\(game.id)") }
                }
            } else if game.installed {
                HStack {
                    Text("Installed").font(.caption).foregroundStyle(.green)
                    Spacer()
                    Button("Play") { play(game) }
                        .disabled(!jit.isOn || session.needsRestart || !steam.clientReady)
                }
            } else {
                Button("Install") { Downloads.shared.install("steam:\(game.id)") }
            }
        }
        .buttonStyle(.borderless)
    }

    private func play(_ game: SteamGame) {
        let (w, h) = TryOutSection.desktopSize()
        session.start(LaunchConfig(program: .steam(appID: game.id), screenWidth: w, screenHeight: h,
                                   reducedPrecisionX87: reducedX87))
        showingGame = true
    }

    private func describe(_ d: GameDownload) -> String {
        let mb = { (b: UInt64) in String(format: "%.0f MB", Double(b) / 1_048_576) }
        switch d.phase {
        case .waiting: return "Waiting"
        case .preparing: return "Preparing"
        case .checking: return "Checking files"
        case .downloading:
            return "\(mb(d.doneBytes)) of \(mb(d.totalBytes)), \(String(format: "%.1f", d.bytesPerSecond / 1_048_576)) MB/s"
        case .finishing: return "Finishing"
        case .failed(let why): return why
        }
    }
}
