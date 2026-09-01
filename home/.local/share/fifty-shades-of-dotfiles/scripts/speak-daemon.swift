// speak-daemon -- a persistent NSSpeechSynthesizer server, so speak-clipboard's
// toggle key doesn't pay the ~1s "Aaron" voice-load cost on every single press.
//
// WHY THIS EXISTS
// ----------------
// Measured (2026-09-01): `say`/NSSpeechSynthesizer costs ~1.0s on its first
// utterance in a fresh process, ~0.78s on later utterances IN THE SAME process.
// The fast alternative (AVSpeechSynthesizer, ~30ms even cold) cannot reach the
// "Aaron" voice at all -- confirmed by direct identifier lookup, not just
// absence from its voice list. So the only way to keep Aaron AND avoid paying
// that cost on every keypress is to keep one process, and one NSSpeechSynthesizer
// instance, alive across presses. That is all this program does.
//
// PROTOCOL
// --------
// A client connects to the Unix socket, writes:
//   line 1: mode -- SPEAK, STOP, or TOGGLE
//   line 2: rate (words per minute) as a number, or empty for the default
//   line 3: voice identifier, or empty for the default (Aaron)
//   line 4 onward: the text to speak (only used by SPEAK/TOGGLE)
// then closes its write side. The daemon reads until EOF, closes immediately
// (it does not wait for speech to finish), and speaks/stops in the background.
//
// SINGLETON
// ---------
// On startup this tries to CONNECT to its own socket path first. A successful
// connect means another instance is already listening, so this one exits
// immediately rather than fighting over the socket file.
//
// RENDER-THEN-PLAY, NOT LIVE SPEAKING (2026-09-01)
// -------------------------------------------------
// Reported: speech through this daemon sounded muffled, "like someone
// blowing into the microphone" -- while the identical text/voice/rate
// rendered to a FILE (via startSpeaking(_:to:)) sounded correct, confirmed
// byte-identical to `say`'s own file output. So NSSpeechSynthesizer's LIVE
// playback path specifically is where the artifact comes from -- most
// likely the file is 22050 Hz and something in that live path is not
// converting it cleanly to the real output device rate. Rather than debug
// Apple's internal live-audio pipeline, this renders to a temp file (the
// path already proven clean) and plays that file back with AVAudioPlayer,
// which is a standard, well-tested API for exactly this kind of format/rate
// negotiation. Each call uses a unique temp filename so a rapid second
// press can never race the first press's still-in-use file.
import Foundation
import AppKit
import AVFoundation
import Darwin

let defaultVoiceId = "com.apple.ttsbundle.gryphon-neuralAX_Aaron_en-US_premium"
let defaultRate: Float = 420
let traceMax = 200

let stateDir = (ProcessInfo.processInfo.environment["XDG_STATE_HOME"] ?? (NSHomeDirectory() + "/.local/state")) + "/herdr"
let socketPath = stateDir + "/speak-daemon.sock"
let traceFile = stateDir + "/speak-daemon.log"

func trace(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    let entry = "\(stamp) \(line)\n"
    guard let handle = FileHandle(forWritingAtPath: traceFile) else {
        FileManager.default.createFile(atPath: traceFile, contents: entry.data(using: .utf8))
        return
    }
    handle.seekToEndOfFile()
    handle.write(entry.data(using: .utf8)!)
    handle.closeFile()

    if let content = try? String(contentsOfFile: traceFile, encoding: .utf8) {
        var lines = content.split(separator: "\n", omittingEmptySubsequences: true)
        if lines.count > traceMax {
            lines = Array(lines.suffix(traceMax))
            try? (lines.joined(separator: "\n") + "\n").write(toFile: traceFile, atomically: true, encoding: .utf8)
        }
    }
}

func makeSockaddr(_ path: String) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: ptr.pointee)) { cptr in
            path.withCString { strncpy(cptr, $0, MemoryLayout.size(ofValue: ptr.pointee) - 1) }
        }
    }
    return addr
}

func tryConnectExisting(_ path: String) -> Bool {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var addr = makeSockaddr(path)
    let len = socklen_t(MemoryLayout<sa_family_t>.size + path.utf8.count + 1)
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, len) }
    }
    return result == 0
}

try? FileManager.default.createDirectory(atPath: stateDir, withIntermediateDirectories: true)

if tryConnectExisting(socketPath) {
    exit(0)
}
unlink(socketPath)

let listenFd = socket(AF_UNIX, SOCK_STREAM, 0)
guard listenFd >= 0 else { fatalError("socket() failed: \(String(cString: strerror(errno)))") }

