// `key`: presses key combinations as if typed, for the scripted demo video: a hotkey daemon runs
// the bound command and a keystroke overlay shows the keys. Posted at the HID tap, so every
// session-level event tap (skhd's, the overlay's) sees them as it sees real key presses.

import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Key codes are positions on an ANSI keyboard: on another layout a letter may sit elsewhere
/// (QWERTZ swaps Y and Z), while the hotkey daemon matches the character the layout types there.
private let keyCodes: [String: Int] = [
  "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
  "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
  "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
  "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
  "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
  "z": kVK_ANSI_Z, "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
  "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8,
  "9": kVK_ANSI_9, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "return": kVK_Return,
  "space": kVK_Space, "tab": kVK_Tab, "escape": kVK_Escape, "left": kVK_LeftArrow,
  "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
]

private let modifierKeyCodes: [(flag: CGEventFlags, keyCode: Int)] = [
  (.maskControl, kVK_Control), (.maskAlternate, kVK_Option), (.maskShift, kVK_Shift),
  (.maskCommand, kVK_Command),
]

private struct KeyCombination {
  let modifiers: CGEventFlags
  let keyCode: CGKeyCode

  /// `option+shift+j`: modifiers as `mod-drag` names them, then one key.
  init?(_ text: String) {
    let parts = text.lowercased().split(separator: "+").map(String.init)
    guard let key = parts.last, let code = keyCodes[key] else { return nil }
    if parts.count == 1 {
      modifiers = []
    } else {
      guard let flags = modifierFlags(parts.dropLast().joined(separator: "+")) else { return nil }
      modifiers = flags
    }
    keyCode = CGKeyCode(code)
  }

  /// The modifiers go down one by one and come up in reverse, as when typed, so an overlay that
  /// shows held modifiers shows them.
  func press(source: CGEventSource) -> Bool {
    let held = modifierKeyCodes.filter { modifiers.contains($0.flag) }
    var events: [CGEvent?] = []
    var flags: CGEventFlags = []
    for modifier in held {
      flags.insert(modifier.flag)
      events.append(event(source, CGKeyCode(modifier.keyCode), isDown: true, flags))
    }
    events.append(event(source, keyCode, isDown: true, flags))
    events.append(event(source, keyCode, isDown: false, flags))
    for modifier in held.reversed() {
      flags.remove(modifier.flag)
      events.append(event(source, CGKeyCode(modifier.keyCode), isDown: false, flags))
    }
    let posted = events.compactMap { $0 }
    guard posted.count == events.count else { return false }
    for event in posted {
      event.post(tap: .cghidEventTap)
      usleep(10_000)
    }
    return true
  }

  private func event(
    _ source: CGEventSource, _ code: CGKeyCode, isDown: Bool, _ flags: CGEventFlags
  ) -> CGEvent? {
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isDown)
    event?.flags = flags
    return event
  }
}

/// `key <combination>...`: presses each combination, 0.1 s apart.
func key(_ arguments: [String]) throws(UsageError) {
  let combinations = arguments.map { KeyCombination($0) }
  guard !arguments.isEmpty, combinations.allSatisfy({ $0 != nil }) else {
    throw UsageError(
      "key <combination>...: modifiers (option, ctrl, cmd, shift) and one key joined by +, "
        + "such as option+shift+j; keys: a-z, 0-9, \",\", \".\", return, space, tab, escape, "
        + "arrows (left, right, up, down)")
  }
  guard let source = CGEventSource(stateID: .privateState) else {
    throw UsageError("key: no event source")
  }
  for (index, combination) in combinations.compactMap({ $0 }).enumerated() {
    if index > 0 { usleep(100_000) }
    guard combination.press(source: source) else {
      throw UsageError("key: creating the events for \(arguments[index]) failed")
    }
  }
}
