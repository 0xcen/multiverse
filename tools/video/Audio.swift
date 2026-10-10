import Foundation

// Sound design for the launch film, synthesised in code from the same timeline as the picture
// (Film.swift, `T`). Deterministic: noise comes from a fixed-seed generator. Restrained on purpose:
// a quiet pad, dry clicks and pops, a rising tone while a link travels, a chime when it lands.

let sampleRate = 48_000.0

struct Mixer {
    var left: [Float], right: [Float]
    init(seconds: Double) {
        let n = Int(seconds * sampleRate)
        left = Array(repeating: 0, count: n); right = Array(repeating: 0, count: n)
    }

    /// Adds `f(time since start)` from `start` for `length` seconds, panned -1 (left) … 1 (right).
    mutating func add(at start: Double, length: Double, pan: Double = 0, gain: Double = 1, _ f: (Double) -> Double) {
        let a = Float(cos((pan + 1) * .pi / 4) * gain), b = Float(sin((pan + 1) * .pi / 4) * gain)
        let s0 = max(0, Int(start * sampleRate)), s1 = min(left.count, Int((start + length) * sampleRate))
        guard s1 > s0 else { return }
        for i in s0..<s1 {
            let v = Float(f(Double(i) / sampleRate - start))
            left[i] += v * a; right[i] += v * b
        }
    }
}

/// Fixed-seed noise so every render sounds the same.
struct Noise {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(Int64(bitPattern: state >> 1) % 2_000_000) / 1_000_000 - 1
    }
}

private func sine(_ f: Double, _ t: Double) -> Double { sin(2 * .pi * f * t) }

extension Mixer {
    /// Dry click: a few milliseconds of bright noise plus a tick.
    mutating func click(_ at: Double, pan: Double = 0, gain: Double = 0.35, seed: UInt64 = 1, tone: Double = 2400) {
        var noise = Noise(state: seed &* 7919 &+ UInt64(at * 1000))
        var last = 0.0
        add(at: at, length: 0.03, pan: pan, gain: gain) { t in
            let n = noise.next(), hp = n - last; last = n
            return (hp * 0.6 + sine(tone, t) * 0.5) * exp(-t / 0.0025)
        }
    }

    /// Soft pop: a short sine that drops in pitch.
    mutating func pop(_ at: Double, _ f: Double, pan: Double = 0, gain: Double = 0.22) {
        var phase = 0.0
        add(at: at, length: 0.25, pan: pan, gain: gain) { t in
            let freq = f * (1 + 0.8 * exp(-t / 0.018))
            phase += 2 * .pi * freq / sampleRate
            return sin(phase) * (1 - exp(-t / 0.002)) * exp(-t / 0.07)
        }
    }

    /// Mouse button: down and up.
    mutating func mouse(_ at: Double, pan: Double = 0) {
        click(at, pan: pan, gain: 0.45, seed: 3, tone: 1800)
        click(at + 0.055, pan: pan, gain: 0.25, seed: 4, tone: 2600)
    }

    /// A tone gliding from f0 to f1 while something travels.
    mutating func glide(from t0: Double, to t1: Double, _ f0: Double, _ f1: Double, pan0: Double, pan1: Double, gain: Double = 0.07) {
        var phase = 0.0
        let length = t1 - t0
        // Pan is applied per sample by splitting into short slices.
        let slices = 24
        for s in 0..<slices {
            let a = Double(s) / Double(slices), b = Double(s + 1) / Double(slices)
            let pan = pan0 + (pan1 - pan0) * (a + b) / 2
            add(at: t0 + a * length, length: (b - a) * length, pan: pan, gain: gain) { t in
                let x = a + t / length
                let freq = f0 * pow(f1 / f0, x)
                phase += 2 * .pi * freq / sampleRate
                let env = sin(.pi * min(1, x)) * 0.8 + 0.2 * (1 - x)
                return (sin(phase) + 0.25 * sin(2 * phase)) * env
            }
        }
    }

