# GTA VI Radio for FiveM

A FiveM port of **VI Radio**, the GTA V Legacy singleplayer mod by *sej0bec*: a
GTA VI–styled radio carousel, a mute system, station logos, and a slow-motion
effect while you browse stations.

Standalone and client-side — no framework dependency.

## Install

1. Copy the `vi_radio` folder into your server's `resources/` directory.

   > The folder **must** be named `vi_radio`. If you cloned this repo, rename the
   > checkout — the resource name is what `exports['vi_radio']` resolves to.

2. Add to `server.cfg`:

   ```
   ensure vi_radio
   ```

3. Tune `config.lua` to taste.

## Controls

| Action | Keyboard | Controller |
| --- | --- | --- |
| Open the radio wheel | Hold **Q** | Hold **D-pad Left** |
| Previous / next station | **←** / **→**, or the mouse wheel | **Right stick** left / right |
| Mute / unmute | **O**, or **↓** while the wheel is open | **D-pad Down** while the wheel is open |

Both open bindings can be rebound under **Settings → Key Bindings → FiveM**;
they are two default bindings on the same command, so changing one leaves the
other alone.

Controller layout follows the vanilla radio wheel: D-pad Left opens it, the right
stick picks a station. The D-pad cannot be used for browsing because D-pad Left
is the open button (it is `INPUT_CELLPHONE_LEFT` and `INPUT_WEAPON_WHEEL_PREV`
as well), so holding it would otherwise spam a station change every frame. While
the wheel is open on a pad the camera is locked so the right stick does not swing
the view — set `Config.Controller.lockCamera = false` if you would rather it did.

Mute has no global controller binding because every pad button is already taken
while driving; it lives on D-pad Down inside the wheel instead. Set
`Config.Controller.enabled = false` to drop controller support entirely.

## Configuration

Everything lives in `config.lua`, mirroring the original mod's `VI Radio.ini`:

* **Controls** — keys, mouse-wheel scrolling, arrow auto-repeat, whether
  passengers and on-foot players can use it.
* **Feel** — `TimeScale`, timecycle modifier and strength, hi-DOF, radar hiding,
  open/close sounds and volume.
* **HUD** — tile size, spacing, colours, borders, slide time, side icons, the
  info-line and text positions. Values are authored at 1920x1080 and scale to
  the player's resolution.
* **Stations** — display label, logo and genre per station.

## Adding or hiding stations

`Config.Stations` maps a game station name to its display label, logo file and
genre. Stations the game reports as unlocked but that are missing from the table
still appear, using a tidied version of their raw name and a text tile instead
of a logo. To drop one from the wheel:

```lua
['RADIO_05_TALK_01'] = { label = 'West Coast Talk Radio', hidden = true },
```

Logos live in `html/logos/` — drop in a PNG and reference it by filename.

## Exports

```lua
exports['vi_radio']:SetNowPlaying(title, artist)
exports['vi_radio']:IsOpen()        --> boolean
exports['vi_radio']:IsMuted()       --> boolean
exports['vi_radio']:SetMuted(bool)
exports['vi_radio']:GetStation()    --> current radio station name
```

## Differences from the singleplayer mod

The original is a compiled ScriptHookVDotNet plugin. FiveM cannot load SHVDN
assemblies, so this is a rewrite rather than a drop-in conversion. The
behaviour, layout values, station list and artwork carry over; the
implementation does not.

* **HUD** — drawn with NUI (`html/`) instead of native textures. Every value
  from the `[HUD]` section of the original `.ini` is passed to the page as CSS
  variables, so the layout stays fully tunable.
* **Track title / artist — not available.** The singleplayer mod reads the
  current track's GXT text id and resolves it through the game's string table.
  FiveM exposes `GetAudibleMusicTrackTextId()` but has no native that turns that
  id back into text, so the title line is empty by default and the second line
  falls back to the station genre (`Config.Hud.subtitle`). If your server knows
  what is playing — custom streamed stations, xsound, a metadata feed — push it
  in:

  ```lua
  exports['vi_radio']:SetNowPlaying('Track title', 'Artist')
  -- or from the server:
  TriggerClientEvent('vi_radio:setNowPlaying', src, 'Track title', 'Artist')
  ```

* **Slow motion** — `SetTimeScale` is client-side only. While the wheel is open
  the player's vehicle drifts out of sync with what everyone else sees, and the
  longer the wheel is held the more visible that is. It is on by default to
  match the original feel; set `Config.TimeScale = 1.0` to keep only the HUD.
* **Mute** — uses `SetVehicleRadioEnabled` /
  `SetMobileRadioEnabledDuringGameplay` so the station is preserved, and is
  re-applied when the player changes vehicle.
* **In-game settings editor (F10)** — dropped. Edit `config.lua` instead.
* **Non-Stop-Pop song replacement** — the optional part of the original download
  is an OpenIV `.rpf` swap. On a server that would have to ship as a streamed
  audio pack for every client, so it is not included.

## Credits

* **sej0bec** (GTA5-Mods user `sbc17`) — VI Radio for GTA V Legacy Edition: the
  concept, HUD design, station logos, icons and sound effects. This port would
  not exist without it.
  Original mod: <https://www.gta5-mods.com/scripts/vi-radio-v1-0>
* **Vernon Adams** — the Anton typeface, SIL Open Font License 1.1.

## License

Code is released under the [PolyForm Noncommercial License 1.0.0](LICENSE.md).
You may use, modify and share it for any noncommercial purpose. You may **not**
use it, or anything derived from it, for commercial advantage or monetary
compensation — that includes selling it, bundling it into a paid package, and
putting it behind donation perks, subscriptions or any other paid tier.

The artwork and sound effects in `html/` are the work of **sej0bec** and are
redistributed here with credit; they are not covered by this license. Ask the
original author before reusing them elsewhere.
