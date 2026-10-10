# Launch film rules

Read before changing `LaunchVideo.swift`. Every rule came from a way films go wrong.

1. **A frame is a function of its number.** `frame(n)` only looks at `n`: no clocks, timers, animations
   or random numbers. Any frame can be re-rendered and checked on its own.
2. **Carbon only.** Graphite and ivory are the surface (`tools/Carbon.swift`). Olive is Personal and
   nothing else. No gradients, glass or glows.
3. **Real material only.** App symbols come from the real app icons on this Mac (`Carbon.glyph`). Menu
   items and labels use Multiverse's real wording ("Settings…", "Setup & permissions…", "Copy of Slack
   · own logins"). No invented features.
4. **Understandable on mute.** Every beat has to read without sound: one short caption at most per beat.
5. **Nothing ships unchecked.** `check.sh` must pass: frame count, duration, 30 fps, square pixels,
   identical re-render of sample frames. Then look at the stills in `checks/`.

## Spec

1920×1080, 30 fps, 32 s (960 frames), H.264, yuv420p, SAR 1:1.

## Screenplay: "One Mac. Different universes."

| Time | Beat |
| --- | --- |
| 0–3 s | One app icon separates into two copies. The second inverts to ivory. "Same app." |
| 3–6 s | Both open into the same app with different accounts, side by side. "Different lives." |
| 6–10 s | Pull back to the Multiverse menu showing Work and Personal. "Meet Multiverse." |
| 10–14 s | Quick cuts: each copy's name and icon, then both in the Dock. |
| 14–19 s | Click a link in the Work app; a pulse follows app → Work → work browser, which opens it. |
| 19–24 s | The same for Personal. Both routes side by side. "Personal stays personal." |
| 24–28 s | Pull out: each world gathers into a diagonal pane, then they become the Multiverse icon. |
| 28–32 s | "Multiverse. One Mac. Different universes." |
