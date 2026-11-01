// Functions Madeira's native engine calls back into the app for. Madeira's
// versions live in its interface files, which AkvavitKit leaves out.
// (akvavit_link_vcruntime_x86 is in AkvavitVCRuntime.swift.)

import Foundation

/// Winios.m and win32u's iOS driver: whether a hardware mouse's events are
/// routed to the game. Madeira's HardwareInput: on unless
/// env.MADEIRA_MOUSE_ROUTING = 0.
@_cdecl("winios_mouse_routing_enabled")
func akvavitMouseRoutingEnabled() -> Int32 {
    let value = MadeiraConfig.get("env.MADEIRA_MOUSE_ROUTING") ?? ProcessInfo.processInfo.environment["MADEIRA_MOUSE_ROUTING"]
    return value == "0" ? 0 : 1
}
