# Dive Harder Patch

**English** | [中文](README.zh-CN.md)

Unofficial Lua mod for Helldivers 1 (Steam, 2015): reopens defeated factions, shows hidden
objectives directly, adds optional enemy health tiers, and collects the QoL options (by
SomeDoggo) and its own switches into one **MOD SETTINGS** page in the pause menu.

The mod works as a standalone boot package (`resource_packages/boot_dh`): it modifies
neither the game files nor the QoL files. Installing only points `boot_package` in
`settings.ini` at the new package; uninstalling points it back.

Current version: **0.1.1**

## Features

| Feature | Description | Default |
| --- | --- | --- |
| Unlock defeated factions | Factions the community has already defeated reappear on the campaign map and can be selected for missions; the front line sits in sector 10 | ON |
| Reveal hidden objectives | Yellow question-mark missions are drawn with their real icon from mission start, no recon UAV needed | OFF |
| Enemy health tiers | `ENEMY HEALTH`: `OFF` / `HARD` (total HP ×1.5) / `HELLDIVE` (×2) | OFF |
| HUD ping | draws `PING: xx.xxms` below the player ID card, left aligned at its outer edge | OFF |
| Ping window | mean of the last 3 / 5 / 10 samples (smaller reacts faster, larger is smoother) | 5 |
| Friends list refresh | refreshes the room list once when a filter in the multiplayer menu is opened, so host information shows without pressing refresh | auto |
| Results-screen chat font | fixes QoL's `display_player_text` not taking effect on the results / planet reward screens | follows QoL |
| Version label | main menu shows the QoL version on top, `Dive Harder: v.0.1.1` below it | — |
| Option text | option names uppercase with underscores stripped; QoL's untranslated `LOC:xxx` keys shown as readable names | — |

### MOD SETTINGS

The pause menu (main menu / ship / mission) gets one extra row below `SETTINGS`; entering
it replaces the page with:

- the **QoL** group (only shown when QoL is installed);
- the **DIVE HARDER** group (5 options);
- `APPLY CHANGES`.

## Requirements

- Genuine Helldivers 1 on Steam (Windows x64).
- QoL 0.29.2 is **optional** — the installer detects it and picks the matching payload.
- Building from source needs Python 3.8+, LuaJIT 2.0.3 and a local game installation.

## Install

1. Download `dive_harder_pack.zip` from the
   [Releases page](https://github.com/Octopus058/Helldivers-Dive-Harder-Patch/releases/latest)
   and extract it;
2. Run `install.bat`: it finds the game directory, tells vanilla and QoL apart by the
   SHA256 of `9cf71054ea26dddf`, copies the matching payload, backs up `settings.ini` and
   points `boot_package` at `resource_packages/boot_dh`;
3. Fully quit the game process, then start the game.

In game: press `ESC` and open the row below `SETTINGS` (`MOD SETTINGS`); confirm on
`APPLY CHANGES` when done.

Uninstall: run `revert.bat`; `settings.ini` is restored from the backup and QoL comes back
exactly as it was. The game's `9e13…` / `9cf…` files have never been modified.

## Build from source

### Preparing the base

`vendor/base_csm.lua` is the decompiled `lua/character_states/character_state_machine`.
It is game code:

```powershell
python tools/extract_base.py                 # -> build\cs_orig.bc
luajit-decompiler-v2.exe build\cs_orig.bc    # writes the result into its own output\ directory
# save that file as vendor/base_csm.lua
```

`build.py` recompiles it and only builds when the result is byte-identical to the bytecode
inside the game's boot package.

### Build requirements

- Python 3.8+
- **LuaJIT 2.0.3** (this game's Lua runtime; other versions produce incompatible bytecode)
- a Helldivers installation whose `contents` folder has `9e13b2414b41b842.orig` (vanilla
  boot package backup)
- for the QoL payload, a QoL boot package backup `9e13b2414b41b842.qol_boot_backup_*`
  (the older `.enemy_stats_backup_*` name also works; the QoL installer or an older
  release of this mod leaves one behind)

### Build

```powershell
python tools/build.py
# or with explicit paths
python tools/build.py --contents "E:\Steam\steamapps\common\Helldivers\contents" --luajit "C:\luajit\luajit.exe"
```

Outputs `dist/dive_harder_vanilla.bin` and `dist/dive_harder_qol.bin` and prints their
SHA256 values for the installer.

### Packaging a release

```powershell
pwsh -File tools/package.ps1                            # build + assemble + install locally + zip
pwsh -File tools/package.ps1 -NoInstall                 # build and zip only
```

## Tests

Offline self-tests that run the hooks against fake objects, no game required:

```powershell
luajit tests\test_health.lua
luajit tests\test_menu.lua
luajit tests\test_ping.lua
```

Every script prints each assertion and ends with `all … tests passed`; failures exit
non-zero.

## Repository layout

```
lua/
  dive_harder.lua        all hook code
  ping_hud.lua           HUD ping / ping window / friends refresh
installer/
  install.ps1, install.bat
  revert.ps1,  revert.bat
  INSTALL.txt            player notes shipped in the release zip
tools/
  bundle.py              boot package read/write + murmur64a
  build.py               assemble the Lua, compile, emit both payloads
  extract_base.py        pull the original bytecode out of a boot package
  package.ps1            build + assemble + install + zip
tests/                   offline self-tests
```

## Known limitations

- Defeated factions are only "reopened on the client, front line in sector 10"; the server
  campaign is not really advanced, and mother planets (boss planets) still use the local
  flow.
- Hidden objectives and enemy health are host-authoritative.
- Enemy health is scaled when an enemy spawns, so changing the tier only affects enemies
  spawned afterwards.
- After a QoL update the QoL payload has to be regenerated from the new QoL boot package;
  the installer identifies versions by the `9cf` hash and aborts on unknown ones.

## License

MIT, see [LICENSE](LICENSE). HELLDIVERS and its assets are © Sony Interactive
Entertainment / Arrowhead Game Studios; this project is unofficial and not affiliated with
them. QoL is the work of SomeDoggo. `vendor/base_csm.lua` is decompiled from the player's
own game installation, is not part of this repository, and this repository distributes no
game assets.
