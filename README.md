# Sleepover — Week 1 Kill Test

The ugliest possible test of one question: **is being a sleeping bag funny to move around in?**
Single-player, gray-box, no networking, no art. If you and a friend laugh at the
movement within 5 minutes *without the monster*, it's a GO.

---

## Setup (from scratch)

### 1. Install Godot 4.3+
- Download the **standard** build (not .NET/Mono — this project is pure GDScript)
  from <https://godotengine.org/download/windows/>.
- It's a single `.exe`, no installer. Put it anywhere (e.g. `Downloads`), run it.

### 2. Open this project
- Launch Godot → **Import** → browse to this folder → select `project.godot` → **Import & Edit**.
- (Or just drag `project.godot` onto the Godot window.)

### 3. Run
- Press **F5** (or the ▶ Play button, top-right).
- First run may ask you to select a main scene — it's already set to
  `scenes/Main.tscn`, so it should just go.

That's it. No plugins, no Steam, no asset packs needed for this milestone.

---

## Controls — upright potato-sack posture
| Key | Verb |
|---|---|
| **W/A/S/D** (hold) | Shuffle — slowed walk (~1.3 m/s), quiet, stamina regens |
| **Space** (tap) | Hop — fast burst your way (yellow arrow), LOUD landing thump, **costs 1 pip** |
| **Space at 0 pips** | Face-plant. That's the game. |
| **W/A/S/D** (mash) | Wriggle upright after a tumble (~2.5s, fully vulnerable) |
| **Mouse** | Orbit the camera (never steers the bag) |
| **Q** (hold) | Look-back glance — see the thing behind you |
| **R** | Reset player + monster to spawn |
| **Esc** | Free / recapture the mouse cursor |

**Stamina: 5 pips** (bar at bottom-center). Regens ~1 pip / 2s while grounded;
nothing regens mid-air. Bad landings (too fast, e.g. down the stairs) also tumble you.

The **red cube** is the monster. It hunts *noise*, not sight — every hop landing
and tumble crash makes a ping it chases; shuffling is silent. It's faster than
your shuffle and slower than your hop chain, so **escapes last exactly as long
as your pips do**. Touch = **CAUGHT** (screen freeze — no death logic this week).

Try the staircase at the far end. Hopping *down* it on low stamina is the point.

---

## Tuning the feel
All the feel constants (hop power, wobble stiffness, topple threshold, monster
speed…) are in **[FEEL.md](FEEL.md)** and exposed as `@export` vars. While the
game is running, open the **Remote** tab of the Scene panel, click the `Player`
or `Monster` node, and drag values in the Inspector to feel changes live. Write
the keepers back into `FEEL.md`.

Change **one** number at a time. That's the whole job this week.

---

## Pass / fail (be honest)
- ✅ **PASS** — you laugh at the movement itself within 5 min, no monster needed.
- ✅ **PASS** — tumbling down the stairs makes you want to do it again.
- ❌ **FAIL** — movement is a chore / fights you without being funny.
  → Pivot the codebase toward Séance and revisit locomotion later.

---

## What's here (HouseKit layout — spec 1.1)
```
project.godot            # Godot 4.7 project + autoloads + gravity tweak
core/
  player/Player.gd       # the upright sleeping-bag RigidBody — shuffle/hop/stamina/tumble
  networking/SteamManager.gd  # Steam init + lobby helpers (+ ENet loopback test mode)
  audio/NoiseBus.gd      # global "noise ping" signal bus (autoload)
games/sleepover/
  Main.tscn / Main.gd    # game scene: camera, HUD, catch/reset, 20Hz net sync
  Monster.gd             # red-cube Housesitter placeholder (Patrol/Investigate/Chase)
maps/house_suburban/
  HouseSuburban.gd       # data-driven full-house gray-box (16 rooms, 3 stairs, chute)
addons/godotsteam/       # GodotSteam 4.20 GDExtension
FEEL.md                  # every tuning constant, with what-if guidance
FRIEND_SETUP.md          # cold-start guide for playtesters
```

## Deliberately NOT in this milestone
Per the build spec's Week-1 scope: no GodotSteam / 2-player sync, no Unzip verb,
no objectives, no cocoon/rescue, no real art. Those come after the movement
passes the laugh test. The level is built procedurally so there are no binary
scene files to merge-conflict once networking lands.

## Next step once this passes
Wrap **GodotSteam** for the 2-player networking spike (needs Steam installed +
the GodotSteam plugin binaries + Spacewar appid 480 for dev). Per the spec's
working notes, we'll fetch the current GodotSteam lobby docs at that point rather
than trusting memory — the API moves fast.
