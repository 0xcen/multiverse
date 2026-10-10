import Foundation

// The score: a fresh piece, not a loop. 96 BPM, D minor (i–VI–III–VII: Dm, B♭, F, C).
// A warm analogue bass ostinato drives it, wide detuned pads carry the chords, drums stay sparse, and a
// short lead hook arrives with the link routes. Kandinsky's synaesthesia: shapes on screen sound as
// in-key bells (circles ring, landings chime) that echo through a ping-pong delay and a small room.
// The cold-open mess before the snap is left to the cue layer in Audio.swift.

private func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }

/// D minor chords for each bar: root (MIDI) and chord tones for pads and bells.
private let progression: [(root: Double, tones: [Double])] = [
    (50, [62, 65, 69, 74]),   // Dm:  D4 F4 A4 D5
    (46, [58, 62, 65, 70]),   // B♭:  B♭3 D4 F4 B♭4
    (53, [60, 65, 69, 72]),   // F:   C4 F4 A4 C5
    (48, [60, 64, 67, 72]),   // C:   C4 E4 G4 C5
]

extension Mixer {
    /// Band-limited saw through a two-pole low-pass whose cutoff moves from c0 to c1 over the note.
    mutating func saw(_ at: Double, _ f: Double, length: Double, pan: Double = 0, gain: Double,
                      cutoff c0: Double, to c1: Double, attack: Double = 0.005, release: Double = 0.08,
                      detune: Double = 0, vibrato: Double = 0) {
        var phase = 0.0, lp1 = 0.0, lp2 = 0.0
        let harmonics = max(1, min(28, Int(9000 / f)))
        add(at: at, length: length + release * 4, pan: pan, gain: gain) { t in
            let vib = 1 + vibrato * sin(2 * .pi * 5.2 * t) * min(1, t / 0.3)
            phase += 2 * .pi * f * (1 + detune) * vib / sampleRate
            var v = 0.0
            for h in 1...harmonics { v += sin(Double(h) * phase) / Double(h) }
            let x = min(1, t / max(length, 0.001))
            let cutoff = c0 + (c1 - c0) * x
            let k = 1 - exp(-2 * .pi * cutoff / sampleRate)
            lp1 += k * (v - lp1); lp2 += k * (lp1 - lp2)
            let env = min(1, t / attack) * (t < length ? 1 : exp(-(t - length) / release))
            return lp2 * env * 0.6
        }
    }

    /// Glassy bell: inharmonic partials, used for shapes appearing on screen.
    mutating func bell(_ at: Double, _ f: Double, pan: Double = 0, gain: Double = 0.06, decay: Double = 1.2) {
        add(at: at, length: decay * 4, pan: pan, gain: gain) { t in
            let a = 1 - exp(-t / 0.002)
            return a * (sin(2 * .pi * f * t) * exp(-t / decay)
                        + 0.5 * sin(2 * .pi * f * 2.76 * t) * exp(-t / (decay * 0.35))
                        + 0.25 * sin(2 * .pi * f * 5.4 * t) * exp(-t / (decay * 0.15)))
        }
    }

    mutating func deepKick(_ at: Double, gain: Double = 0.42) {
        var phase = 0.0
        add(at: at, length: 0.5, gain: gain) { t in
            phase += 2 * .pi * (44 + 90 * exp(-t / 0.035)) / sampleRate
            return sin(phase) * exp(-t / 0.2) * (1 - exp(-t / 0.001))
        }
    }

    /// Clap: three quick noise bursts through a band-pass.
    mutating func clap(_ at: Double, gain: Double = 0.16, seed: UInt64) {
        var noise = Noise(state: seed)
        var lp = 0.0, lp2 = 0.0
        add(at: at, length: 0.35, pan: 0.1, gain: gain) { t in
            let n = noise.next()
            lp += 0.45 * (n - lp); lp2 += 0.08 * (lp - lp2)
            let hp = lp - lp2  // band around 1–3 kHz
            let bursts = [0.0, 0.011, 0.023].reduce(0.0) { acc, o in acc + (t >= o ? exp(-(t - o) / 0.006) : 0) }
            return hp * (bursts * 0.6 + exp(-t / 0.09))
        }
    }

    mutating func tick(_ at: Double, gain: Double, seed: UInt64) {
        var noise = Noise(state: seed)
        var last = 0.0
        add(at: at, length: 0.04, pan: -0.25, gain: gain) { t in
            let n = noise.next(), d = n - last; last = n
            return d * exp(-t / 0.008)
        }
    }

