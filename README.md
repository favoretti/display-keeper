# Display Keeper

A tiny macOS menu-bar app that puts your external monitors, and the windows on them, back where they belong
after the Mac wakes up.

## The problem

If you have two (or more) **identical monitors**, macOS often swaps them after sleep: the left screen's
windows and menu bar end up on the right one. It happens because identical monitors usually report the
same EDID serial number, so macOS cannot tell them apart and hands out their display IDs in whatever
order they come up. Tools like `displayplacer` key on those same IDs, so a saved `displayplacer`
command breaks in exactly the case you need it.

## How Display Keeper fixes it

- It identifies each monitor by its **per-unit serial** (the alphanumeric serial in the EDID descriptor,
  e.g. `HTPM100050`), which is unique even when the numeric serial is not. If a monitor has none, it
  falls back to the physical port.
- You save a layout once per **set of monitors** (home desk, office desk, …). Each set gets its own
  profile and is recognised automatically.
- After wake, unlock and any display change, it compares the current arrangement with the saved one and
  restores positions and resolutions if they differ. If they already match, it does nothing.
- It rearranges displays with macOS's public CoreGraphics API. No `displayplacer` or other helpers needed.
- Optionally it also saves **window positions** with the layout, and puts windows back on the right
  monitor once the displays are in place. Windows are checked on every pass, because macOS can move them
  even when the displays came back in the right order.

## Install

Download `DisplayKeeper-<version>.zip` from [Releases](../../releases), unzip, and move
`DisplayKeeper.app` to `/Applications`.

Until releases are notarized, macOS will block the first launch: right-click the app → **Open**, or run
`xattr -dr com.apple.quarantine /Applications/DisplayKeeper.app`.

Or build it yourself (Xcode 16+ / Swift 6 toolchain, macOS 13+):

```sh
git clone https://github.com/favoretti/display-keeper
cd display-keeper
scripts/build-app.sh          # -> dist/DisplayKeeper.app
```

## Use

1. Arrange your displays the way you want them in System Settings → Displays, and your windows the way you
   like them.
2. Menu-bar icon → **Save Current Layout**. This saves displays and windows together; nothing is saved
   automatically, so re-save whenever you change your setup.
3. Turn on **Open at Login**.
4. For window restore, turn on **Restore Windows** and grant Accessibility access when asked.

That's it. Repeat step 1–2 at each desk you use.

### How windows are matched

Saved windows are matched to open ones in this order: the same window (if the app has kept running), then
app + window title, then app + the window's position in the app's window list. Windows that match nothing
are left alone. Minimised and full-screen windows are skipped, and only windows on the current Space of
each display can be moved.

The menu also has **Restore Saved Layout**, **Forget Layout for These Displays** and
**Pause Automatic Restore**.

## Command line

The app bundle contains a CLI at `DisplayKeeper.app/Contents/Resources/display-keeper`:

```
display-keeper list       # online displays and the key each is saved under
display-keeper save       # save displays and windows for this set of monitors
display-keeper windows    # list open windows as they would be saved
display-keeper restore    # re-apply it now
display-keeper status     # compare current vs saved
display-keeper profiles   # list saved profiles
display-keeper forget     # delete the profile for the current monitors
display-keeper watch      # run headless (e.g. from a LaunchAgent) instead of the menu-bar app
```

Profiles live in `~/Library/Application Support/DisplayKeeper/profiles.json`, shared by app and CLI.

## Limitations

- Reading the per-unit serial uses an undocumented CoreDisplay function
  (`CoreDisplay_DisplayCreateInfoDictionary`) to find each display's IOKit node. Public APIs only expose
  the numeric serial, which is the one identical monitors share. This is why Display Keeper is not on
  the Mac App Store. If Apple removes the function, it falls back to the numeric serial and then the port.
- Tested on Apple silicon. On Intel Macs the IOKit layout differs; the per-unit serial lookup may fall
  back to the port.
- Mirroring and rotation are not managed; mirrored displays are left as they are.
- Until releases are signed with a Developer ID, macOS treats every new build as a new app, so the
  Accessibility permission has to be granted again after each update.

## License

MIT
