# SLEEPOVER — Master Build & Play Document
### The full Claude Code sprint sequence, objective catalog, house layout, and how a round truly plays
*Third companion doc. sleepover-build-spec.md = mechanics/design intent. sleepover-launch-plan.md = narrative/launch/live-ops. THIS doc = the build order Claude Code follows and the moment-to-moment gameplay.*

---

## 0. WHERE THE "MAKE IT A GAME" PROMPT FITS

That prompt is **Sprint 1 of 6**. It converts the chase demo into one playable round with ONE objective (the Landline), the AI monster, hiding, and the cocoon/rescue loop. It is the foundation everything else stacks on — deliberately narrow. Do not add to it; ship it, then move down this list.

| Sprint | Outcome | Maps to launch-plan phase |
|---|---|---|
| **0. Menu + lobby** | Main menu, functional Steam lobby, join code, ready-up → round start | Phase 1 (wks 2–3) |
| **1. Make it a game** | One playable round, 1 objective, AI monster, hide + rescue, 3 endings | Phase 2 (wks 4–5) |
| **2. Full objective system** | All 6–8 objectives + 3 escape routes, data-driven | Phase 2→3 (wk 5–6) |
| **3. Add the basement** | Extend test house with a basement level (the dread floor) | Phase 3 (wk 6) |
| **4. Player-monster + juice** | Secret monster assignment, audio stack, camera juice, eye-states | Phase 4 (wks 8–9) |
| **5. Narrative layer** | Scrapbook, lore fragments, lullaby/shush behaviors, intro/outro | Phase 3→4 (wk 7–9) |
| **6. Content framework** | Monster #2 + House Rules mutators + map-swap architecture | Phase 7 (post-launch) |

Each sprint below is written to be handed to Claude Code as its own milestone prompt. Feed ONE at a time.

**Run order note:** Sprint 0 (menu + lobby) comes FIRST — you need a way to get two players into a round before you can test the round itself. It's infrastructure for Sprint 1, not a later polish task. The *pretty* menu (art, real settings styling, polished lobby room) is Phase 5 polish; Sprint 0 is the gray-box functional version only.

---

## 0.5 SPRINT 0 — MAIN MENU + FUNCTIONAL LOBBY

Gray-box, no art. The minimum that lets friends get in and start a round.

### What it includes
- **Main menu:** Host Game, Join Game (Steam invite + visible 6-char join code), Settings (stub: volume, sensitivity, mic device, rebinds), Quit.
- **Lobby screen (host-authoritative):** synced player list (Steam name + colored bag swatch), per-player ready toggle, host START button (enabled when all ready), leave/disconnect handling, START → LIGHTS OUT for all.
- **Stubbed host controls** (visible dropdowns, wired later): map select (Sprint 3), monster mode AI/secret-player (Sprint 4), House Rules (Sprint 6). Building the UI slots now means later sprints plug in instead of forcing a lobby redesign.

### Two decisions baked in
- **Visible join code is not optional** — Steam overlay invites cover friends, but streamers need a code to paste in chat for viewers. A marketing feature disguised as UI; it ships from day one.
- **min-to-start = 1** (in FEEL.md) so you can solo-test the full round loop without dragging a friend in every time. Flip to 2 for real playtests.

### Claude Code prompt frame for Sprint 0
```
MILESTONE: Minimal main menu + functional lobby (gray-box, no art).

MAIN MENU (single screen):
- HOST GAME → creates a Steam lobby, goes to lobby screen as host
- JOIN GAME → accepts Steam invite / join-code entry, goes to lobby as client
- SETTINGS → volume sliders, mouse sensitivity, mic device select, key rebinds
  (stub screen is fine, wire real values later)
- QUIT
- Steam invite works via overlay AND a visible 6-char join code.

LOBBY SCREEN (host-authoritative):
- Player list: each connected player (Steam name + a colored bag swatch)
- Ready toggle per player; all-ready enables the host's START button
- Host-only controls (stub now, wire later): map select, monster mode
  (AI / secret-player), House Rules dropdown
- Leave button; handle a player disconnecting from lobby gracefully
- START → LIGHTS OUT for all clients

REQUIREMENTS:
- Everything syncs over GodotSteam (join/leave/ready reflected on all screens)
- Lobby state is host-owned; late joiners allowed before START, spectate after
- Constants (max players = 8, min to start = 1) in FEEL.md

ACCEPTANCE: two Steam clients — one hosts, one joins via code, both ready up,
host starts, both land in LIGHTS OUT together. A client leaving updates the
host's list.
```

