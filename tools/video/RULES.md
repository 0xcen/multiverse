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

## Spec

1920×1080, 30 fps, 22 s (660 frames), H.264, yuv420p, SAR 1:1, AAC stereo 48 kHz.

Pace: entrances under 0.35 s (`snap`), pops land with a small overshoot (`pop`), hard cuts between
beats. Sound is restrained: a quiet pad, dry clicks/pops, a rising tone while a link travels, a chime
where it lands, one low hit when the icon lands. Picture and sound read the same `T` timings.

## Screenplay: "One Mac. Different universes."

| Time | Beat |
| --- | --- |
| 0–2 s | One app icon separates into two copies. The second inverts to ivory. "Same app." |
| 2–4 s | Both open into the same app with different accounts, side by side. "Different lives." |
| 4–6.6 s | Pull back to the Multiverse menu showing Work and Personal. "Meet Multiverse." |
| 6.6–9 s | Quick cuts: each copy's name and icon, then both in the Dock. |
| 9–12 s | Click a link in the Work app; a pulse follows app → Work → work browser, which opens it. |
| 12–14.4 s | The same for Personal. |
| 14.4–16.2 s | Both routes side by side. "Personal stays personal." |
| 16.2–17.7 s | The routes fold into two diagonal panes; the icon lands. |
| 17.7–22 s | "Multiverse. One Mac. Different universes." |
