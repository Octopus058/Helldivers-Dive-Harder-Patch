# Changelog

## 0.1.0

First release.

### Features

- **Unlock defeated factions** — factions with `status == "defeated"` are treated as
  `active` on the client, reappear on the campaign map and can be selected for missions;
  the front line is placed in sector 10 (`points = points_max * 0.95`).
- **Reveal hidden objectives** — hooks `Level.get_data(level, "objective_hidden_data")`
  and returns `nil` while the option is on, which equals permanently owning the UAV Mk2
  hidden-objective detection. Off by default.
- **Enemy health tiers** — `ENEMY HEALTH` with `OFF` / `HARD` (total HP ×1.5) /
  `HELLDIVE` (×2). `max_hitpoints` and `constitution` (the total damage an enemy can
  absorb is the sum of both) are scaled when the enemy spawns, filtered with
  `EntityAux.has_component(unit, "enemy")` so players and allies are untouched. The
  original values are cached in a weak table, so a repeated `setup` never multiplies
  twice. Runtime only, no save writes, host authoritative.
- **MOD SETTINGS page** — one extra row in the pause menu below `SETTINGS`; entering it
  replaces the page with the QoL group (13 options, only when QoL is installed), the
  DIVE HARDER group (5 options) and `APPLY CHANGES`. Keyboard
  up/down/left/right, mouse row clicks and arrow clicks, and `ESC` / `Q` / `BACK` to
  leave.
- **HUD ping** — `HUD PING` draws `PING: xx.xxms` below each player card, left aligned
  outside the card; only the local machine is skipped. The value is the mean of the last
  N samples (scheme B) and comes from the same function as the pause menu ping. The pause
  menu used to show half the RTT, which the patch corrects by doubling it in
  `GuiManager.draw_text`.
- **PING WINDOW** — 3 / 5 / 10, the number of recent samples the ping average uses.
- **Friends list host info** — entering the multiplayer `FRIENDS` filter triggers one
  vanilla room refresh, so host information appears without pressing refresh.
- **Results-screen chat font** — after `GuiManager.update`, `qol/display_player_text` is
  copied to `GuiManager.display_player_text`, fixing QoL's setting on the results and
  planet reward screens.
- **Main menu version label** — QoL on top, `Dive Harder: v.0.1.0` below it.
- **Option text** — option names and values are uppercase with underscores stripped, and
  untranslated `LOC:xxx` keys are shown as readable names.

### Packaging

- Release zip `dive_harder_pack.zip`, produced by `tools/package.ps1` (build, assemble,
  install locally, zip).
- Two payloads: `dive_harder_vanilla.bin` (vanilla) and `dive_harder_qol.bin`
  (QoL 0.29.2); the installer picks one by the SHA256 of `9cf71054ea26dddf`.
- Standalone boot package `resource_packages/boot_dh` (file `05cd02202827e9a0`);
  installing only changes `boot_package` in `settings.ini`, and game / QoL files are never
  touched.
- Build checks: the base recompiles to byte-identical bytecode, and every resource except
  `character_state_machine` stays byte-identical inside the package.
- The SHA256 values inside `install.ps1` and `INSTALL.txt` are written by the packaging
  script.

### Known limitations

- Defeated factions are a client-side reopen plus a front-line position; the server
  campaign is not advanced and boss planets still use the local flow.
- Hidden objectives and enemy health are host-authoritative.
- Enemy health is applied when an enemy spawns, so a tier change only affects later spawns.
- After a QoL update the QoL payload has to be rebuilt from the new QoL boot package.
