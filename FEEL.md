# FEEL.md — Sleeping-Bag Locomotion Tuning

> **Every number that affects how the bag *feels* lives here.** They are all
> `@export` vars, so you can also drag them in the Godot Inspector **while the
> game is running** and watch the change instantly. When you land on a value you
> like, write it back here so the file stays the source of truth.
>
> Workflow: play for ~2 min → change ONE constant → play again. Feel tuning is
> 80% of Week 1. Don't change three things at once; you won't know which helped.

Constants live on the actor scripts. Select the node in the running scene
tree (**Remote** tab) to tune live.

**The kill-test question this build must answer:** do players hoard hops when
the cube approaches, then panic-spam and tumble anyway? If yes, the panic
engine works.

---

## Player (`core/player/Player.gd`) — upright potato-sack posture

### Shuffle — the safe, agonizing baseline
| Constant | Default | What it does | If it feels wrong |
|---|---|---|---|
| `shuffle_force` | 45.0 | push while a WASD key is held | too sluggish to start? raise |
| `shuffle_speed` | 2.0 | hard speed cap (m/s) | was 1.3 — playtest verdict: boring + monster too quick |
| `brake_damping` | 8.0 | stop rate with no input | holds position on stair ramps; lower = more slide |

### Hop & Stamina — the panic economy
| Constant | Default | What it does | If it feels wrong |
|---|---|---|---|
| `hop_speed` | 3.6 | forward burst speed of one hop | was 4.0 — chains outran the monster too easily |
| `hop_up_speed` | 4.6 | upward speed per hop (independent knob) | jump height = up²/(2·gravity) ≈ 0.88m — 3.6 still snagged on stair risers |
| `stamina_max` | 5.0 | hop pips | 5 → 3 → 5: with the full-size house, 3 ran dry before anywhere interesting |
| `stamina_regen` | 0.6 | pips/sec while grounded (1 pip / ~1.7s) | tuned upward with the 3-pip tank — small tank, fast refill |
| `regen_delay` | 1.6 | secs after any hop before regen resumes | kills the "6th pip" bug — mid-chain the tank is strictly fixed |
| `land_loudness` | 1.0 | noise ping per landing thump (0..1) | the risk tax — keep it the loudest thing |
| `land_tumble_speed` | 6.5 | land harder than this = face-plant | above one flat hop (~4) — only stairs/chains trip it |

### Wobble & Tumble — the source of all comedy
| Constant | Default | What it does | If it feels wrong |
|---|---|---|---|
| `upright_stiffness` | 40.0 | spring holding the bag up | was 28 — tumbled from a single flat hop |
| `upright_damping` | 7.0 | settles the sway | low = bag keeps swaying, recoveries feel lucky |
| `tumble_angle_deg` | 60.0 | tilt past this = down you go | lower = tumbles constantly |
| `hop_wobble_torque` | 1.2 | random lean per hop | was 3.0 — a wobble, not a coin flip |
| `faceplant_kick` | 5.0 | forward flop when hopping on empty | was 9 — sent the bag flying, not flopping |
| `recover_mashes_needed` | 8.0 | key mashes to wriggle upright (~2.5s) | higher = longer vulnerable window |
| `recover_mash_kick` | 3.0 | righting impulse per mash | feedback per mash press |
| `tumble_loudness` | 0.8 | crash ping when you go down | tumbling near the monster should be fatal-ish |

---

## Camera (`games/sleepover/Main.gd`) — the horror multiplier
| Constant | Default | What it does | Design rule |
|---|---|---|---|
| `cam_height` | 0.9 | pivot height above the bag | LOW — the house must loom |
| `cam_distance` | 2.2 | spring-arm length behind | CLOSE — the monster fills the frame |
| `cam_shoulder` | 0.35 | right-shoulder offset | slight bias per spec |
| `mouse_sensitivity` | 0.004 | orbit speed | taste |
| `cam_pitch_default` | -6.0 | starting pitch (deg) | slightly down at the bag |
| `fov_base` | 70.0 | resting FOV | — |
| `fov_chase` | 82.0 | FOV when monster is point-blank | the panic kick |
| `chase_range` | 8.0 | monster distance where the FOV kick ramps in | you feel it before you see it |

