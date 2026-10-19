# Sleepover

A Godot co-op horror/comedy prototype: move around a house in a sleeping bag, complete randomized objectives, evade the Housesitter, rescue friends, and collect lore that unlocks cosmetics.

## Run

Open `project.godot` in the locally used Godot 4.7 standard build and press F5, or use `run.bat`. The launcher accepts a `GODOT` environment variable pointing to your executable. The main scene is `core/ui/AppRoot.tscn`.

Host Game enters a lobby. Ready up, then Start. Without Steam initialization, hosting falls back to solo play. Steam lobbies use the bundled GodotSteam extension and development app ID 480. See [FRIEND_SETUP.md](FRIEND_SETUP.md) for friend setup.

## Current build

- Menu, ready-up lobby, Steam transport and local ENet test mode.
- Procedural multilevel house, sleeping-bag locomotion, AI pursuit and hiding.
- Randomized objectives, inventory, keys, rescue and three round outcomes.
- First-person/third-person camera state, proximity voice, scrapbook and cosmetics.
- Settings for master/effects/incoming-voice volume, mouse sensitivity and voice mode. Back or Escape saves changes.

This remains a prototype. Late joining, host validation of client gameplay claims, several lobby options, and key rebinding need more work. See [AUDIT.md](AUDIT.md) for evidence and the prioritized build backlog.

## Verification (PowerShell)

Run from this project directory. Use a private data directory so automated play does not change your real progression:

```powershell
$godotExe = 'C:\path\to\Godot_v4.7-stable_win64_console.exe'
New-Item -ItemType Directory -Force .audit-user | Out-Null
$env:APPDATA = Join-Path (Get-Location) '.audit-user'
& $godotExe --headless --path . --log-file audit-final.log -- --selftest
& $godotExe --headless --path . --log-file audit-regression.log --scene res://tests/AuditRegression.tscn
```

The gameplay harness prints `RESULT: ALL PASS`; the regression scene prints `RESULT: PASS`. Both exit 0 on success. The APPDATA override applies to this PowerShell session and its child processes; use a separate terminal for normal play.

For transport smoke testing, run two terminals with isolated APPDATA directories and the same executable:

```powershell
# First terminal
& $godotExe --headless --path . -- --enet-host
# Second terminal
& $godotExe --headless --path . -- --enet-join
```

ENet uses localhost port 24565, auto-readies both peers and starts a round. Stop with Ctrl+C. Synthetic voice in this harness is not a microphone quality test.

## Project map

| Location | Responsibility |
|---|---|
| core/ui | Menu, lobby, settings, pause and scene lifecycle |
| core/player | Bag physics, procedural visuals and eyes |
| core/networking | Steam transport and lobby roster |
| core/audio | Noise bus, procedural sound and voice |
| core/save | Local/cloud scrapbook and preferences |
| games/sleepover | Gameplay, objectives, items, monster, lore and embedded acceptance tests |
| maps/house_suburban | Procedural house geometry and anchors |
| tests | Focused engineering regression scene |

[FEEL.md](FEEL.md) records tuning history. The build-spec, master-build and launch-plan documents describe design intent and future milestones; they are not proof those features are implemented.
