// speak-render -- speak text through the Aaron voice, one process per press.
//
// WHY THIS SHAPE (2026-09-03)
// ---------------------------
// The premium neural voice "Aaron" is reachable only through NSSpeechSynthesizer,
// and that engine costs ~0.8 s before its first word in a fresh process. A
// background daemon was built to hide that cost. It saved ~0.5 s per press and
// brought a socket, a singleton race, a process that never exited, a lock that
// kept the Mac from sleeping, and a toggle that silently cancelled long text
// (see docs/HERDR.md). This program replaces it: it lives for exactly one
// utterance and then exits. Nothing runs between presses.
//
// The silence problem is solved by CHUNKING, not by a warm engine. The text is
// split at sentence ends. Chunk 1 is rendered to a temp AIFF (~0.7 s for one
// sentence) and starts playing at once; chunk 2 renders while chunk 1 plays,
// and so on. Rendering runs ~8x faster than speech, so playback never runs dry.
// Measured on 3215 chars of prose: first audio at 0.9 s, 13 chunks, and the
// chunked audio total was within 2% of a single whole-text render -- the joins
// add no silence.
//
// Render-to-file + AVAudioPlayer (not live NSSpeechSynthesizer output) is kept
// from the daemon era: live output sounded muffled, file playback did not. One
// AVAudioPlayer per chunk, chained from audioPlayerDidFinishPlaying, survives
// output-device changes (Bluetooth profile flips); AVAudioEngine does not.
//
// STOP = KILL THIS PROCESS. The caller (speak-clipboard) keeps the pid. On
// SIGTERM/SIGINT the player stops, temp files are deleted, exit 0. The voice
// extension's render dies with its host process (observed), so there is no
// engine tail to manage. If the engine refuses or interrupts a render, what is
// already rendered plays out and the process exits with that code afterwards,
// so a sentence is never cut mid-word by the program's own error handling.
//
// Temp files live in the per-user temp directory (0700, purged by the OS). File
// names carry this process's pid, so two instances overlapping during a
// "replace" never touch each other's files. Files older than ten minutes with
// this program's prefix are swept at start, in case an earlier instance was
// SIGKILLed before it could clean up.
//
// USAGE
//   speak-render [flags] < text
//     --rate N         words per minute (default 420)
//     --voice ID       NSSpeechSynthesizer voice identifier (default Aaron)
//     --first-chunk N  the first chunk is one sentence, merged up to N chars (60)
//     --min-chunk N    later chunks merge sentences up to at least N chars (200)
//     --max-chunk N    hard split above N chars at the last space (600)
//     --out DIR        directory for temp AIFF files (default: per-user temp dir)
//     --no-play        render every chunk and print timings; play nothing (tests)
//     --keep           keep the rendered files (with --no-play, for inspection)
//
// Timing lines go to stderr, one per event, never the text itself.
//
// EXIT CODES
//   0 spoke everything, or was told to stop
//   1 nothing to speak
//   2 bad flag
//   3 voice not found
//   4 the engine refused to start a render
//   5 a render was interrupted
//   6 a rendered file could not be opened or played
import Foundation
import AppKit
import AVFoundation

let defaultVoiceId = "com.apple.ttsbundle.gryphon-neuralAX_Aaron_en-US_premium"
var rate: Float = 420
var voiceId = defaultVoiceId
var firstChunk = 60
var minChunk = 200
var maxChunk = 600
var noPlay = false
var keepFiles = false
var outDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

var args = Array(CommandLine.arguments.dropFirst())
func nextArg(_ flag: String) -> String {
    if args.isEmpty {
        FileHandle.standardError.write("speak-render: \(flag) needs a value\n".data(using: .utf8)!)
        exit(2)
    }
    return args.removeFirst()
}
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--rate": rate = Float(nextArg(a)) ?? rate
    case "--voice": voiceId = nextArg(a)
    case "--first-chunk": firstChunk = Int(nextArg(a)) ?? firstChunk
    case "--min-chunk": minChunk = Int(nextArg(a)) ?? minChunk
    case "--max-chunk": maxChunk = Int(nextArg(a)) ?? maxChunk
    case "--out": outDir = URL(fileURLWithPath: nextArg(a), isDirectory: true)
    case "--no-play": noPlay = true
    case "--keep": keepFiles = true
    default:
        FileHandle.standardError.write("speak-render: unknown flag \(a)\n".data(using: .utf8)!)
        exit(2)
    }
}