> Camera **shake is removed** (playtest 2026-07-08: nausea, not horror). The FOV
> kick alone carries proximity dread. If shake ever returns, it must be subtle,
> point-blank only, and probably rotational rather than positional.

---

## Monster (`games/sleepover/Monster.gd`) — senses-only AI
**The monster NEVER reads a player position directly. Its only inputs are
NoiseBus pings and line-of-sight checks.** State machine:
ASLEEP → PATROL → INVESTIGATE → CHASE → LUNGE.

| Constant | Default | What it does | Design rule |
|---|---|---|---|
| `move_speed` | 2.6 | CHASE speed | **> shuffle (2.0), < hop chain (~3.6)** — escapes are stamina-bound |
| `patrol_speed_mult` | 0.45 | PATROL crawl ÷ move_speed | slow lap so you hear it coming |
| `wake_delay` | 40.0 | secs asleep at round start | exploration grace (round loop overrides to lights-out) |
| `hearing_radius` | 14.0 | how far a full-loudness ping reaches | scaled by ping loudness; room-scale, not house-scale |
| `investigate_time` | 8.0 | secs spent searching a ping site | then it gives up and patrols |
| `pings_to_chase` | 3 | pings within `ping_window` = instant CHASE | panic-spamming hops summons it |
| `ping_window` | 10.0 | secs the ping counter remembers | — |
| `chase_memory` | 12.0 | secs of no sight/ping before the trail dies | THE near-miss lever — spec wants ~60% escapes |
| `sight_range` | 8.0 | darkness-adjusted eyes | short on purpose — hearing is the main sense |
| `sight_fov_deg` | 120.0 | vision cone around its heading | it only sees where it's going; walls block it |
| `sight_min_speed` | 0.6 | move slower than this = invisible | **FREEZE to hide** (also: hide volumes, cocooned) |
| `turn_rate` | 2.5 | heading turn speed (rad/s) | lower = more committed = jukeable |
| `lunge_range` | 3.0 | CHASE + LOS inside this = LUNGE | — |
| `lunge_windup` | 0.4 | stationary screech before the burst | your window to break the line |
| `lunge_speed_mult` | 2.3 | burst speed ÷ move_speed | — |
| `lunge_hit_radius` | 1.1 | connect distance = COCOON | — |
| `lunge_cooldown` | 1.6 | recovery after a miss | a missed lunge buys you time |
| `solo_hearing_mult` | 0.6 | hearing ×0.6 (−40%) when `lobby_size == 1` | solo-test modifier so it can't zero in on the only player |
| `solo_chase_memory` | 8.0 | chase give-up drops 12s → 8s when solo | shorter near-miss window so a lone tester can shake it |

> **Solo-testing modifier.** `Monster.set_solo(is_solo)` is called at LIGHTS OUT
> with `is_solo = lobby_size == 1` (from `Main._lobby_size()`). Solo: hearing
> radius ×`solo_hearing_mult`, `chase_memory` = `solo_chase_memory`. Multiplayer
> restores the base values. Base defaults are captured in `Monster._ready()` so the
> multiplier is always applied to the exported value, never a stale one.