var bindAddr = makeSockaddr(socketPath)
let bindLen = socklen_t(MemoryLayout<sa_family_t>.size + socketPath.utf8.count + 1)
let bindResult = withUnsafePointer(to: &bindAddr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFd, $0, bindLen) }
}
guard bindResult == 0 else { fatalError("bind() failed: \(String(cString: strerror(errno)))") }
guard listen(listenFd, 8) == 0 else { fatalError("listen() failed: \(String(cString: strerror(errno)))") }

trace("start pid=\(ProcessInfo.processInfo.processIdentifier)")

// Prevent App Nap (reduced scheduling priority, throttled timers/I-O for a
// windowless background process). Tried first as the fix for the muffled-
// audio report below; confirmed via `pmset -g assertions` to be genuinely
// active, and made no audible difference -- so App Nap was NOT the actual
// cause. Left in place anyway since a daemon with degraded scheduling
// priority is a bad idea regardless; the real fix is RENDER-THEN-PLAY above.
// The returned token is deliberately never released -- it stays in effect
// for the daemon's whole lifetime.
let activityToken = ProcessInfo.processInfo.beginActivity(
    options: [.userInitiated, .latencyCritical],
    reason: "speech playback must not be throttled"
)

final class SpeechHandler: NSObject, NSSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    let synth: NSSpeechSynthesizer?
    var player: AVAudioPlayer?
    var renderPath: String?

    override init() {
        synth = NSSpeechSynthesizer(voice: NSSpeechSynthesizer.VoiceName(rawValue: defaultVoiceId))
        super.init()
        synth?.rate = defaultRate
        synth?.delegate = self
    }

    func speak(_ text: String, rate: Float?, voice: String?) {
        if let voice = voice, !voice.isEmpty {
            synth?.setVoice(NSSpeechSynthesizer.VoiceName(rawValue: voice))
        }
        synth?.rate = rate ?? defaultRate
        let path = NSTemporaryDirectory() + "speak-daemon-\(UUID().uuidString).aiff"
        renderPath = path
        _ = synth?.startSpeaking(text, to: URL(fileURLWithPath: path))
    }

    // Fires when RENDERING (to file) finishes -- not when playback finishes.
    // finishedSpeaking is false if stop() interrupted the render, in which
    // case there is a partial/no file and nothing should be played.
    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finishedSpeaking: Bool) {
        guard finishedSpeaking, let path = renderPath else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: path))
            p.delegate = self
            player = p
            p.play()
        } catch {
            trace("playback failed: \(error)")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        if let path = renderPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        renderPath = nil
    }

    func stop() {
        synth?.stopSpeaking()   // interrupts a still-in-progress render
        player?.stop()          // interrupts an already-playing utterance
        player = nil
        if let path = renderPath {
            try? FileManager.default.removeItem(atPath: path)
        }
        renderPath = nil
    }

    var isSpeaking: Bool {
        (synth?.isSpeaking ?? false) || (player?.isPlaying ?? false)
    }
}

let handler = SpeechHandler()

func handleConnection(_ clientFd: Int32) {
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(clientFd, &buf, buf.count)
        if n <= 0 { break }
        data.append(contentsOf: buf[0..<n])
    }
    close(clientFd)

    guard let message = String(data: data, encoding: .utf8) else { return }
    // A zero-byte connection is another speak-daemon instance's own startup
    // singleton check (see tryConnectExisting), not a real client request --
    // skip it entirely so the trace log only records actual commands.
    if message.isEmpty { return }
    var lines = message.components(separatedBy: "\n")
    guard !lines.isEmpty else { return }
    let mode = lines.removeFirst().trimmingCharacters(in: .whitespaces)
    let rateStr = lines.isEmpty ? "" : lines.removeFirst().trimmingCharacters(in: .whitespaces)
    let voiceStr = lines.isEmpty ? "" : lines.removeFirst().trimmingCharacters(in: .whitespaces)
    let text = lines.joined(separator: "\n")
    let rate = Float(rateStr)

    DispatchQueue.main.async {
        trace("mode=\(mode) textLen=\(text.count)")
        switch mode {
        case "STOP":
            handler.stop()
        case "TOGGLE":
            if handler.isSpeaking {
                handler.stop()
            } else if !text.isEmpty {
                handler.speak(text, rate: rate, voice: voiceStr)
            }
        case "SPEAK":
            if !text.isEmpty {
                handler.speak(text, rate: rate, voice: voiceStr)
            }
        default:
            break
        }
    }
}

DispatchQueue.global(qos: .userInitiated).async {
    while true {
        var clientAddr = sockaddr_un()
        var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(listenFd, $0, &clientLen)
            }
        }
        guard clientFd >= 0 else { continue }
        handleConnection(clientFd)
    }
}

RunLoop.main.run()
