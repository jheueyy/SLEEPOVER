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

> **Detection rules.** PATROL: a lone ping → INVESTIGATE; 3 pings in 10s → CHASE.
> INVESTIGATE: walk to the ping, search 8s; a *second* ping → CHASE. CHASE: hunts
> the LAST KNOWN position (only sight or a fresh ping updates it — going silent
> AND still AND out of sight for 12s loses it). Sight is motion-gated: freeze and
> it looks through you; hide volumes and cocooned bags are unseeable.
>
> Movement is navmesh-routed, collision-free (geometry can't block it), feet
> snapped to the visible treads so it walks stairs. In the round loop it sleeps
> through LIGHTS OUT and wakes when the round begins.

## Round loop (`games/sleepover/Main.gd`)
| Constant | Default | What it does |
|---|---|---|
| `lights_out_duration` | 10.0 | ready-up → dark countdown (monster asleep) |
| `round_duration` | 600.0 | 10-min night; survive to SUNRISE win |
| `rescue_range` | 1.9 | how close to unzip a cocooned friend |
| `rescue_time` | 5.0 | hold-E seconds to free them (return at 2 pips) |
| `rescue_zipper_at` | 3.0 | secs into a rescue the LOUD zipper ping fires |
| `zipper_loudness` | 0.9 | that ping's loudness (pulls the monster back) |
| `dial_time` | 1.5 | secs per rotary digit (each = loud click ping) |
| `dial_loudness` | 0.8 | the dial-click ping loudness |

> Endings: **ESCAPE** (dial the landline number → front door unlocks → walk out),
> **SUNRISE** (survive the timer), **LOSS** (everyone cocooned). Host-authoritative
> over Steam; host presses ENTER in lobby/results to advance.

---

## Global (`project.godot`)
| Setting | Default | Note |
|---|---|---|
| `physics/3d/default_gravity` | 12.0 | punchier than Earth's 9.8 — snappier hops read better in clips |

---

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
hop landing (1.0)  ≈  zipper/rescue (0.9)  >  tumble crash (0.8)  ≈  phone dial (0.8)
   >  leaving a hide spot (0.3)  >  shuffle (0.0 — silent)
```
Every ping carries a loudness that scales the effective hearing radius, so a
zipper across the house pulls the monster off you, and a quiet rustle leaving a
closet barely registers. Constants: `land_loudness`/`tumble_loudness` (Player),
`zipper_loudness`/`dial_loudness` (Main), hide-exit ping hardcoded 0.3 in Main.
> Mic-as-noise was removed (2026-07-08 playtest decision). An archived copy of
> `MicMonitor.gd` exists outside the project if it's ever revisited.
