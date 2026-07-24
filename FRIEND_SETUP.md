# Sleepover Playtest — Setup (5–10 minutes)

You're joining a co-op test of a sleeping-bag horror-comedy prototype. You are a
kid zipped into a sleeping bag. Something is in the house with you. You cannot
run, you can barely walk, and the only way out is finishing three tasks together.

Nothing to buy. Nothing to install except Godot, which is a single .exe.

## 1. Steam
Have Steam installed and **running**, logged into any account. That's it — the
test runs under Valve's free developer app.

Steam is what finds your friend's lobby, and it's also what carries voice chat.

## 2. Godot 4.7 (the engine — one .exe, no installer)
- Download **Godot 4.7 (standard, NOT the .NET version)**:
  <https://godotengine.org/download/windows/>
- Unzip it anywhere. Downloads is fine. You'll get `Godot_v4.7-stable_win64.exe`.

## 3. Get the game
- **Git:** `git clone https://github.com/jheueyy/SLEEPOVER.git`
- **No git:** on <https://github.com/jheueyy/SLEEPOVER> click **Code → Download ZIP**, unzip it.

## 4. Run it
**Easy way:** double-click `run.bat` in the SLEEPOVER folder. It finds Godot for
you. If it can't, it prints exactly what to do.

**Manual way:**
1. Launch the Godot exe → **Import** → browse into the SLEEPOVER folder → pick
   `project.godot` → **Import & Edit**.
2. Wait for it to finish importing (first time takes about a minute).
3. Press **F5** to play.

## 5. Get into a game
You'll land on a menu.

- **Host:** click **HOST GAME**. A 6-character **join code** appears at the top
  of the lobby. Read it out.
- **Joining:** type that code into the box, click **JOIN GAME**.
- Everyone clicks **READY**. The host clicks **START**.

Before you start, hit **SETTINGS** (on the menu *and* in the lobby) and check
your mic: voice defaults to **push-to-talk on V**. Switch it to open mic there if
you'd rather. You can also flip it mid-round with **M**.

> If it says "Steam offline", make sure Steam is actually running, then restart
> the game. Solo still works offline if you just want to walk around.

## Controls
| Key | What it does |
|---|---|
| **W A S D** | Shuffle — slow, and completely silent. Your default state. |
| **Space** | Hop — fast, but **loud**, and costs a stamina pip (the bar at the bottom). At 0 pips you face-plant. |
| **W A S D** (mash) | Get back up after falling over |
| **Mouse** | Camera |
| **Q** (hold) | Look behind you |
| **E** | Interact — read a clue, use a keypad, grab something. Some need a **hold**; the prompt tells you which. |
| **E** (hold, next to a cocooned friend) | Unzip them free |
| **0–9** | Dial a phone / type on a keypad, once its panel is open |
| **V** (hold) | Push-to-talk |
| **M** | Switch push-to-talk ↔ open mic |
| **F** | While cocooned: watch a teammate. `[` and `]` cycle between them. |
| **Esc** | Pause — resume, settings, or leave the game |
| **F3** | Debug readout (ignore unless I ask) |

Stairs are walkable at a shuffle — slower than flat ground, but you never need to
spend hops on them. If you find a staircase you can't walk up, that's a bug, tell me.

## How a round works
Three tasks unlock the way out. Each is a **clue** plus an **action**: find a note,
a birthday, a wiring diagram — then use what it told you at the matching phone,
keypad, or fuse box. Your HUD tracks *what* and *whether*, never *where*. Finding
things is the game.

**The Housesitter** starts asleep in the attic and wakes up partway through. She
hunts **noise and line of sight**. She cannot see you if you hold still, and
shuffling makes no sound at all. Hopping, unzipping your bag, dialing, and the dog
barking are all things she can hear. She hums a lullaby, so you can usually track
her through the walls if you shut up and listen.

If she catches you, you're **cocooned** — zipped in and unable to move. That's not
the end: a teammate can unzip you (hold E for a few seconds, and it's loud). While
you wait, press **F** to watch someone.

Once all three tasks are done, every unlocked door opens and you run for it.

Voice chat is **proximity-based**: distance makes people quieter, and walls and
floors muffle them. If someone sounds underwater, they're on another floor.

## What I need from you
Tell me what felt bad, not just what broke. Especially:
- anything you pressed that didn't respond
- anywhere you got stuck on geometry
- whether you could hear each other properly
- whether being caught felt survivable, or felt like the round just ended for you

That's it. Get in the bag.