    /// Adds another bus into this one.
    mutating func mix(_ other: Mixer, gain: Float = 1) {
        for i in 0..<min(left.count, other.left.count) { left[i] += other.left[i] * gain; right[i] += other.right[i] * gain }
    }

    /// Ping-pong delay (dotted eighth), returned as a new bus.
    func pingPong(time: Double, feedback: Float = 0.42) -> Mixer {
        var out = self
        let d = Int(time * sampleRate)
        for i in d..<left.count {
            out.left[i] += out.right[i - d] * feedback
            out.right[i] += out.left[i - d] * feedback
        }
        return out
    }

    /// A small Schroeder room (4 combs + 2 all-passes per side).
    func room(wet: Float = 0.3) -> Mixer {
        var out = Mixer(seconds: Double(left.count) / sampleRate)
        func process(_ x: [Float], spread: Int) -> [Float] {
            let combs = [1557, 1617, 1491, 1422].map { $0 + spread }, fb: Float = 0.8
            var y = [Float](repeating: 0, count: x.count)
            for c in combs {
                var buf = [Float](repeating: 0, count: c), idx = 0, lp: Float = 0
                for i in 0..<x.count {
                    let o = buf[idx]; lp = o * 0.7 + lp * 0.3
                    buf[idx] = x[i] + lp * fb; idx = (idx + 1) % c
                    y[i] += o * 0.25
                }
            }
            for a in [225, 556] {
                var buf = [Float](repeating: 0, count: a), idx = 0
                for i in 0..<y.count {
                    let b = buf[idx], v = y[i]
                    buf[idx] = v + b * 0.5; y[i] = b - v * 0.5; idx = (idx + 1) % a
                }
            }
            return y
        }
        out.left = process(left, spread: 0).map { $0 * wet }
        out.right = process(right, spread: 23).map { $0 * wet }
        return out
    }
}