    /// Bell-like chime.
    mutating func chime(_ at: Double, _ f: Double, pan: Double = 0, gain: Double = 0.16, decay: Double = 0.9) {
        add(at: at, length: decay * 4, pan: pan, gain: gain) { t in
            let attack = 1 - exp(-t / 0.003)
            return attack * (sine(f, t) * exp(-t / decay) + 0.45 * sine(f * 2.005, t) * exp(-t / (decay * 0.5))
                             + 0.2 * sine(f * 3.01, t) * exp(-t / (decay * 0.3)))
        }
    }

    /// Air rushing in: noise through a low-pass that opens up, then stops.
    mutating func whoosh(from t0: Double, to t1: Double, gain: Double = 0.22, seed: UInt64 = 9) {
        var noise = Noise(state: seed)
        var lp = 0.0
        let length = t1 - t0
        add(at: t0, length: length + 0.05, gain: gain) { t in
            let x = min(1, t / length)
            let cutoff = 250 * pow(24, x)
            let k = 1 - exp(-2 * .pi * cutoff / sampleRate)
            lp += k * (noise.next() - lp)
            let env = pow(x, 1.6) * (t > length ? exp(-(t - length) / 0.01) : 1)
            return lp * env * 1.6
        }
    }

    /// Low hit for the icon landing.
    mutating func thump(_ at: Double, gain: Double = 0.55) {
        var phase = 0.0
        add(at: at, length: 0.6, gain: gain) { t in
            let freq = 52 * (1 + 1.2 * exp(-t / 0.03))
            phase += 2 * .pi * freq / sampleRate
            return sin(phase) * exp(-t / 0.22)
        }
        click(at, gain: 0.2, seed: 11, tone: 900)
    }

    /// Quiet sustained chord with slow movement; fades in and out.
    mutating func pad(from t0: Double, to t1: Double, _ freqs: [Double], gain: Double = 0.016) {
        let length = t1 - t0
        for (i, f) in freqs.enumerated() {
            let detune = 1 + 0.0015 * Double(i % 2 == 0 ? 1 : -1)
            add(at: t0, length: length, pan: i % 2 == 0 ? -0.35 : 0.35, gain: gain) { t in
                let fade = min(1, t / 0.35) * min(1, (length - t) / 0.35)
                let wobble = 1 + 0.15 * sin(2 * .pi * (0.25 + 0.07 * Double(i)) * t)
                return (sine(f, t) + 0.3 * sine(f * detune * 2, t)) * fade * wobble
            }
        }
    }
}