> **Detection rules.** PATROL: a lone ping → INVESTIGATE; 3 pings in 10s → CHASE.
> INVESTIGATE: walk to the ping, search 8s; a *second* ping → CHASE. CHASE: hunts
> the LAST KNOWN position (only sight or a fresh ping updates it — going silent
> AND still AND out of sight for 12s loses it). Sight is motion-gated: freeze and
> it looks through you; hide volumes and cocooned bags are unseeable.
>
> Movement is navmesh-routed, collision-free (geometry can't block it), feet
> snapped to the visible treads so it walks stairs. In the round loop it sleeps
> through LIGHTS OUT and wakes when the round begins.

## Menu + lobby (`core/ui/AppRoot.gd`, `core/networking/`)
| Constant | Default | What it does |
|---|---|---|
| `LobbyManager.MAX_PLAYERS` | 8 | lobby capacity |
| `LobbyManager.MIN_TO_START` | 1 | players required before START enables (1 = solo playable) |
| `SteamManager.MAX_PLAYERS` | 8 | Steam lobby size (matches the above) |
| `SteamManager.CODE_CHARS` | A-Z2-9 (no 0/O/1/I) | the 6-char join-code alphabet |

> Flow: **MAIN MENU** (Host / Join-by-code / Settings stub / Quit + overlay
> invite) → **LOBBY** (host-authoritative roster with name + bag swatch, per-player
> ready, all-ready enables the host's START, host-only map/monster/rules stubs,
> Leave) → **START** loads the game on every peer and, once all clients ack their
> scene loaded, the host begins LIGHTS OUT. Late joiners are allowed before START
> and spectate after. Solo (Steam offline) still works: Host → 1-player lobby → START.
> AppRoot only swaps child scenes so the Steam peer + roster persist across states.

## Round loop (`games/sleepover/Main.gd`)
| Constant | Default | What it does |
|---|---|---|
| `lights_out_duration` | 10.0 | ready-up → dark countdown (monster asleep) |
| `round_duration` | 600.0 | 10-min night; survive to SUNRISE win |
| `rescue_range` | 1.9 | how close to unzip a cocooned friend |
| `rescue_time` | 5.0 | hold-E seconds to free them (return at 2 pips) |
| `rescue_zipper_at` | 3.0 | secs into a rescue the LOUD zipper ping fires |
| `zipper_loudness` | 0.9 | that ping's loudness (pulls the monster back) |

> Endings: **ESCAPE** (complete 3 objectives → exits unlock → walk out any exit),
> **SUNRISE** (survive the timer), **LOSS** (everyone cocooned). Host-authoritative
> over Steam; host presses ENTER in lobby/results to advance.
>
> **HUD objective tracker** (top-right): lists the round's 5 objectives by name
> with `[x]`/`[~]`/`[ ]` (done / in progress / not started) and an `ESCAPE X/3`
> counter (round timer is the top-center clock). Two-stage reveal — a code
> objective (Landline/Garage/Breaker) shows only its NAME until a player reads
> its clue, then the action detail (`dial 5 5 2 1`) appears on every HUD (reveal
> is host-owned + synced). It shows WHAT and WHETHER, **never WHERE** — no map,
> markers, or locations; finding and shouting spots over voice is the gameplay.

## Objectives (`games/sleepover/ObjectiveDef.gd` + `Objective.gd`)
Each round the host draws a random **5 of 6**; completing **any 3** arms the escape
PHASE — but **which doors are open depends entirely on which objectives you did**
(Sprint 5). Every objective is a CLUE → ACTION pair with a randomized clue spot;
ACTIONs emit NoiseBus pings.

| Objective | Kind | Action | Opens (exit) | Noise (sound / loudness) |
|---|---|---|---|---|
| The Landline | code 4 | read note → rotary-dial (1.5s/digit, wrong resets) | **FRONT DOOR** | click / 0.8 |
| The Garage Code | code 4 | read birthday → keypad (wrong = loud beep) | **GARAGE** | beep / 0.85 |
| The Breaker | code 3 | read garage diagram → set fuse colours (keys 1-3) in basement | **BASEMENT WINDOW** | clatter / 0.85 |
| The Dog Has The Keys | reach | grab pantry snack → reach the wandering dog | **BACK DOOR** | bark / 0.7 (barks every 4s on its own) |
| The Deadbolt | 2-player | two bodies at the back door, hold E 3s | — (support) | click / 0.5 |
| The Glasses | find | one random player's screen is BLURRED until they find their glasses | — (support) | click / 0.25 |

**Escape-door mapping** (`Main.EXIT_OBJECTIVE`). A door's physical blocker is
hidden only once ITS objective is done; standing in an OPEN exit's zone while the
escape phase is armed = you're out. Four of the six objectives are door-openers;
only **Deadbolt** and **Glasses** are support (count toward the 3, open nothing).
Because a 5-of-6 draw drops just one objective, **any set of 3 completions opens
≥1 door** — every round is winnable, no soft-lock. The BACK DOOR is a new north-wall
exit (gap into the dining room); the basement window is logic-gated (no physical
blocker). HUD tracker names each task's door and lists which exits are OPEN.
> *Design note (needs your call):* the standalone **Deadbolt** objective still
> lives at the kitchen back-door spot but no longer opens a door — the DOG now owns
> the back door per the Sprint 5 brief ("the dog has the keys to the deadbolted
> back door"). If you'd rather Deadbolt open the back door and the Dog be support,
> it's a one-line swap in `EXIT_OBJECTIVE`.

- `Objective.NEAR` = 2.0m interaction reach; `Objective.DIAL_TIME` = 1.5s rotary windup.
- `Objective.DOG_SPEED` = 0.9 m/s — the dog is navmesh-routed (walks through
  doorways, never through walls) and ambles slowly so it's catchable.
- Deadbolt `solve_secs` = 3.0. Glasses blur is a full-screen box-blur post-process
  on only the assigned player; clears on pickup.
- Tuning per-objective solve params lives on the factory methods in `ObjectiveDef.gd`
  (clue pools, action spots, code lengths, `noise_loudness`); exit zones + door
  blockers in `HouseSuburban.EXITS`.
- Known gray-box limitation: the dog runs a deterministic local sim on each peer
  (same path/speed), so its position can drift slightly between machines — fine
  for gray-box, revisit with host-owned sync in the art pass.

---

## Global (`project.godot`)
| Setting | Default | Note |
|---|---|---|
| `physics/3d/default_gravity` | 12.0 | punchier than Earth's 9.8 — snappier hops read better in clips |

---

## Housesitter juice + eye-states (Sprint 4)
The bag's googly eyes carry the character. `core/player/BagEyes.gd` drives pupils
+ eyelids per **mood**, mapped from state in `Player.eye_mood()`:
`COCOONED→SLEEPY`, `TUMBLED→SPIRAL`, `hidden→SHUT`, `stamina<1→DROOP`, else `IDLE`
(with occasional blinks). `Main` layers `ALERT` (wide, darting) on when the
monster is within `chase_range`, and syncs the mood as one int on the bag RPC so
you see your **friends'** eyes go wide too.

The Housesitter's **shush** (`shush_range` 4.0, `shush_cooldown` 3.5) fires when
it corners a survivor mid-chase — "go to sleep." Its lullaby **hum swells** as it
nears the closest survivor (−12→−3 dB over 3–15m).

> Client audio note: creak/shush/hum-swell run in the host's monster
> `_physics_process`; clients get the looping hum + screech via the existing
> relay but not the swell/shush (a known gray-box gap, fine for now).

## Round bookends, cocoon, unzip (Sprint 5)
- **10-second intro bookend.** Players spawn zipped in the living room under the
  standard low third-person chase cam. A **porch light** just outside the front
  door (`Main._porch_light`) flickers erratically through the `lights_out_duration`
  (10s) intro, dimming as it fails, then **dies** the instant the round begins and
  the 10-minute timer starts. No cinematic camera work — one clean beat.
- **Caught → cocoon is an INSTANT hard snap** (no AnimationPlayer, no stinger).
  On the lunge hit `Main._cocoon_local()` kills the chase cam on the same frame
  (`_cocoon_cam = 1` — camera pulled inside the bag at 0.12m), drops the full-screen
  **fabric-dark** overlay, locks WASD (the player's COCOONED state), and starts a
  **heavy breathing loop** (`SoundKit "breath"`) on a runtime **low-pass audio bus**
  (`InBag`, cutoff 600 Hz) so in-bag audio is muffled — proximity voice routes here
  too once VOIP exists. **Hold Q** = instant 180° look-back over the shoulder,
  release snaps straight back. The wiggling body stays visible to others for the
  5-second rescue channel. `cocooned` state syncs over the wire (`_net_cocoon` RPC
  + `FLAG_COCOONED` on the bag-state RPC) — verified caught-on-client in ENet loopback.
- **Unzip friction.** Grabbing a clue/item (note, snack, glasses) means unzipping:
  a **hold-E channel** (`unzip_secs` 1.2s) that broadcasts a **loud NoiseBus ping**
  (`unzip_loudness` 0.85) + a zipper sound the moment the seal breaks — the grab
  isn't committed until the channel completes, so a fumbled unzip still costs the
  time and noise. While the monster is **CHASE**-or-worse it takes `unzip_chase_penalty`
  (+1s) longer and shows a **shaky-hand** panic prompt (text jitter, never camera
  shake). Panels/dial/dog-hand-off/deadbolt stay instant presses. See `Objective.grab_available()`
  + `Main._begin_unzip/_update_unzip`.

## Narrative layer — story through systems (Milestone)
Tone law: **Goosebumps, not Saw** — PG-13, creepy-cute, zero gore. No cutscenes;
the premise (something comes to put you to sleep; sunrise / the porch light are the
tells; get in your bag) is *inferable* from the fragments + behaviour alone.

| Constant | Default | What it does |
|---|---|---|
| `Main.fragment_spawn_min / _max` | 3 / 4 | lore fragments seeded per round (host rolls a count in range) |
| `Main.outro_duration` | 6.0 | closing-bookend length (≤10s), sunrise / all-tucked-in |
| `Monster.close_shush_range` | 5.0 | even NOT chasing, a survivor this close gets a gentle "shhh" |
| `Monster.close_shush_cooldown` | 6.0 | slower cadence for the passing-by shush |

- **Lore fragments** (`Fragment.gd`, content in `games/sleepover/data/lore_fragments.json`,
  loaded by `LoreFragments.gd`). 20 fragments — tapes, polaroids, crayon drawings,
  clippings, a flyer — with **deliberate gaps + contradictions** (the mystery is
  meant to be argued about). Each round the host seeds a random 3–4 at
  `HouseSuburban.fragment_anchors()` (the union of the objective clue-spawn spots),
  so lore-hunting carries the **same risk + traversal** as objectives. Pickup is a
  hold-E **unzip** (the same loud channel as grabbing a clue). Collection is
  **host-authoritative, once per lobby per round** (`_net_request_collect` →
  `_authoritative_collect_fragment` → `_net_fragment_collected`); the whole party's
  Scrapbook is credited (shared discovery). Tapes "play" a procedural tape sound on
  pickup (`SoundKit "tape"`) — **no voice, ever**; the message is the on-screen transcript.
- **The Scrapbook** (`core/save/Scrapbook.gd`, autoload) — persistent meta-progression
  saved to `user://scrapbook.save` and mirrored to **Steam Cloud** (Remote Storage;
  fails soft to local in solo/headless). Fragments fill **5 pages of 4**
  (`LoreFragments.PAGES`); completing a page unlocks a `BagVisual` skin (pages →
  skins 1–5), and filling every page unlocks the two bonus skins (6–7). Opened from
  the main menu **and** the lobby ("SCRAPBOOK / SKINS"); the chosen skin is the one
  you wear (reported into the lobby roster, worn by your bag + shown to others).
- **Housesitter behaviours** — the story is in what it *does*: PATROL lullaby **hum**
  is the signature; **shush** now also fires at close range when it's not even
  chasing (`close_shush_range`) — it isn't here to kill you, it's here to put you to
  sleep; COCOON is the **"tucking in"** (the fabric-dark overlay *fades* up, lullaby
  audible through the bag). It never speaks.
- **Round bookends** (≤10s, skippable after the first view via Space/Enter, tracked
  by `Scrapbook.seen_intro/seen_outro`): **INTRO** = the porch-light flicker-and-die
  during LIGHTS OUT (Sprint 5); **OUTRO SUNRISE** = warm dawn floods in and the
  Housesitter `withdraw()`s; **OUTRO ALL-TUCKED-IN** = the house goes quiet, lullaby
  fades. `Main._start_outro/_update_outro`, overlaid on the results.

## Proximity voice (`core/audio/VoiceManager.gd`, autoload)
Capture is the **Steam voice API** (compression is Steam's; uses the **system
default** input device — the API has no per-device select, so settings has no
misleading dropdown). Push-to-talk **V** by default; "open mic" + "voice enabled"
toggles in settings. Packets ride the same RPC stack as gameplay
(`any_peer, unreliable`); **sender identity comes from the transport**, never the
packet. No Steam (solo / `--enet-*` loopback): `test_tone_mode` streams synthetic
s16 tone packets down the identical path, so transport is provable headlessly.

| Constant | Default | What it does |
|---|---|---|
| `Main.voice_range` | 14.0 | AudioStreamPlayer3D falloff — voice is room-scale-ish, like the hearing radius |
| `VoiceManager.PTT_KEY` | V | push-to-talk |
| `VoiceManager.SPEAK_HOLD` | 0.4 | secs the 🗣 indicator lingers after the last packet |

- Each peer's voice plays from an `AudioStreamPlayer3D` **parented to their ghost
  bag** (mouth height 0.7) — proximity attenuation via the 3D mixer, for free.
- **Cocoon muffle**: a cocooned speaker's player is routed to the `InBag` 600 Hz
  low-pass bus — voice through fabric (flag-edge detected in `_net_bag_state`).
- HUD: "V talk" in the controls line + a green "🗣 name, name" row while peers speak.
- **Design law: the monster NEVER hears voice.** Talking is the co-op glue and must
  always feel safe; hops/zippers are the noise economy, not your friends.
- Verified: selftest group `voice` (rx counting, speak-on/off, unregister-clean,
  2.4k frames pushed headless) + loopback both directions (181 pkts / 427k frames
  each way, zero errors). Real audio/positioning/muffle needs the two-Steam-client
  ear check (FRIEND_SETUP.md).

## Floor distribution (pull players + monster across all 3 floors)
Everything used to cluster on the ground floor. Now:
- **Objective clues** have per-floor pools (Landline/Garage/Breaker each carry
  ground + upstairs + basement candidates in `HouseSuburban`). `Main._host_start_round`
  runs a **spread picker**: each round's 5 clues land ≤2 per floor, span ≥2 floors,
  and always ≥1 upstairs — so clue-hunting drags players up and down. (Final
  *completions* stay ground-heavy by nature; spreading those needs the 2 optional
  objectives — a later content add.)
- **Monster spawn** is dynamic (`MONSTER_SPAWN_CANDIDATES`): at LIGHTS OUT the host
  picks the candidate farthest from the players + the round's clue/action anchors,
  excluding any within `spawn_stair_clearance` (3.0) of a staircase (`STAIR_PLAN_POINTS`).
  So the action floor starts monster-free and it's never camped on a chokepoint.
- **Patrol dwell cap** (`Monster.patrol_floor_dwell`, 20s): the monster can't spend
  more than N secs on one floor while patrolling — it routes to the nearest waypoint
  on a different floor, so it circulates and is encountered everywhere.
- `HouseSuburban.floor_of(y)` classifies a height: basement `y<-1`, ground `-1..2`,
  upstairs `y≥2` (attic counts as up).

## Basement (the dread floor)
**One stacked stairwell.** The basement flight runs *directly beneath* the up-flight
in the same shaft (`x−1..0.5, z0..5`), descending the opposite way, so the two stay a
constant **3 m apart**. The shaft is walled off from the hall's walking lane
(`x0.5..2`), **open at its north end** (that's the up-stairs mouth) and closed at its
south end by a wall carrying **the BASEMENT DOOR**, right beside the front entry —
you go through a *door*, never a hole in the floor.

The basement itself (`y=-3`, `x−8..2, z−6..6` ≈ 14×17 m) is a **gauntlet, not a
corridor**. Stairs land north-centre; the **WALKOUT** escape is the far **SW**
(`x=-8` gap at `z4.5`) while the **Breaker** — the objective that *unlocks* that
walkout — sits in a dead-end pocket in the far **NE** (`x0..2, z−6..−3`). Two
staggered chokepoints in between: divider `x=-3` (gap at `z1`) is the only way west,
then divider `z=2` (gap at `x=-7`) is the only way into the SW. So escaping means
fetching the thing that opens the door and then crossing the whole pitch-black floor
to reach it.

Intentionally the darkest floor: lamps below ground use `BASEMENT_LIGHT_ENERGY = 0.18`
(vs `ROOM_LIGHT_ENERGY = 0.7`) with a cold tint. Descent = commit + lose the upstairs
escapes.

> **Yard-slab rule (do not break this).** The yard safety-slab (`top −0.05`) must
> always carry a hole matching the basement footprint. It spans the whole map
> otherwise, and a player stepping into the stairwell lands on *it* at y≈0 instead of
> descending — the silent bug that made the basement unreachable on foot for several
> builds. The basement floor is the safety net inside that hole.
>
> Regression cover: `Main._probe_basement_walkable` raycasts **both** flights in the
> shaft (rays must start *below* the upper flight or they just hit it), and
> `_audit_anchors_on_floor` verifies every spawn/objective/clue anchor stands on solid
> floor — that one caught a clue spawning inside a staircase.

## House scale
`HouseSuburban.S = 1.4` — the whole floor plan is scaled 1.4x at build time
(playtest 2026-07-09: rooms too small, corridors too tight, chases resolved
too fast). Heights stay 1:1, so the scale also made stairs shallower (rise 0.3,
run 0.7) and doors wider (~1.5m). Raise/lower S to resize the entire house.

## Stairs & verbs
Every staircase has an invisible ramp collider (layer 2, players only) so bags
can SHUFFLE up and down stairs — slowly, thanks to the slope fighting gravity.
Hopping remains the fast way up; hopping DOWN at speed still tumble-chains.
The monster ignores the ramps entirely (rays + navmesh masked to layer 1) and
keeps walking the real treads. Chases continue across floors either way.

## The speed ladder (keep this ordering true while tuning!)
```
shuffle_speed (2.0)  <  monster.move_speed (2.6)  <  hop-chain pace (~3.6 bursts)
```
The hop-chain-vs-monster gap is deliberately THIN: you pull away slowly while
pips last, and the tank only buys 5 hops. Escape = spend everything + a corner.

Tumble behavior: on any tumble the bag bleeds 65% of its speed, spin is capped,
and heavy damping switches on until you're upright — it *falls over* in place
rather than ragdolling across the map. (Damping resets to 0 on recovery.)
The monster must catch shufflers and lose to full-stamina hop chains — so every
chase is exactly as long as your pips. When the tank hits 0 mid-chase, the
choice is "shuffle and be caught" or "hop and face-plant". That dilemma IS the
game; if a tuning change removes it, revert.

## Noise ladder (what the monster hears, loudest first)
```
hop landing (1.0)  ≈  zipper/rescue (0.9)  >  garage beep (0.85) ≈ breaker clatter (0.85)
   >  tumble crash (0.8) ≈ phone dial (0.8)  >  dog bark (0.7)  >  deadbolt (0.5)
   >  leaving a hide spot (0.3)  >  glasses grab (0.25)  >  shuffle (0.0 — silent)
```
Every ping carries a loudness that scales the effective hearing radius, so a
zipper across the house pulls the monster off you, and a quiet rustle leaving a
closet barely registers. Constants: `land_loudness`/`tumble_loudness` (Player),
`zipper_loudness` (Main), objective `noise_loudness` (ObjectiveDef factories),
hide-exit ping hardcoded 0.3 in Main.
> Mic-as-noise was removed (2026-07-08 playtest decision). An archived copy of
> `MicMonitor.gd` exists outside the project if it's ever revisited.
