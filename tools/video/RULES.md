# Launch film rules

Read before changing the film (`Film.swift` for picture, `Audio.swift` for sound, both timed by `T`). Every rule came from a way films go wrong.

1. **A frame is a function of its number.** `frame(n)` only looks at `n`: no clocks, timers, animations
   or random numbers. Any frame can be re-rendered and checked on its own.
2. **Carbon only.** Graphite and ivory are the surface (`tools/Carbon.swift`). Olive is Personal and
   nothing else. No gradients, glass or glows.
3. **Real material only.** App symbols come from the real app icons on this Mac (`Carbon.glyph`). Menu
   items and labels use Multiverse's real wording ("Settings…", "Setup & permissions…", "Copy of Slack
   · own logins"). No invented features.
4. **Understandable on mute.** Every beat has to read without sound: one short caption at most per beat.
5. **Nothing ships unchecked.** `render.sh` must pass: frame count, 30 fps, square pixels, audio
   present, same length as the picture and not clipping, identical re-render of sample frames.
   Then look at the stills in `checks/`.

## Principles of animation (Lasseter, 1987)

Helpers in `Pieces.swift`; use them rather than linear moves.

- **Anticipation** (`anticipate`, wind-ups): the icon squeezes before it splits; the tangle pulls in before
  it snaps; the rows spread before folding into the icon; the icon dips before it lifts.
- **Squash & stretch** (`squash`): tiles, Dock icons, the copy card and the icon plate flatten on landing
  and spring back; the travelling dot stretches along its path.
- **Arcs** (`arc`): the split, the tiles snapping into place and the cursor all travel on curves.
- **Follow-through & overlapping action**: window contents land after their frames; captions and the
  tagline arrive word by word; menu rows cascade.
- **Secondary action**: a ring leaves each node as a link reaches it; the browser page draws in line by line.
- **Staging**: one focal point at a time; the app window dims once its link is on its way.
- **Exaggeration**: bigger overshoot on the hero moments (the snap, the icon landing), gentler on long moves.
- **Slow in & out, timing**: `snap`, `ease`, `pop`; small things move fast, windows a little slower.

## Speed

`speed` in `Film.swift` (1.1) plays the whole film faster without touching the timeline: picture time is
`frame / fps × speed`, and the soundtrack is sped up to match with a pitch-keeping tempo change. Timings in
`T` and the screenplay below are at 1×.

## Spec

1920×1080, 30 fps, about 39 s (see `T.duration`), H.264, yuv420p, SAR 1:1, AAC stereo 48 kHz.

Reading time: every caption appears with room to be read (about 0.25 s a word plus a beat) and holds
fully visible for 1.3 s or more before the next cut. When a beat feels rushed, lengthen the beat, not the
animation.

Sound (`Audio.swift`): the first score, kept on purpose. A quiet chord pad per act (Am-ish, then F, then
Cmaj7 at the end) under dry cues: pops and ticks for things appearing, a mouse click, a tone that rises
while a link travels, a chime where it lands (different pitch per universe), a whoosh into the icon and
one low hit when it lands. The cold-open mess is deep space: a slowly beating sub rumble under an organ-like
low chord in open fifths that opens up and swells into the snap, where it cuts dead.

Pace: entrances under 0.35 s (`snap`), pops land with a small overshoot (`pop`), hard cuts between
beats. Sound is restrained: a quiet pad, dry clicks/pops, a rising tone while a link travels, a chime
where it lands, one low hit when the icon lands. Picture and sound read the same `T` timings.

## Screenplay: "One Mac. Different universes."

Times below are after the 4.6 s cold open (`T.intro`).

| Time | Beat |
| --- | --- |
| cold open, 0–4.6 s | Frame 0 is already busy: two dozen apps drifting, links tangled between them. At 1.3 s it all snaps into two grids whose lines fan cleanly into Work and Personal. "Run copies of any app. Organize your workflow." holds ~2.5 s while dots flow along the lines, ticking as they arrive. Sound: busy, clashing clatter until the snap, then an even tick. |
| 0–2 s | One app icon separates into two copies. The second inverts to ivory. "Same app." |
| 2–4 s | Both open into the same app with different accounts, side by side. "Different lives." |
| 4–6.6 s | Pull back to the Multiverse menu showing Work and Personal. "Meet Multiverse." |
| 6.6–9 s | Quick cuts: each copy's name and icon, then both in the Dock. |
| 9–12 s | Click a link in the Work app; a pulse follows app → Work → work browser, which opens it. |
| 12–14.4 s | The same for Personal: Personal ChatGPT → Dia. |
| 14.4–16.6 s | And a third: Side project Cursor → Side project Dia. |
| 16.6–18.4 s | All three routes. "Every link in its own universe." |
| 18.4–19.9 s | The routes fold into two diagonal panes; the icon lands. |
| 19.9–24.2 s | "Multiverse. One Mac. Different universes." |
