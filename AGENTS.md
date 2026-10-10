# Installing and configuring Multiverse (instructions for coding agents)

You are setting up Multiverse for the user on their Mac. Multiverse builds from source and signs
itself for this Mac only, so the user doesn't need an Apple developer account or any certificates.
Follow these steps in order and keep the user informed in plain language.

## 1. Check requirements

```bash
sw_vers -productVersion          # needs 14.0 or newer
xcode-select -p                  # needs a path; otherwise run: xcode-select --install (user clicks Install, then wait)
swiftc --version
```

## 2. Build and install

```bash
git clone https://github.com/0xcen/multiverse ~/multiverse   # skip if already cloned
cd ~/multiverse && ./build.sh install
```

This installs `/Applications/Multiverse.app` and starts it. It appears in the menu bar and needs no
Dock icon. Below, `MV` means `/Applications/Multiverse.app/Contents/MacOS/Multiverse`.

## 3. Ask the user how they want things split

Ask briefly, and suggest answers based on the apps they have (`ls /Applications`):

1. Which universes do they want? Usually 💼 Work and 🏠 Personal.
2. Which browser should each universe's links open in? Options:
   - Two different browsers, e.g. Chrome for work and Safari for personal.
   - A separate browser for one universe: a `clone` of a Chromium browser (Chrome, Brave, Edge, Arc,
     Dia…), e.g. "Work Chrome". It's its own app, with its own Dock icon, logins and history. Set
     that universe's `browser` to `{"appPath": "/Applications/Work Chrome.app"}`. This is what
     Settings does under "Make a separate browser".
   - An existing second profile folder (`--user-data-dir`), if they already run one.
   - Note: Chrome's built-in profile switcher (Profile 1, Profile 2…) is not supported. Use a
     separate browser instead.
3. Which apps belong to which universe? If they use an app in both, put the original in one universe
   and a copy in the other, e.g. Slack as is in Personal and a "Work Slack" copy in Work.
4. Which universe is the default for links from apps not in any universe? Usually Work.

## 4. Write the config

Path: `~/Library/Application Support/Multiverse/config.json` (or `MV config-path`). The running app
picks up changes within a second. Schema:

```json
{
  "defaultUniverseID": "<id of a universe>",
  "universes": [
    {
      "id": "<UUID, uppercase>",
      "name": "Work",
      "emoji": "💼",
      "color": "#5B8DEF",
      "browser": { "appPath": "/Applications/Google Chrome.app" }
    },
    {
      "id": "<UUID>",
      "name": "Personal",
      "emoji": "🏠",
      "color": "#30A46C",
      "browser": { "appPath": "/Applications/Safari.app" }
    }
  ],
  "apps": [
    { "id": "<UUID>", "name": "Slack", "kind": "original", "sourcePath": "/Applications/Slack.app",
      "universeID": "<Personal id>", "env": {}, "icon": "original" },
    { "id": "<UUID>", "name": "Work Slack", "kind": "clone", "sourcePath": "/Applications/Slack.app",
      "universeID": "<Work id>", "env": {}, "icon": "ivory" }
  ]
}
```

- `kind`:
  - `original`: the installed app as is.
  - `clone`: a separate copy at `/Applications/<name>.app` with its own Dock icon. Electron apps and
    Chromium browsers get their own logins automatically. Other apps share logins with the original.
    Apps in `/System` can't be copied.
  - `launcher`: rarely needed. A small app that opens an existing Chromium profile folder
    (`dataDir`). Its windows share the original's Dock icon. Prefer `clone`.
- `icon` (copies only):
  - `ivory`: an ivory tile with the app's symbol in graphite. The default, and easy to tell apart.
  - `graphite`: a graphite tile with the symbol in ivory.
  - `tint`: recoloured in the universe's `color`.
  - `invert`: inverted colours. `original`: unchanged.
- `browser.dataDir` (optional): a Chromium profile folder, e.g.
  `~/Library/Application Support/Chrome-Personal`.
- Leave out `bundleID` and `dataDir` for clones. Multiverse fills them in when it builds.
- Copy names must not match an app that already exists in `/Applications`. Multiverse refuses to
  replace apps it didn't make.
- Generate ids with `uuidgen`. Colour palette: `#7E95B0 #9DA67C #C2876A #CDB98A #8F7A9E #7FA394`.

Then validate:

```bash
MV check
```

## 5. Create the copies

```bash
MV build --all
```

Before running this, tell the user:
- Each copy is a separate app with its own Dock icon.
- Copies of Electron and Chromium apps need a fresh sign-in.
- The first time such a copy opens, macOS asks to let it use "<App> Safe Storage" from the keychain.
  They should enter their Mac password and click **Always Allow**. It's expected and safe, and if
  they deny it, the copy can't keep them signed in.

## 6. Turn on link routing

```bash
MV make-default-browser
```

macOS shows a dialog. Tell the user to click **Use "Multiverse"**. You can't click it for them.
The first time a link goes to a browser profile, macOS may ask whether Multiverse may control that
browser. The user should click **Allow**.

## 7. Verify

```bash
MV status        # every app "ready", "Link routing: on"
tail -f ~/Library/Logs/Multiverse.log    # ask the user to click a link in one app per universe
```

Each line in the log shows `<app> -> <universe> <host>`. If a link goes to the wrong universe, the
log shows which app Multiverse thought sent it.

## Later

- After an original app updates, `MV status` says so. Run `MV build "<copy name>"` while the copy is
  closed, or `MV build --all`. App data and logins are kept.
- Everything can also be changed in Multiverse → Settings… in the menu bar.
- Never delete the user's original apps or anything in `~/Library/Application Support`. Multiverse
  never does either.