func addScore(_ m: inout Mixer) {
    let q = T.quarter, e = q / 2, bar = q * 4
    func chord(at t: Double) -> (root: Double, tones: [Double]) {
        progression[max(0, Int((t - T.untangle) / (bar * 2))) % progression.count]  // two bars per chord
    }
    var bells = Mixer(seconds: T.duration)
    var verb = Mixer(seconds: T.duration)

    // The snap: a deep D, a wide Dm chord, and the pulse starts.
    m.deepKick(T.untangle, gain: 0.5)
    m.saw(T.untangle, hz(26), length: 1.6, gain: 0.12, cutoff: 180, to: 90, release: 0.6)  // D1 boom
    for (i, n) in progression[0].tones.enumerated() {
        m.saw(T.untangle, hz(n), length: 1.2, pan: [-0.6, -0.2, 0.2, 0.6][i], gain: 0.025, cutoff: 3000, to: 900, release: 0.8)
    }

    // Bass ostinato in eighths: root, root, octave, root, fifth, root, octave, fifth. The filter opens
    // from the snap to the end of the cold open, then breathes with each bar.
    let pattern: [Double] = [0, 0, 12, 0, 7, 0, 12, 7]
    var step = 0
    var t = T.untangle + q
    while t < T.gather - 0.05 {
        let c = chord(at: t), n = c.root - 12 + pattern[step % pattern.count]
        let opening = min(1, (t - T.untangle) / (T.intro - T.untangle))
        let inBar = (t - T.untangle).truncatingRemainder(dividingBy: bar) / bar
        let cutoff = 260 + 900 * opening + 500 * sin(.pi * inBar)
        m.saw(t, hz(n), length: e * 0.8, pan: 0, gain: 0.1, cutoff: cutoff * 1.6, to: cutoff, release: 0.05)
        step += 1; t += e
    }

    // Pads: three detuned saws per chord tone, two bars each, from the end of the cold open.
    t = T.untangle + bar * 2
    while t < T.gather - 0.1 {
        let c = chord(at: t), length = min(bar * 2, T.gather - t) - 0.05
        for (i, n) in c.tones.enumerated() {
            for d in [-0.004, 0.0, 0.004] {
                m.saw(t, hz(n), length: length, pan: [-0.7, -0.25, 0.25, 0.7][i] + d * 40, gain: 0.0075,
                      cutoff: 700, to: 1400, attack: 0.5, release: 0.6, detune: d)
            }
        }
        t += bar * 2
    }

    // Drums with the explainer: deep kick on 1 and the "and" of 3, clap on 3 (into the room), soft hats.
    t = T.intro
    var b = 0
    while t < T.gather - 0.05 {
        let beat = b % 8  // eighths in a bar
        if beat == 0 || beat == 5 { m.deepKick(t, gain: 0.32) }
        if beat == 4 { verb.clap(t, gain: 0.12, seed: UInt64(b)); m.clap(t, gain: 0.08, seed: UInt64(b)) }
        m.tick(t + e / 2, gain: beat % 2 == 0 ? 0.035 : 0.022, seed: UInt64(1000 + b))
        b += 1; t += e
    }

    // The hook, with the routes: a lead line that answers each chord.
    let hook: [(beat: Double, note: Double, len: Double)] = [
        (0, 74, 1.5), (1.5, 72, 0.5), (2, 69, 1), (3, 70, 1), (4, 69, 2), (6, 65, 1), (7, 67, 1),
        (8, 69, 1.5), (9.5, 70, 0.5), (10, 72, 1), (11, 74, 1), (12, 76, 2), (14, 74, 2),
    ]
    var phraseStart = T.workRoute
    while phraseStart + bar * 4 <= T.gather + 0.01 {
        for h in hook {
            let at = phraseStart + h.beat * q
            m.saw(at, hz(h.note), length: h.len * q * 0.95, pan: 0.15, gain: 0.05, cutoff: 2600, to: 1600,
                  attack: 0.02, release: 0.25, vibrato: 0.004)
            bells.saw(at, hz(h.note), length: h.len * q * 0.6, pan: -0.3, gain: 0.015, cutoff: 2000, to: 1200, release: 0.2)
        }
        phraseStart += bar * 4
    }

    // Kandinsky: shapes sound as bells, in key.
    let events: [(Double, Double)] = [
        (T.split + 0.3, 74), (T.invert + 0.12, 77), (T.lives + 0.45, 69), (T.lives + 0.55, 72),
        (T.menuOpen + 0.05, 74), (T.cuts + 0.22, 77), (T.card2 + 0.22, 81),
        (workTimes.leg1.1, 81), (workTimes.open, 86), (personalTimes.leg1.1, 77), (personalTimes.open, 81),
        (sideTimes.leg1.1, 79), (sideTimes.open, 84), (T.both + 0.05, 74), (T.both + 0.15, 77), (T.both + 0.25, 81),
    ]
    for (i, ev) in events.enumerated() { bells.bell(ev.0, hz(ev.1), pan: i % 2 == 0 ? -0.4 : 0.4, gain: 0.05) }
    for i in 0..<Frame.dockItems.count {
        bells.bell(T.dock + 0.22 + Double(i) * 0.06, hz([74, 77, 79, 81, 84, 86, 89][i]), pan: -0.6 + Double(i) * 0.2, gain: 0.04)
    }

    // The fold: everything drops, a riser, then the icon lands on a big chord that rings out.
    var riserPhase = 0.0
    m.add(at: T.gather, length: T.plateLand - T.gather, gain: 0.05) { t in
        let x = t / (T.plateLand - T.gather)
        riserPhase += 2 * .pi * hz(50 + 24 * x) / sampleRate
        return (sin(riserPhase) + 0.5 * sin(2 * riserPhase)) * x * x
    }
    m.deepKick(T.plateLand, gain: 0.5)
    m.saw(T.plateLand, hz(38), length: 3.5, gain: 0.1, cutoff: 400, to: 120, release: 1.2)   // D2
    for (i, n) in [62.0, 65, 69, 72, 76].enumerated() {                                        // Dm9
        m.saw(T.plateLand, hz(n), length: 3.2, pan: [-0.7, -0.35, 0, 0.35, 0.7][i], gain: 0.016,
              cutoff: 2600, to: 700, attack: 0.01, release: 1.4)
        bells.bell(T.plateLand + Double(i) * 0.05, hz(n + 12), pan: [-0.7, -0.35, 0, 0.35, 0.7][i], gain: 0.04, decay: 1.8)
    }
    // End card: slow bells on the chord, fading.
    var k = 0
    t = T.end + q
    while t < T.duration - 0.8 {
        let fade = 1 - (t - T.end) / (T.duration - T.end)
        bells.bell(t, hz([74, 77, 81, 84][k % 4]), pan: k % 2 == 0 ? -0.5 : 0.5, gain: 0.035 * fade, decay: 1.5)
        k += 1; t += q
    }

    // Space: bells through the ping-pong delay, bells and claps into the room.
    let echoed = bells.pingPong(time: q * 0.75)
    m.mix(echoed, gain: 1)
    verb.mix(bells, gain: 0.6)
    m.mix(verb.room(wet: 0.35))
}