func filmSoundtrack() -> Mixer {
    var m = Mixer(seconds: T.duration)
    // Cold open: a busy scatter of ticks over rising air, then everything snaps into place.
    var n = Noise(state: 2024)
    for i in 0..<70 {
        let at = pow(Double(i) / 70, 0.8) * (T.untangle - 0.05)
        let f = 300 + (n.next() + 1) * 900
        if i % 3 == 0 { m.pop(at, f, pan: n.next(), gain: 0.07) } else { m.click(at, pan: n.next(), gain: 0.12, seed: UInt64(i), tone: f * 2) }
    }
    m.whoosh(from: 0, to: T.untangle, gain: 0.16, seed: 77)
    m.thump(T.untangle, gain: 0.5)
    for i in 0..<Frame.openApps.count {   // tiles landing in order: a quick rising run
        let notes = [261.63, 293.66, 329.63, 392, 440, 523.25, 587.33, 659.25, 783.99, 880, 1046.5, 1174.66]
        m.pop(T.untangle + 0.08 + Double(i) * 0.025, notes[i], pan: -0.8 + Double(i) * 0.14, gain: 0.1)
    }
    m.chime(T.untangle + 0.4, 659.25, pan: 0.5, gain: 0.08, decay: 0.8)
    m.chime(T.untangle + 0.46, 880, pan: 0.5, gain: 0.08, decay: 0.8)
    m.whoosh(from: T.intro - 0.3, to: T.intro, gain: 0.1, seed: 78)
    // Bed: a chord per act; brighter at the end.
    m.pad(from: T.untangle, to: T.workRoute + 0.2, [110, 164.81, 246.94, 261.63])  // A2 E3 B3 C4
    m.pad(from: T.workRoute - 0.2, to: T.gather + 0.2, [87.31, 130.81, 220, 329.63]) // F2 C3 A3 E4
    m.pad(from: T.plateLand - 0.1, to: T.duration, [130.81, 196, 329.63, 493.88], gain: 0.02) // Cmaj7

    // 1. One becomes two
    m.pop(T.intro + 0.03, 330)
    m.click(T.split, pan: 0, gain: 0.3)
    m.pop(T.split + 0.02, 440, pan: 0.4)
    m.chime(T.invert, 1318.5, pan: 0.45, gain: 0.07, decay: 0.5)
    // 2. Different lives
    m.whoosh(from: T.lives - 0.25, to: T.lives + 0.02, gain: 0.12)
    m.pop(T.lives + 0.02, 262, pan: -0.5)
    m.pop(T.lives + 0.09, 330, pan: 0.5)
    // 3. Menu
    m.whoosh(from: T.menu - 0.2, to: T.menu + 0.05, gain: 0.08, seed: 21)
    m.mouse(T.menuOpen - 0.06, pan: 0.6)
    m.click(T.hoverSlack, pan: 0.6, gain: 0.12, seed: 5, tone: 3200)
    m.click(T.hoverPersonal, pan: 0.6, gain: 0.12, seed: 6, tone: 3200)
    // 4. Copies
    m.pop(T.cuts, 392, gain: 0.26)
    m.pop(T.card2, 440, gain: 0.26)
    let scale = [523.25, 587.33, 659.25, 783.99, 880, 1046.5]  // pentatonic up
    for i in 0..<Frame.dockItems.count {
        m.pop(T.dock + Double(i) * 0.06, scale[i], pan: -0.6 + Double(i) * 0.24, gain: 0.14)
    }
    // 5–6. Routes: click, the link travels (rising), node, it lands (chime).
    for (rt, land) in [(workTimes, 659.25), (personalTimes, 880.0)] {
        m.mouse(rt.click - 0.03, pan: -0.55)
        m.glide(from: rt.leg1.0, to: rt.leg1.1, 330, 520, pan0: -0.5, pan1: 0)
        m.click(rt.leg1.1, gain: 0.18, seed: 7, tone: 1600)
        m.glide(from: rt.leg2.0, to: rt.leg2.1, 520, 780, pan0: 0, pan1: 0.55)
        m.chime(rt.open, land, pan: 0.55, gain: 0.17)
    }
    // 7. Both routes
    m.chime(T.both + 0.05, 659.25, pan: -0.2, gain: 0.1, decay: 0.7)
    m.chime(T.both + 0.17, 880, pan: 0.2, gain: 0.1, decay: 0.7)
    // 8. Into the icon, and the title.
    m.whoosh(from: T.gather, to: T.plateLand - 0.02, gain: 0.26, seed: 31)
    m.thump(T.plateLand)
    for (i, f) in [523.25, 659.25, 783.99, 987.77].enumerated() {
        m.chime(T.plateLand + Double(i) * 0.015, f, gain: 0.07, decay: 1.6)
    }
    m.click(T.end + 0.12, gain: 0.12, seed: 13, tone: 2000)
    m.click(T.end + 0.3, gain: 0.09, seed: 14, tone: 2200)
    return m
}

/// 16-bit stereo WAV, with a soft limiter so nothing clips.
func writeWAV(_ m: Mixer, to path: String) {
    var data = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
    let n = m.left.count
    data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 4)); data.append(contentsOf: Array("WAVE".utf8))
    data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2); u32(UInt32(sampleRate)); u32(UInt32(sampleRate) * 4); u16(4); u16(16)
    data.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 4))
    for i in 0..<n {
        for v in [m.left[i], m.right[i]] {
            let limited = tanh(Double(v) * 1.1) * 0.89
            u16(UInt16(bitPattern: Int16(max(-32767, min(32767, limited * 32767)))))
        }
    }
    try! data.write(to: URL(fileURLWithPath: path))
}
