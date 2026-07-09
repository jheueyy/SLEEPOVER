# Sleepover Playtest — Setup (5–10 minutes)

You're joining a 2-player test of a sleeping-bag horror-comedy prototype.
No purchases needed, nothing to install except Godot (a single .exe).

## 1. Steam
- Have Steam installed and **running**, logged into any account.
- That's it — the test runs under Valve's free developer app, nothing to buy.

## 2. Godot 4.7 (the game engine — one .exe, no installer)
- Download **Godot 4.7 (standard, NOT the .NET version)** for Windows:
  <https://godotengine.org/download/windows/>
- Unzip it anywhere (e.g. Downloads). You'll get `Godot_v4.7-stable_win64.exe`.

## 3. Get the game
Either:
- **Git:** `git clone https://github.com/jheueyy/SLEEPOVER.git`
- **No git:** on <https://github.com/jheueyy/SLEEPOVER> click **Code → Download ZIP**, unzip.

## 4. Run it
1. Launch the Godot exe → **Import** → browse into the SLEEPOVER folder → pick `project.godot` → **Import & Edit**.
2. Wait for the editor to finish importing (first time takes ~a minute).
3. Press **F5** to play.

> If the blue NET line in-game says "Steam offline", make sure Steam is running,
> then close and F5 again.

## 5. Join the game
- Wait until the host says their lobby is up (they press **H**).
- Press **J**. The NET line should switch to `CLIENT in lobby …`.
- You should see the host as an **orange bag**. You're the cyan one on your screen.

## Controls
| Key | What it does |
|---|---|
| **W/A/S/D** | Shuffle (slow, silent) |
| **Space** (tap) | Hop — costs 1 stamina pip (bar at bottom). At 0 pips you face-plant |
| **W/A/S/D** (mash) | Get up after falling over |
| **Mouse** | Camera |
| **Q** (hold) | Look behind you |
| **R** | Reset the round (host only — ask them if you're stuck) |

The red cube hunts **noise** — hop landings and crashes. Shuffling is silent.
It's faster than your shuffle and slower than your hops... while your stamina lasts.

That's it. Get in the bag.
