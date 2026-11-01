// SPDX-License-Identifier: GPL-3.0-or-later
//
// TEMPORARY: stand-in games for the flip spike (step 1), with colour covers.
// Step 2 replaces them with AkvavitKit's game list and real covers.

import SwiftUI

struct PlaceholderGame: Identifiable, Hashable {
    let id: String
    let name: String
    let coverTop: UInt32
    let coverBottom: UInt32
    let released: String
    let size: String?

    static let library: [PlaceholderGame] = [
        .init(id: "steam:7610", name: "Railroad Tycoon 3", coverTop: 0xC9772F, coverBottom: 0x4F250F,
              released: "2003", size: nil),
        .init(id: "steam:7620", name: "Railroad Tycoon II Platinum", coverTop: 0x2F7090, coverBottom: 0x13263A,
              released: "1999", size: "669 MB"),
        .init(id: "steam:400", name: "Portal", coverTop: 0x8E98A3, coverBottom: 0x333942,
              released: "2007", size: nil),
        .init(id: "steam:620", name: "Portal 2", coverTop: 0x4A8FD0, coverBottom: 0x18294A,
              released: "2011", size: nil),
        .init(id: "steam:221380", name: "Age of Empires II HD", coverTop: 0xB8933A, coverBottom: 0x43300F,
              released: "2013", size: nil),
        .init(id: "steam:813780", name: "Age of Empires II: Definitive Edition", coverTop: 0x8A4030,
              coverBottom: 0x26120E, released: "2019", size: nil),
    ]
}
