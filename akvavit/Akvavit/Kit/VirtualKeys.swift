// SPDX-License-Identifier: GPL-3.0-or-later
//
// Windows virtual keys (VK_*), which the engine takes for key presses, and
// their names. The engine's driver derives the scan codes for a US layout.

import Foundation

public enum VirtualKey {
    public static let backspace = 0x08
    public static let tab = 0x09
    public static let enter = 0x0D
    public static let shift = 0x10
    public static let ctrl = 0x11
    public static let alt = 0x12
    public static let pause = 0x13
    public static let escape = 0x1B
    public static let space = 0x20
    public static let pageUp = 0x21
    public static let pageDown = 0x22
    public static let end = 0x23
    public static let home = 0x24
    public static let left = 0x25
    public static let up = 0x26
    public static let right = 0x27
    public static let down = 0x28
    public static let printScreen = 0x2C
    public static let insert = 0x2D
    public static let delete = 0x2E
    public static let windows = 0x5B
    public static let f1 = 0x70

    private static let names: [Int: String] = [
        backspace: "Backspace", tab: "Tab", enter: "Enter", shift: "Shift", ctrl: "Ctrl", alt: "Alt",
        pause: "Pause", escape: "Esc", space: "Space", pageUp: "Page Up", pageDown: "Page Down",
        end: "End", home: "Home", left: "Left", up: "Up", right: "Right", down: "Down",
        printScreen: "Print Screen", insert: "Insert", delete: "Delete", windows: "Windows",
        0x6A: "Num *", 0x6B: "Num +", 0x6D: "Num -", 0x6E: "Num .", 0x6F: "Num /",
        0xBA: ";", 0xBB: "=", 0xBC: ",", 0xBD: "-", 0xBE: ".", 0xBF: "/", 0xC0: "`",
        0xDB: "[", 0xDC: "\\", 0xDD: "]", 0xDE: "'",
    ]

    /// The key's name as a keyboard shows it ("Ctrl", "F5", "E", "1").
    public static func name(_ vk: Int) -> String {
        if let name = names[vk] { return name }
        switch vk {
        case 0x30...0x39, 0x41...0x5A: return String(UnicodeScalar(UInt8(vk)))
        case 0x60...0x69: return "Num \(vk - 0x60)"
        case 0x70...0x87: return "F\(vk - 0x70 + 1)"
        default: return String(format: "Key %02X", vk)
        }
    }
}