let t0 = Date()
let pid = ProcessInfo.processInfo.processIdentifier
func log(_ s: String) {
    let line = String(format: "[%6.2fs] %@\n", Date().timeIntervalSince(t0), s)
    FileHandle.standardError.write(line.data(using: .utf8)!)
}

// ---- stale files from a SIGKILLed earlier instance ----
do {
    let fm = FileManager.default
    let cutoff = Date(timeIntervalSinceNow: -600)
    for name in (try? fm.contentsOfDirectory(atPath: outDir.path)) ?? []
    where name.hasPrefix("speak-render-") && name.hasSuffix(".aiff") {
        let p = outDir.appendingPathComponent(name).path
        if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, m < cutoff {
            try? fm.removeItem(atPath: p)
        }
    }
}

// ---- input ----
let input = String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
if text.isEmpty { log("nothing to speak"); exit(1) }

// ---- chunking ----
// 1. Split after . ! ? when followed by whitespace or end of text.
// 2. Any piece longer than maxChunk (terminal text often has no sentence
//    punctuation) is hard-split at the last space inside the window.
// 3. Merge pieces until a chunk reaches its target, never past maxChunk. The
//    first chunk's target is firstChunk (one sentence, so audio starts fast);
//    every later chunk's target is minChunk.
func splitSentences(_ s: String) -> [String] {
    var out: [String] = []
    var current = ""
    let chars = Array(s)
    for (i, c) in chars.enumerated() {
        current.append(c)
        if c == "." || c == "!" || c == "?" {
            if i + 1 >= chars.count || chars[i + 1].isWhitespace {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
    }
    out.append(current.trimmingCharacters(in: .whitespaces))
    return out.filter { !$0.isEmpty }
}
func hardSplit(_ s: String, max: Int) -> [String] {
    var out: [String] = []
    var rest = Substring(s)
    while rest.count > max {
        let window = rest.prefix(max)
        if let cut = window.lastIndex(of: " ") {
            out.append(String(rest[rest.startIndex..<cut]))
            rest = rest[rest.index(after: cut)...]
        } else {
            out.append(String(window))
            rest = rest.dropFirst(max)
        }
    }
    if !rest.isEmpty { out.append(String(rest)) }
    return out
}
var chunks: [String] = []
do {
    var acc = ""
    for s in splitSentences(text).flatMap({ hardSplit($0, max: maxChunk) }) {
        if !acc.isEmpty && acc.count + 1 + s.count > maxChunk {
            chunks.append(acc); acc = ""
        }
        acc = acc.isEmpty ? s : acc + " " + s
        if acc.count >= (chunks.isEmpty ? firstChunk : minChunk) {
            chunks.append(acc); acc = ""
        }
    }
    if !acc.isEmpty { chunks.append(acc) }
}
log("chars=\(text.count) chunks=\(chunks.count) sizes=\(chunks.map { $0.count })")

// ---- pipeline: render ahead, play behind ----
// Everything runs on the main thread: NSSpeechSynthesizer and AVAudioPlayer
// deliver their delegate calls on the main run loop, and the signal sources are
// bound to the main queue. Renders are strictly sequential on one synthesizer,
// so a render-finished callback always belongs to chunk renderIdx.
final class Pipeline: NSObject, NSSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    let synth: NSSpeechSynthesizer
    var renderIdx = 0                        // next chunk index to render
    var playIdx = 0                          // next chunk index to play
    var players: [Int: AVAudioPlayer] = [:]  // rendered and prepared, not yet played
    var player: AVAudioPlayer?               // playing now
    var renderStart = Date()
    var files: [String] = []
    var renderMs: [Int] = []
    var audioSec: [Double] = []
    var failCode: Int32 = 0                  // rendering stopped early; drain, then exit with it

    init(voice: String) {
        guard let s = NSSpeechSynthesizer(voice: NSSpeechSynthesizer.VoiceName(rawValue: voice)) else {
            log("voice not found: \(voice)"); exit(3)
        }
        synth = s
        super.init()
        synth.delegate = self
        synth.rate = rate
    }

    func renderNext() {
        guard failCode == 0, renderIdx < chunks.count else { return }
        let i = renderIdx
        let path = outDir.appendingPathComponent("speak-render-\(pid)-\(i).aiff").path
        files.append(path)
        renderStart = Date()
        if !synth.startSpeaking(chunks[i], to: URL(fileURLWithPath: path)) {
            log("startSpeaking refused for chunk \(i)")
            fail(4)
        }
    }

    // Fires when a chunk's RENDER finishes (a file render, not playback).
    func speechSynthesizer(_ sender: NSSpeechSynthesizer, didFinishSpeaking finished: Bool) {
        let i = renderIdx
        guard i < files.count, !sender.isSpeaking else { return }  // late or doubled callback
        renderMs.append(Int(Date().timeIntervalSince(renderStart) * 1000))
        guard finished else { log("render \(i) interrupted"); fail(5); return }
        renderIdx += 1
        renderNext()                                             // keep the engine busy first
        do {
            let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: files[i]))
            p.prepareToPlay()
            audioSec.append(p.duration)
            log(String(format: "render %d done chars=%d ms=%d audio=%.2fs", i, chunks[i].count, renderMs[i], p.duration))
            players[i] = p
        } catch {
            log("open \(i) failed: \(error)"); fail(6); return
        }
        playIfPossible()
    }

    func playIfPossible() {
        guard player == nil, let p = players.removeValue(forKey: playIdx) else { return }
        if noPlay {
            log(playIdx == 0 ? "first audio would start now" : "play \(playIdx) skipped")
            advance()
            return
        }
        p.delegate = self
        player = p
        guard p.play() else { log("play \(playIdx) failed to start"); fail(6); return }
        log(playIdx == 0 ? "first audio started" : "play \(playIdx) start")
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        guard p === player else { return }
        player = nil
        if !keepFiles { try? FileManager.default.removeItem(atPath: files[playIdx]) }
        log("play \(playIdx) done")
        advance()
    }

    // One rule for "next chunk or finish", shared by real and simulated playback.
    func advance() {
        playIdx += 1
        if playIdx >= chunks.count { finish(code: 0); return }
        if failCode != 0 && players[playIdx] == nil { finish(code: failCode); return }
        playIfPossible()
    }

    // Rendering stopped early. Let what is already rendered play out, then exit.
    func fail(_ code: Int32) {
        if failCode == 0 { failCode = code }
        if player == nil {
            if players[playIdx] != nil { playIfPossible() } else { finish(code: failCode) }
        }
    }

    func finish(code: Int32) {
        // Stop the engine BEFORE deleting: a render still in progress would
        // otherwise keep writing (or reopen) its file after the unlink.
        if synth.isSpeaking { synth.stopSpeaking() }
        player?.stop()
        if !keepFiles { for f in files { try? FileManager.default.removeItem(atPath: f) } }
        let total = Date().timeIntervalSince(t0)
        log(String(format: "done code=%d total=%.2fs renderMs=%@ audioSec=%@", code, total,
                   renderMs.description, audioSec.map { String(format: "%.1f", $0) }.description))
        exit(code)
    }
}

let pipe = Pipeline(voice: voiceId)

// Stop = signal. Stop playback, delete temp files, exit 0.
let signalSources: [DispatchSourceSignal] = [SIGTERM, SIGINT].map { sig in
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    src.setEventHandler { log("signal \(sig): stopping"); pipe.finish(code: 0) }
    src.resume()
    return src
}

pipe.renderNext()
RunLoop.main.run()
