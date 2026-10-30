// SPDX-License-Identifier: GPL-3.0-or-later
//
// Keeps a Steam sign-in alive while Akvavit is in the background.
//
// After the password (or the QR code), Madeira asks Steam every few seconds whether
// the sign-in was approved (PollAuthSessionStatus); Steam keeps that session open
// for minutes. Approving it in the Steam app, or reading a Steam Guard code there,
// sends Akvavit to the background, iOS suspends it, and the request in flight
// fails ("network connection lost"). Madeira ended the sign-in on that and showed
// "No internet connection". The polling loops (patches/) now ask again after such
// an error instead; real failures (wrong code, refused, expired) still end it.

import Foundation

enum AkvavitSteamPoll {
    /// Errors that mean the request was interrupted, not that the sign-in failed.
    static func isTransient(_ error: Error) -> Bool {
        guard !Task.isCancelled, let url = error as? URLError else { return false }
        switch url.code {
        case .networkConnectionLost, .notConnectedToInternet, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .secureConnectionFailed, .dataNotAllowed, .internationalRoamingOff,
             .callIsActive, .backgroundSessionWasDisconnected:
            return true
        case .cancelled:
            // URLSession cancels requests of a suspended app; our task wasn't cancelled.
            return true
        default:
            return false
        }
    }

    /// Waits before asking again, logging why (no account details).
    static func pause(after error: Error, seconds: Double) async throws {
        let code = (error as? URLError)?.code.rawValue ?? 0
        SteamLog.event("[steam-signin] poll interrupted (\(code)); asking again")
        try await Task.sleep(nanoseconds: UInt64(max(1, seconds) * 1_000_000_000))
    }
}
