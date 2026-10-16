// ============================================================================
//  Speak Anywhere -- one speak key in every app on this Mac
// ============================================================================
//
// WHY (Gavin, 2 and 15 Oct 2026; dotfiles-main Q12 (v2): 2)
// The speak key lived only in herdr (ctrl+alt+backtick), because herdr was the
// only thing listening for it. On 2 Oct Gavin asked for cmd+option+backtick at
// the macOS level, "the convenience of using the same keyboard shortcut", with
// one firm rule: "I didn't want the previous clipboard contents to be lost or
// overwritten", with "the least downtime". This helper is that key.
//
// WHAT ONE PRESS DOES
//   * speech playing (speak-clipboard's speaker is alive): stop it, nothing
//     else -- checked first, so a stop never waits on a copy
//   * a terminal is in front (iTerm2, Ghostty, Terminal): speak the clipboard,
//     exactly as the herdr key does. herdr owns the highlight there and a drag
//     has already copied, so there is nothing better to read
//   * any other app: read the highlight
//       1. ask the app for its selected text through the accessibility API;
//          the clipboard is never touched
//       2. if the app does not answer, copy: snapshot every clipboard item and
//          type, send Cmd+C, wait up to 500 ms for the clipboard to change,
//          read the text, put the snapshot back
//       3. nothing highlighted: speak the clipboard, as in a terminal
//   The text is handed to `speak-clipboard --toggle --stdin`, so the voice,
//   speed, pauses and cleaner are the same as every other speak key.
//
// Cmd+C is sent only after Command and Option are let go: an app reads the
// keys that are physically down, and Cmd+Option+C is a different command
// (Finder: copy the path).
//
// NEEDS Accessibility permission (System Settings > Privacy & Security >
// Accessibility > Speak Anywhere) to read a highlight and to send Cmd+C.
// Catching the key needs no permission. Without it, every press speaks the
// clipboard and the log says "no-permission".
//
// LOG: ~/.local/state/herdr/speak-anywhere.log, one line per press: when, the
// app in front, how the text was found, how many characters. Never the text.
//
// Built and installed by `speak-anywhere --install`; see that script.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

let home = FileManager.default.homeDirectoryForCurrentUser.path
let speakClipboard = home + "/.local/bin/speak-clipboard"
let stateDir = (ProcessInfo.processInfo.environment["XDG_STATE_HOME"] ?? home + "/.local/state") + "/herdr"
let logPath = stateDir + "/speak-anywhere.log"
let pidFile = stateDir + "/speak-render.pid"
let terminals: Set<String> = ["com.googlecode.iterm2", "com.mitchellh.ghostty", "com.apple.Terminal"]
let copyTimeout = 0.5

func stamp() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_AU")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    return f.string(from: Date())
}

func log(_ line: String) {
    let text = "\(stamp()) \(line)\n"
    try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)
    if let h = FileHandle(forWritingAtPath: logPath) {
        h.seekToEndOfFile()
        h.write(text.data(using: .utf8)!)
        h.closeFile()
    } else {
        FileManager.default.createFile(atPath: logPath, contents: text.data(using: .utf8))
    }
}

