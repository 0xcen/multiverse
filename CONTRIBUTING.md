# Contributing

Thanks for helping. Multiverse is small on purpose; please keep changes focused.

## Build

```bash
./build.sh            # build into ./build
./build.sh install    # install to /Applications and launch
```

Needs macOS 14+ and Xcode's command line tools. There are no dependencies.

## Before you open a pull request

- `swiftc -parse-as-library -typecheck Sources/*.swift` passes (CI runs `./build.sh`).
- You tried the change in the running app, including setup ("Setup & permissions…").
- Anything that writes to `/Applications` only ever touches bundles carrying Multiverse's owner marker
  (`MultiverseCopyOf`). Never delete or overwrite an app Multiverse didn't make, and never touch app
  data in `~/Library`.
- UI follows the Carbon identity in `Sources/Brand.swift` (graphite, ivory, olive; medium-weight
  headings, plain language).

## Launch film and images

`tools/` renders the launch images and film from code. See `tools/video/RULES.md` before editing the
film; `tools/video/render.sh` renders and checks it.

## Reporting a security problem

Please don't open a public issue for anything that could harm users (for example a way to make
Multiverse replace or delete an app it didn't make). Open a private security advisory on GitHub instead.
