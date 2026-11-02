// SPDX-License-Identifier: GPL-3.0-or-later
//
// GOG: the account. GOG has no public API for this; Galaxy, GOG's own client,
// signs in like this, and every community tool does the same:
//
//   1. GOG's sign-in page (auth.gog.com/auth with Galaxy's client ID), shown
//      by the interface in a web view: GOG's page does the password, captcha
//      and two-step code;
//   2. it ends on embed.gog.com/on_login_success with a one-use `code`;
//   3. auth.gog.com/token trades the code for an access token (an hour) and a
//      refresh token, which renews it.
//
// The tokens stay in the Keychain on this device only. Logs never carry a
// token or a code.

import Foundation
import Observation
import Security

@MainActor @Observable
public final class GOGAccount {
    public static let shared = GOGAccount()

    public enum State: Equatable {
        case signedOut
        /// Trading the sign-in page's code for tokens.
        case busy
        case signedIn
    }

    public private(set) var state: State = .signedOut
    /// The account's name on GOG, once known.
    public private(set) var userName: String?
    /// The last sign-in's error, in words.
    public private(set) var error: String?

    public var isSignedIn: Bool { state == .signedIn }

    @ObservationIgnored private var tokens: GOGTokens?
    /// A renewal under way: callers that need a token meanwhile wait for it.
    @ObservationIgnored private var renewing: Task<GOGTokens, Error>?

    private init() {
        tokens = TokenStore.load()
        if tokens != nil {
            state = .signedIn
            userName = UserDefaults.standard.string(forKey: Self.userNameKey)
        }
    }

    // MARK: Sign-in

    // Galaxy's own client: public, the same in every GOG tool.
    private static let clientID = "46899977096215655"
    private static let clientSecret = "9d85c43b1482497dbbce61f6e4aa173a433796eeae2ca8c5f6129f2dc4de46d9"
    private static let redirect = "https://embed.gog.com/on_login_success?origin=client"
    private static let userNameKey = "akvavit.gog.userName"

    /// GOG's sign-in page, for a web view.
    public var signInURL: URL {
        var url = URLComponents(string: "https://auth.gog.com/auth")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirect),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "layout", value: "client2"),
        ]
        return url.url!
    }

    /// The sign-in code, if `url` is the page GOG ends the sign-in on. The
    /// web view stops there and hands the code to `finish(code:)`.
    public nonisolated func signInCode(in url: URL) -> String? {
        guard url.host == "embed.gog.com", url.path == "/on_login_success",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
        return items.first { $0.name == "code" }?.value
    }

    /// Trades the sign-in page's code for tokens.
    public func finish(code: String) async {
        state = .busy
        error = nil
        do {
            let new = try await Self.requestTokens([
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "code", value: code),
                URLQueryItem(name: "redirect_uri", value: Self.redirect),
            ])
            TokenStore.save(new)
            tokens = new
            state = .signedIn
            LogStore.shared.log("[gog] signed in")
            await loadUserName()
        } catch {
            state = .signedOut
            self.error = "GOG didn't sign you in. " + Self.words(error)
            LogStore.shared.log("[gog] sign-in failed: \(Self.words(error))", level: .error)
        }
    }

    /// Forgets the tokens. GOG has no way to revoke them; they expire.
    public func signOut() {
        renewing?.cancel()
        renewing = nil
        tokens = nil
        TokenStore.delete()
        UserDefaults.standard.removeObject(forKey: Self.userNameKey)
        userName = nil
        state = .signedOut
        Games.shared.forgetGOG()
        LogStore.shared.log("[gog] signed out")
    }

    private func loadUserName() async {
        guard let (data, _) = try? await authorized(URL(string: "https://embed.gog.com/userData.json")!),
              let reply = try? JSONDecoder().decode(UserData.self, from: data) else { return }
        userName = reply.username
        UserDefaults.standard.set(reply.username, forKey: Self.userNameKey)
    }

    private struct UserData: Decodable { let username: String }

    // MARK: Requests

    public enum Failure: LocalizedError {
        case signedOut
        case refused(Int)
        case unreadable

        public var errorDescription: String? {
            switch self {
            case .signedOut: "Sign in to GOG first."
            case .refused(let status): "GOG refused the request (\(status))."
            case .unreadable: "GOG's answer couldn't be read."
            }
        }
    }

    /// A GET with the account's access token, renewed first when it is about
    /// to expire. A refusal for the token (401) renews it once and tries again.
    func authorized(_ url: URL) async throws -> (Data, HTTPURLResponse) {
        var token = try await validTokens()
        for attempt in 0..<2 {
            var request = URLRequest(url: url)
            request.setValue("Bearer " + token.accessToken, forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw Failure.unreadable }
            if http.statusCode == 401, attempt == 0 {
                token = try await renew(token)
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw Failure.refused(http.statusCode) }
            return (data, http)
        }
        throw Failure.refused(401)
    }

    private func validTokens() async throws -> GOGTokens {
        guard let tokens else { throw Failure.signedOut }
        if tokens.expires.timeIntervalSinceNow > 5 * 60 { return tokens }
        return try await renew(tokens)
    }

    private func renew(_ old: GOGTokens) async throws -> GOGTokens {
        if let renewing { return try await renewing.value }
        let task = Task {
            try await Self.requestTokens([
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: old.refreshToken),
            ])
        }
        renewing = task
        defer { renewing = nil }
        do {
            let new = try await task.value
            // Signed out meanwhile: keep it that way.
            guard tokens != nil else { throw Failure.signedOut }
            TokenStore.save(new)
            tokens = new
            return new
        } catch Failure.refused(let status) where (400..<500).contains(status) {
            // The refresh token is no longer good: sign in again.
            LogStore.shared.log("[gog] renewal refused (\(status)): signed out", level: .error)
            signOut()
            throw Failure.signedOut
        }
    }

    private static func requestTokens(_ grant: [URLQueryItem]) async throws -> GOGTokens {
        var url = URLComponents(string: "https://auth.gog.com/token")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret),
        ] + grant
        let (data, response) = try await URLSession.shared.data(from: url.url!)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw Failure.refused(status) }
        guard let reply = try? JSONDecoder().decode(TokenReply.self, from: data) else { throw Failure.unreadable }
        return GOGTokens(accessToken: reply.access_token, refreshToken: reply.refresh_token,
                      expires: Date().addingTimeInterval(TimeInterval(reply.expires_in)), userID: reply.user_id)
    }

    private struct TokenReply: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int
        let user_id: String
    }

    static func words(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

struct GOGTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expires: Date
    var userID: String
}

/// The tokens as one Keychain item, on this device only.
private enum TokenStore {
    private static var query: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: (Bundle.main.bundleIdentifier ?? "akvavit") + ".gog",
            kSecAttrAccount: "tokens",
        ]
    }

    static func load() -> GOGTokens? {
        var search = query
        search[kSecReturnData] = true
        search[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(GOGTokens.self, from: data)
    }

    static func save(_ tokens: GOGTokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let update: [CFString: Any] = [kSecValueData: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData] = data
            add[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
