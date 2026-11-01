// SPDX-License-Identifier: GPL-3.0-or-later
//
// Facts about the account's games that SwiftSteam doesn't read: release years
// (from Steam's product info) and the account's playtime (Player.GetOwnedGames).
// Both go over the signed-in connection.

import Foundation

extension Steam {
    /// Release years by app ID: `steam_release_date`, else
    /// `original_release_date` (Unix times) in the product info's `common`.
    /// Apps without either are left out.
    func releaseYears(_ appIDs: [Int]) async throws -> [Int: Int] {
        guard !appIDs.isEmpty else { return [:] }
        try await session.ensureConnected()
        var years: [Int: Int] = [:]
        for start in stride(from: 0, to: appIDs.count, by: 50) {
            let batch = appIDs[start..<min(start + 50, appIDs.count)].map { UInt32($0) }

            var tokenRequest = CMsgClientPICSAccessTokenRequest()
            tokenRequest.appids = batch
            let tokenReply = try await session.sendAndWait(eMsg: .clientPICSAccessTokenRequest,
                                                           body: tokenRequest.serialize(),
                                                           responseEMsg: .clientPICSAccessTokenResponse,
                                                           timeout: 30)
            let tokens = try CMsgClientPICSAccessTokenResponse.deserialize(from: tokenReply.body).appAccessTokens
            let tokenFor = Dictionary(tokens.map { ($0.appid, $0.accessToken) }, uniquingKeysWith: { a, _ in a })

            var request = CMsgClientPICSProductInfoRequest()
            request.apps = batch.map { .init(appid: $0, accessToken: tokenFor[$0] ?? 0) }
            let replies = try await session.sendAndWaitPICS(eMsg: .clientPICSProductInfoRequest,
                                                            body: request.serialize(), timeout: 30)
            let buffers = try replies.flatMap { reply in
                try CMsgClientPICSProductInfoResponse.deserialize(from: reply.body).apps.map { ($0.appid, $0.buffer) }
            }
            // Parsing whole product info texts is slow; not on the main thread.
            let found = await Task.detached(priority: .utility) {
                var found: [Int: Int] = [:]
                for (appID, buffer) in buffers {
                    if let year = Self.releaseYear(appID: appID, productInfo: buffer) { found[Int(appID)] = year }
                }
                return found
            }.value
            years.merge(found) { $1 }
        }
        return years
    }

    nonisolated private static func releaseYear(appID: UInt32, productInfo: Data) -> Int? {
        let root = VDFParser.parseTextVDF(from: productInfo)
        let app = (root["appinfo"] as? [String: Any]) ?? (root["\(appID)"] as? [String: Any]) ?? root
        guard let common = app["common"] as? [String: Any] else { return nil }
        for key in ["steam_release_date", "original_release_date"] {
            guard let text = common[key] as? String, let seconds = TimeInterval(text), seconds > 0 else { continue }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar.component(.year, from: Date(timeIntervalSince1970: seconds))
        }
        return nil
    }

    /// The account's playtime by app ID, in minutes (games never played: 0).
    func playtimes() async throws -> [Int: Int] {
        try await session.ensureConnected()
        // CPlayer_GetOwnedGames_Request: steamid = 1, include_played_free_games = 3.
        var request = ProtobufEncoder()
        request.writeUInt64(fieldNumber: 1, value: session.steamID)
        request.writeBool(fieldNumber: 3, value: true)
        let reply = try await session.callServiceMethod(method: .getOwnedGames, body: request.data, timeout: 20)

        // CPlayer_GetOwnedGames_Response: games = 2, each with appid = 1 and
        // playtime_forever = 4 (minutes).
        var minutes: [Int: Int] = [:]
        var response = ProtobufDecoder(reply)
        while let (field, wireType) = try response.readTag() {
            guard field == 2, wireType == .lengthDelimited else {
                try response.skip(wireType: wireType)
                continue
            }
            var game = ProtobufDecoder(try response.readBytes())
            var appID = 0, played = 0
            while let (gameField, gameWireType) = try game.readTag() {
                switch (gameField, gameWireType) {
                case (1, .varint): appID = Int(truncatingIfNeeded: try game.readVarint())
                case (4, .varint): played = Int(truncatingIfNeeded: try game.readVarint())
                default: try game.skip(wireType: gameWireType)
                }
            }
            if appID > 0 { minutes[appID] = played }
        }
        return minutes
    }
}