---

## 1. SPRINT 2 — FULL OBJECTIVE SYSTEM

Sprint 1 built the ObjectiveDef framework and one objective. Sprint 2 fills the catalog. **All are two-step (CLUE → ACTION), all require unzipping, all spawn randomized so no two rounds match.** A round activates a random 5 of these; completing any 3 arms the escape routes.

### The objective catalog
1. **The Landline** (built in Sprint 1) — find number → dial rotary phone digit-by-digit.
2. **The Breaker** — find the fuse diagram (garage/junk drawer) → set fuse colors + order in the basement box. Solving it turns house lights ON (helps everyone see, but the monster now sees too).
3. **The Dog Has The Keys** — Buster wanders with keys jingling on his collar → lure with a pantry snack. Hopping near him makes him bark (noise ping you don't control). A *moving* objective.
4. **The Deadbolt** — back door's top bolt is too high → one player hop-boosts off another's shoulders (both unzipped, both helpless).
5. **The Garage Code** — keypad needs a family birthday → find it on a banner/cake photo/calendar. Wrong entries beep loudly.
6. **The Glasses** (comedy wildcard, 1 random player/round) — that player's screen is blurred until they find their glasses; teammates must describe what they're seeing.
7. **The Fuse Box Jr. / Nightlight Circuit** (optional 7th for big lobbies) — restore power to the upstairs hall so hiding spots are visible.
8. **The Window Latch** (optional 8th) — pry a painted-shut window for the basement escape route.

### Escape routes (any 3 objectives arms these)
- **Front door** — needs the Landline call complete (help arrives, unlocks it).
- **Garage** — needs the Garage Code.
- **Basement walkout / window** — needs the Window Latch or a box-stacking physics climb.

Multiple exits = live strategy arguments = the gameplay. Design rule: **every solution must be explainable over voice by a panicking person. If it needs a wiki, cut it.**

### Claude Code prompt frame for Sprint 2
```
MILESTONE: Full objective catalog on the existing ObjectiveDef framework.
- Implement objectives 2–6 as data-driven ObjectiveDefs (clue spawn pool +
  action node + completion signal), matching the Landline's pattern.
- RoundManager picks a random 5 per round; completing any 3 sets
  escape_armed = true and unlocks the mapped exits.
- Each objective's ACTION emits appropriate NoiseEvents (barks, beeps,
  fuse-box clatter) into the existing bus.
- The Glasses: post-process blur on one random player until pickup.
- Add per-objective constants to FEEL.md (solve times, noise radii).
- Gray-box props only. No art.

HUD OBJECTIVE TRACKER (corner of screen, minimal):
- Lists this round's active objectives by NAME with a state each:
  not started / in progress / done (checkbox or ✓).
- Shows a "X of 3 needed to escape" counter and the round timer.
- TWO-STAGE REVEAL: an objective shows only its name until a player finds its
  clue; THEN the HUD reveals the action detail (e.g. "Landline" becomes
  "Landline — dial 5-5-2-1" only after someone reads the note). Found state
  syncs to all players so whoever does the action doesn't have to memorize it.
- NEVER show LOCATIONS. No map, no markers, no "in the garage" hints. The HUD
  tracks WHAT and WHETHER, never WHERE — finding and shouting locations over
  voice is the gameplay.
- Tracker state is host-owned and synced to all clients.

ACCEPTANCE: 5 random objectives spawn in different spots each round; a full
lobby can split up, solve 3, and escape via 2 different exits in one session.
The HUD shows objective names + states, reveals action detail only after a
clue is found, shows no locations, and stays synced across host + client.
```

---

## 2. SPRINT 3 — ADD THE BASEMENT (extend the test house)

**Decision:** the current test house IS the shippable launch map. No real-house dependency — we build on what exists. The one addition it needs is a **basement**, because descent is the game's strongest suspense tool (see below). This is a gray-box level-extension task, not a from-scratch map, and needs no sketch.

### Why a basement specifically (not just another dark room)
Descent is uniquely scary in a way a same-floor dark room can't match: going DOWN means committing, losing the escape routes above you, and turning the single staircase into a chokepoint the monster can pin. Vertical dread is real. This is worth a small build task to get.

### What to add to the test house
- **One staircase down** from the main floor to the basement (a second vertical chokepoint alongside the existing main↔upstairs stairs).
- **Rec room:** open basement space, darkest area in the game.
- **Utility/laundry pocket:** a deliberate dead-end that houses **the Breaker objective** — players WANT to go down for it, and the game makes them dread it.
- **Walkout exit:** a basement door/window = the second escape route (keeps "multiple exits = strategy argument" gameplay intact).

### How the three floors now play
- **Main floor = objective hub + circulation loop.** Landline, Dog/keys, Garage Code. Chases resolve here. Front/back door escapes.
- **Upstairs = hiding + lore.** Closets and under-beds (hiding volumes), most Scrapbook fragments. The main↔upstairs stairs are a chokepoint players gamble on.
- **Basement = the dread floor.** Darkest, houses the Breaker, dead-end utility pocket, walkout escape. The descent is the suspense.

### Circulation rules (apply to the whole house)
- Widen main hallways ~20% for the low camera.
- Guarantee at least one full-loop chase path on the main floor (no instant dead-end).
- Keep 2–3 *intentional* dead ends (basement utility, a far bedroom) as high-risk hiding pockets.
- Two staircases (main↔upstairs, main↔basement) are the core vertical decisions — do NOT add more; chokepoints are the point.

### Claude Code prompt frame for Sprint 3
```
MILESTONE: Add a basement level to the existing test house. Gray-box only.
- Add one staircase down from the main floor to a new basement.
- Basement layout: open rec room (darkest lighting in the game) + a dead-end
  utility/laundry pocket + a walkout door/window escape exit.
- Extend NavigationRegion3D to cover the basement; re-bake navmesh.
- Extend the monster patrol waypoint loop to include the basement.
- Place the Breaker objective anchor in the utility pocket; register the
  walkout as a third escape-route exit.
- Verify: monster can path down and back up; a chase can still run a full
  main-floor loop; every objective anchor + hiding spot reachable by navmesh.
- Basement lighting constants + any new room-scale values in FEEL.md.
ACCEPTANCE: players can descend to the basement, solve the Breaker in the dark,
and escape via the walkout; the monster patrols and chases across all 3 floors
without navmesh gaps.
```

---

## 3. SPRINT 4 — PLAYER-MONSTER + JUICE

The AI monster (Sprint 1) is the balance baseline. Now add the headline mode and the feel.

- **Secret assignment:** at LIGHTS OUT, one player (4+ lobbies) is secretly the Housesitter. Their empty bag stays in the living room; they respawn elsewhere as the monster. Small lobbies (2–3) keep the AI.
- **Monster kit:** the AI's exact ability budget (senses, speed, lunge, cocoon), now player-driven, + noise-ripple vision overlay (sees NoiseEvents through walls, not player positions/voices).
- **Eye-state system** (the character soul): survivor eyes react — wide/darting in chase, squeezed shut hiding, spirals in tumble, drooping at empty stamina. Procedural, script-driven.
- **Audio stack:** patrol hum, proximity creaks, chase sting, proximity heartbeat, lunge screech, the signature zipper.
- **Camera juice:** FOV kick + shake on chase enter, first-person cocoon snap, level camera through tumbles.

---

## 4. SPRINT 5 — NARRATIVE LAYER

Story is delivered as systems, not cutscenes (see launch-plan Part 1).

- **The Scrapbook:** meta-progression menu; collected fragments fill pages, completion unlocks cosmetics + deeper lore.
- **Lore fragments:** answering-machine tapes, polaroids, crayon drawings, newspaper clippings seeded at clue-spawn anchors (lore-hunting = risk-taking). Write the first 20.
- **Housesitter behaviors that tell the story:** lullaby hum on patrol, shush animation at close range, "tucking in" framing of the cocoon. It doesn't kill — it puts you to sleep. Tone: Goosebumps, not Saw.
- **Round bookends:** 10-second intro (kids zipping in, lights out, porch light flickers) and outro (sunrise = it leaves / all-cocooned = tucked in). No long cutscenes.

---

## 5. SPRINT 6 — CONTENT FRAMEWORK (post-launch longevity)

- **Monster #2 — The Tooth Fairy:** hunts MOTION, freezes when a survivor looks at it. Inverts the whole game (staring contests, walking backward). Ships as the Halloween drop via the shared monster chassis (swappable sense profile + quirk + tell).
- **House Rules mutators:** config-file global modifiers, one live/week (Blackout, Sugar High, Two Sitters, Slumber Party). Near-zero-cost content, self-writing calendar.
- **Map-swap architecture:** confirm maps load as data so "The Manor on Maple Street" (the big-lobby map) drops post-launch without engine changes.

---

## 6. HOW A ROUND TRULY PLAYS (the anatomy)

This is the target experience once Sprints 1–5 are in. 4–6 players, ~10-minute round.

**Lights out (0:00).** Six friends zip into bags in the living room. Porch light flickers and dies. If 4+, one bag goes limp — that player is now the Housesitter, somewhere in the house. Nobody knows who. A lullaby hums faintly from... upstairs? The basement? You can't tell yet.

**The scatter (0:00–2:00).** The group argues over open voice: split up or stick together? Objectives revealed this round — Landline, Breaker, Dog, Garage Code, Glasses. Someone shuffles toward the kitchen to find the phone number. Someone else needs the fuse diagram and dreads the basement. The blurred-glasses player bumps a lamp — *noise ping* — and everyone freezes.

**First contact (2:00–4:00).** The hum gets louder. Floorboards creak one room over. The player at the fridge has the number — "it's 5-5-2-1, I'm dialing" — and starts the rotary phone: slow, loud clicks, one digit at a time. The clicks are noise pings. The Housesitter, investigating a bark from the dog two rooms away, hears the phone and pivots. "SOMEONE COME WATCH THE HALL." Too late — the monster rounds the corner.

**The chase (4:00–5:30).** The dialer bolts, full stamina, hopping — fast but loud, every landing a ping. They have maybe five hops before the tank's dry. Panic sets in, they spam the last hops, mistime a staircase, and **tumble** — sprawled, mashing keys to get up. The lullaby is right on top of them. Lunge screech. Cocooned. Their screen goes fabric-dark; their voice muffles to nothing. A wiggling cocoon sits at the top of the stairs.

**The rescue gamble (5:30–7:00).** "They got Jordan, top of the stairs, someone HELP." Two players weigh it: the monster's still up there. One creates a distraction — knocks a prop across the house, pulling the Housesitter to investigate — while the other shuffles up, holds E for five agonizing seconds (the zipper screams a noise ping at 3s), and drags Jordan free. Jordan's back at 2 pips, barely mobile.

**The push (7:00–9:00).** Three objectives down — escape is armed. Front door's unlocked from the Landline call. But the group's scattered and the monster's between them and the door. The blurred-glasses player is being talked through the hallway blind — "left, LEFT, okay hop now" — pure comedy over pure tension.

**The ending (9:00–10:00).** Two make the front door and escape. One's cocooned. One's hiding under a bed upstairs, heartbeat pounding as the Housesitter searches the room, watching its feet through the bed-skirt gap. Sunrise hits at 10:00 — the monster has to leave. The hider survives. Results screen: 2 escaped, 1 survived, 1 tucked in. Awards: "Loudest Zipper — Jordan," "Most Falls — Jordan," "Clutch Rescue — Sam." Everyone's talking over each other. One keypress: run it back.

**Why it works:** every 90 seconds manufactures a clip (the tumble, the blind hallway, the rescue distraction, the under-bed survival), the panic is self-inflicted by the stamina economy, and the three endings mean no round resolves the same way. That's the loop that doesn't die in a week.

---

## 7. TIMELINE (sprints → calendar)

| Weeks | Sprint(s) | Milestone |
|---|---|---|
| Now–2 | finish multiplayer sync → Sprint 0 → Sprint 1 | Lobby works, then first complete playable round |
| 3–4 | Sprint 2 | Full objective catalog live |
| 5–6 | Sprint 3 (basement) + art pass 1 | 3-floor test house, Steam page live, wishlists start |
| 7–8 | Sprint 4 | Player-monster, eye-states, full juice; playtests + TikTok pipeline |
| 8–9 | Sprint 5 | Narrative, Scrapbook, bookends |
| 10–11 | hardening + beta | Netcode, settings, Steam build pipeline, closed beta |
| 11–12 | launch ops | Trailer, streamer keys, wishlist gate check, LAUNCH (early Oct) |
| Post | Sprint 6 | Tooth Fairy + House Rules (Halloween wave), then Manor map |

Critical path is unchanged and singular: **multiplayer sync → Sprint 1.** Everything in this document stacks on two bags in one hallway with a monster that hunts noise. Ship that, and this doc becomes a conveyor belt.
