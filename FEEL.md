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

### Hop & Stamina — the panic economy
| Constant | Default | What it does | If it feels wrong |
|---|---|---|---|
| `hop_speed` | 3.6 | forward burst speed of one hop | was 4.0 — chains outran the monster too easily |
| `hop_up_speed` | 4.6 | upward speed per hop (independent knob) | jump height = up²/(2·gravity) ≈ 0.88m — 3.6 still snagged on stair risers |
| `stamina_max` | 3.0 | hop pips | was 5 — playtest: 3 makes every hop a real decision |
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

## Monster (`games/sleepover/Monster.gd`) — Patrol → Investigate → Chase
| Constant | Default | What it does | Design rule |
|---|---|---|---|
| `move_speed` | 2.6 | chase speed | **faster than shuffle, slower than a hop chain** — 3.3 → 3.0 → 2.6 via playtests |
| `hearing_radius` | 40.0 | how far a noise ping reaches it | shrink to make the house feel bigger |
| `chase_trigger_range` | 6.0 | ping this close to it = instant CHASE | distant noise only gets investigated |
| `proximity_sense` | 3.5 | it just *knows* you're there this close | escalates an investigate into a chase |
| `chase_memory` | 6.0 | secs of no contact before it loses you | THE near-miss lever — spec wants ~60% of chases to end in escape; raise = deadlier |
| `turn_rate` | 2.5 | how fast it changes direction | lower = more committed = jukeable; raise if dodging feels free |
| `track_interval` | 0.4 | secs between position snapshots in CHASE | it aims where you WERE — raise to make sidesteps stronger |
| `patrol_span` | 6.0 | idle wander distance | cosmetic for the kill test |

> Chase rules: once it's locked on it tracks your LIVE position — going silent
> does not break a chase. Any ping (or getting within `proximity_sense`)
> refreshes its memory; it only gives up after `chase_memory` secs of zero
> contact, then checks your last known position before returning to patrol.
>
> Movement is navmesh-routed (baked from the gray-box at startup) and the body
> has NO world collision — geometry can never block or snag it. It walks the
> path with its feet snapped to the surface underfoot, so it climbs stairs
> tread by tread. Spawns in the DINING ROOM and wanders there until it hears you.

---

## Global (`project.godot`)
| Setting | Default | Note |
|---|---|---|
| `physics/3d/default_gravity` | 12.0 | punchier than Earth's 9.8 — snappier hops read better in clips |

---

## The speed ladder (keep this ordering true while tuning!)
```
shuffle_speed (2.0)  <  monster.move_speed (2.6)  <  hop-chain pace (~3.6 bursts)
```
The hop-chain-vs-monster gap is deliberately THIN: you pull away slowly while
pips last, and the tank only buys 3 hops. Escape = spend everything + a corner.

Tumble behavior: on any tumble the bag bleeds 65% of its speed, spin is capped,
and heavy damping switches on until you're upright — it *falls over* in place
rather than ragdolling across the map. (Damping resets to 0 on recovery.)
The monster must catch shufflers and lose to full-stamina hop chains — so every
chase is exactly as long as your pips. When the tank hits 0 mid-chase, the
choice is "shuffle and be caught" or "hop and face-plant". That dilemma IS the
game; if a tuning change removes it, revert.

## Noise ladder (what the monster hears, loudest first)
```
hop landing (1.0)  >  tumble crash (0.8)  >  shuffle (0.0 — silent)
```
> Mic-as-noise was removed (2026-07-08 playtest decision). An archived copy of
> `MicMonitor.gd` exists outside the project if it's ever revisited.