// Runs a program and returns its stdout. stdin, when given, is written then closed.
@discardableResult
func run(_ path: String, _ args: [String], stdin: String? = nil, env: [String: String] = [:]) -> (Int32, String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    var e = ProcessInfo.processInfo.environment
    e["LANG"] = "en_AU.UTF-8"
    e["LC_ALL"] = "en_AU.UTF-8"
    for (k, v) in env { e[k] = v }
    p.environment = e
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    let inPipe = Pipe()
    if stdin != nil { p.standardInput = inPipe } else { p.standardInput = FileHandle.nullDevice }
    do { try p.run() } catch { return (127, "") }
    if let s = stdin {
        inPipe.fileHandleForWriting.write(s.data(using: .utf8) ?? Data())
        inPipe.fileHandleForWriting.closeFile()
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

// The same test as speak-clipboard's speaker_alive: the pid file's process
// must have the recorded start time AND be one of ours, because pids are
// recycled. A wrong "alive" only costs a clipboard read: --toggle decides again.
func speakerAlive() -> Bool {
    guard let body = try? String(contentsOfFile: pidFile, encoding: .utf8) else { return false }
    let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard lines.count >= 2, let pid = Int32(lines[0]), pid > 0, !lines[1].isEmpty else { return false }
    let (_, start) = run("/bin/ps", ["-o", "lstart=", "-p", String(pid)], env: ["LC_ALL": "C", "LANG": "C"])
    guard start.filter({ !$0.isWhitespace }) == lines[1] else { return false }
    let (_, commRaw) = run("/bin/ps", ["-o", "comm=", "-p", String(pid)])
    let comm = (commRaw.trimmingCharacters(in: .whitespacesAndNewlines) as NSString).lastPathComponent
    if comm == "say2" || comm == "say" { return true }
    if comm.hasPrefix("perl") && lines.count >= 3 && lines[2] == "line" { return true }
    let (_, group) = run("/usr/bin/pgrep", ["-g", String(pid), "-x", "say2|ffplay"])
    return !comm.isEmpty && !group.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

// ---------------------------------------------------------------- the highlight

func axSelectedText() -> String? {
    let system = AXUIElementCreateSystemWide()
    var focused: CFTypeRef?
    guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
          let element = focused else { return nil }
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
          let text = value as? String else { return nil }
    return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
}

typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

func snapshot(_ pb: NSPasteboard) -> Snapshot {
    (pb.pasteboardItems ?? []).map { item in
        item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
    }
}

func restore(_ pb: NSPasteboard, _ snap: Snapshot) {
    pb.clearContents()
    let items: [NSPasteboardItem] = snap.map { pairs in
        let it = NSPasteboardItem()
        for (t, d) in pairs { it.setData(d, forType: t) }
        return it
    }
    if !items.isEmpty { pb.writeObjects(items) }
}

// Every item, every type and every byte must match.
func same(_ a: Snapshot, _ b: Snapshot) -> Bool {
    guard a.count == b.count else { return false }
    for (x, y) in zip(a, b) {
        guard x.count == y.count else { return false }
        for (p, q) in zip(x, y) where p.0 != q.0 || p.1 != q.1 { return false }
    }
    return true
}

// Waits until Command, Option, Control and Shift are all up (at most 1.5 s).
func waitForModifiersUp() -> Bool {
    let held: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
    let end = Date().addingTimeInterval(1.5)
    while Date() < end {
        if CGEventSource.flagsState(.hidSystemState).intersection(held).isEmpty { return true }
        usleep(10_000)
    }
    return false
}

func sendCopy() {
    let src = CGEventSource(stateID: .combinedSessionState)
    let c = CGKeyCode(kVK_ANSI_C)
    let down = CGEvent(keyboardEventSource: src, virtualKey: c, keyDown: true)
    let up = CGEvent(keyboardEventSource: src, virtualKey: c, keyDown: false)
    down?.flags = .maskCommand
    up?.flags = .maskCommand
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

// Copies the highlight and puts the clipboard back. nil when nothing changed.
func copyHighlight() -> (String?, String) {
    let pb = NSPasteboard.general
    let snap = snapshot(pb)
    let before = pb.changeCount
    guard waitForModifiersUp() else { return (nil, "keys-held") }
    sendCopy()
    let end = Date().addingTimeInterval(copyTimeout)
    while pb.changeCount == before && Date() < end { usleep(10_000) }
    if pb.changeCount == before { return (nil, "nothing-copied") }
    usleep(30_000)  // let an app that writes in two steps finish
    let text = pb.string(forType: .string)
    restore(pb, snap)
    let ok = same(snapshot(pb), snap)
    return (text, ok ? "restored" : "RESTORE-MISMATCH")
}

// ---------------------------------------------------------------- one press

let work = DispatchQueue(label: "speak-anywhere")
var busy = false

func press() {
    let t0 = Date()
    let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    func ms() -> Int { Int(Date().timeIntervalSince(t0) * 1000) }

    if speakerAlive() {
        run(speakClipboard, ["--toggle"])
        log("app=\(app) path=stop ms=\(ms())")
        return
    }
    if terminals.contains(app) {
        let (rc, _) = run(speakClipboard, ["--toggle"])
        log("app=\(app) path=terminal-clipboard rc=\(rc) ms=\(ms())")
        return
    }
    guard AXIsProcessTrusted() else {
        let (rc, _) = run(speakClipboard, ["--toggle"])
        log("app=\(app) path=no-permission clipboard rc=\(rc) ms=\(ms())")
        return
    }
    if let text = axSelectedText() {
        let (rc, _) = run(speakClipboard, ["--toggle", "--stdin"], stdin: text)
        log("app=\(app) path=ax chars=\(text.count) rc=\(rc) ms=\(ms())")
        return
    }
    let (copied, note) = copyHighlight()
    if let text = copied, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let (rc, _) = run(speakClipboard, ["--toggle", "--stdin"], stdin: text)
        log("app=\(app) path=copy \(note) chars=\(text.count) rc=\(rc) ms=\(ms())")
        return
    }
    let (rc, _) = run(speakClipboard, ["--toggle"])
    log("app=\(app) path=clipboard \(note) rc=\(rc) ms=\(ms())")
}

// ---------------------------------------------------------------- self-test

// --selftest-restore: three arms, then the live clipboard is put back.
//   live:   the clipboard as it is now survives a marker write and a restore
//   rich:   two items, each with plain, rich and web text and a PNG, survive too
//   broken: a snapshot with one byte changed must NOT compare equal (control)
// Borrows the live clipboard for a few milliseconds only.
if CommandLine.arguments.contains("--selftest-restore") {
    let pb = NSPasteboard.general
    let live = snapshot(pb)
    func roundTrip(_ snap: Snapshot) -> Bool {
        pb.clearContents()
        pb.setString("speak-anywhere selftest marker", forType: .string)
        guard pb.string(forType: .string) == "speak-anywhere selftest marker" else { return false }
        restore(pb, snap)
        return same(snapshot(pb), snap)
    }
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: UInt8(7), count: 64))
    let rich: Snapshot = (1...2).map { n in [
        (.string, "item \(n) plain".data(using: .utf8)!),
        (.rtf, "{\\rtf1 item \(n)}".data(using: .utf8)!),
        (.html, "<b>item \(n)</b>".data(using: .utf8)!),
        (.png, png),
    ] }
    // Written as an app would, then snapshotted: macOS adds a derived UTF-16
    // text type of its own, so the snapshot, not the list above, is the truth.
    restore(pb, rich)
    let richSnap = snapshot(pb)
    let richOK = richSnap.count == 2 && roundTrip(richSnap)
    var broken = richSnap
    if let i = broken[1].firstIndex(where: { $0.0 == .png }) {
        var bytes = [UInt8](broken[1][i].1); bytes[bytes.count - 1] ^= 1
        broken[1][i] = (.png, Data(bytes))
    }
    let controlOK = !same(richSnap, broken)
    let liveOK = roundTrip(live)
    let types = live.reduce(0) { $0 + $1.count }
    print("live: items=\(live.count) types=\(types) restored=\(liveOK)")
    print("rich: items=\(richSnap.count) types=\(richSnap.reduce(0) { $0 + $1.count }) restored=\(richOK)")
    print("broken control: told apart=\(controlOK)")
    exit(liveOK && richOK && controlOK ? 0 : 1)
}

// ---------------------------------------------------------------- the key

var hotKeyRef: EventHotKeyRef?
var pendingTimer: DispatchSourceTimer?
var handlerRef: EventHandlerRef?
var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
    work.async {
        if busy { log("path=busy"); return }
        busy = true
        press()
        busy = false
    }
    return noErr
}, 1, &spec, nil, &handlerRef)

let hotKeyID = EventHotKeyID(signature: OSType(0x53504B41), id: 1)  // "SPKA"
let status = RegisterEventHotKey(UInt32(kVK_ANSI_Grave), UInt32(cmdKey | optionKey), hotKeyID,
                                 GetApplicationEventTarget(), 0, &hotKeyRef)
if status != noErr {
    log("start FAILED: cmd+option+backtick could not be registered (status \(status)); another app may own it")
    exit(3)
}

// Ask once for Accessibility; macOS shows its own prompt if it is missing.
let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(opts)
log("start ok: cmd+option+backtick registered, accessibility=\(trusted ? "yes" : "NO (clipboard only until granted)")")

// Say so in the log the moment Accessibility is granted, so the status shows
// the helper's own permission. (Asked from a terminal, the answer would be the
// terminal's permission, not this app's.)
if !trusted {
    let timer = DispatchSource.makeTimerSource(queue: work)
    timer.schedule(deadline: .now() + 5, repeating: 5)
    timer.setEventHandler {
        if AXIsProcessTrusted() { log("accessibility granted"); timer.cancel() }
    }
    timer.resume()
    pendingTimer = timer
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
app.run()
