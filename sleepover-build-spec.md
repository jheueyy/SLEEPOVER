# SLEEPOVER — Build Spec & Roadmap
### (Séance noted as a possible future fast-follow — Sleepover is the sole build focus)

**Studio model:** Solo dev + Claude Code. Godot 4.x, GDScript, GodotSteam P2P (no servers).
**Target:** Steam, $5.99, online co-op — 4–6 players recommended, 2–8 supported (2–3 use the AI monster; 4+ unlock the secret player-monster; 8 via the Slumber Party mode). Launch window: early October 2026.
**Design north star:** One instantly-legible constraint (you are in a sleeping bag) that generates horror and comedy simultaneously. Every mechanic must survive the question: "does this make the clip funnier or scarier?"

---

## PART 1 — HouseKit: The Shared Foundation

Sleepover is the sole build focus. Systems are still built game-agnostically where it's free to do so, because a future fast-follow (Séance — see Part 4) could reuse the foundation. Do NOT add Séance work to any Sleepover sprint; this is architectural hygiene only, not a parallel build.

### 1.1 Project structure
```
/core
  /networking      # GodotSteam lobby, host-authoritative sync
  /player          # Base player controller, camera, interaction
  /interaction     # Grab/use/door/drawer system, physics props
  /audio           # Proximity voice (Steam Voice), SFX bus, occlusion
  /ui              # Lobby, HUD framework, settings, cosmetic menus
/games
  /sleepover       # Game 1 module
  /seance          # Game 2 module (later)
/maps
  /house_suburban  # Shared: two-story suburban house (both games use it)
/assets            # Kenney/KayKit/Synty packs, Mixamo anims
```

### 1.2 Networking model
- **GodotSteam** plugin. Steam lobby (invite via friends list, no room codes needed, but show a join code anyway for streamers).
- **Host-authoritative:** host simulates monster AI, physics state, and game logic; clients send input, receive state. At up to 8 players in a house-sized map this is trivial bandwidth.
- Interpolation on remote players (buffer ~100ms). Physics props: host-owned, clients see replicated transforms.
- Voice: Steam Voice with **proximity attenuation** — friends fade with distance and muffle through walls/cocoons. Social comedy layer only: the monster does NOT hear player mics. Ship push-to-talk AND open-mic modes.

### 1.3 The house map (shared asset)
- Two-story suburban home + basement + attic. ~14 rooms, 2 staircases, 1 laundry chute (comedy traversal for sleeping bags; ghost shortcut in Séance).
- Built from Synty or KayKit modular interior packs. Stylized low-poly, NOT realistic — reads better in clips, cheaper to light, hides jank.
- Lighting: baked ambient + real-time flashlight/moonlight. Darkness is a mechanic in both games.

### 1.4 Interaction system
- Single interact key: context-sensitive (open door, hide under bed, grab prop, help teammate).
- Physics props tagged `knockable` (Séance reuses these) and `noisy` (Sleepover monster hears them).

---

## PART 2 — WEEK 1 KILL TEST — ✅ COMPLETE (except multiplayer)

Locomotion, stamina, tumble, camera, and the noise-hunting cube are built and optimized in the repo. **Remaining item: two-player GodotSteam sync** — still the gate for everything in Part 3. Original pass/fail criteria met; feel constants live in FEEL.md.

---

## PART 3 — SLEEPOVER: Full Design

### 3.1 Premise & objective
It's a sleepover. Everyone's zipped into sleeping bags in the living room when something in the house wakes up. You never leave the bag — the bag is the game.

**Survivors win by either path:** (a) **ESCAPE** — complete any 3 of the round's 5 active tasks, then exit through an unlocked door; or (b) **SURVIVE TO SUNRISE** — outlast the 10-minute round timer. Two win paths deliberately split group strategy live (hiders vs. objective-pushers arguing over open mic IS the gameplay). **Monster wins** by cocooning every survivor first.

### 3.2 Locomotion (IMPLEMENTED — repo is source of truth)
Movement (WASD shuffle, stamina-limited spacebar hops, tumble state, unzip channel) is built and tuned in Claude Code. **All speeds, pip counts, regen rates, and physics constants live in the repo/FEEL.md — this doc no longer specs them.**

Design intent that must survive any retune:
- Shuffle = slow + quiet + regen; hops = fast + loud + finite; running dry mid-chase = tumble. The stamina economy IS the panic engine.
- Stairs punish low-stamina hopping (tumble chains = the money clip) and make shuffling feel agonizing when chased.
- The unzip mechanic stays the tension dial: everything useful requires hands, hands require noise and vulnerability.

### 3.3 Pickups & tools (spawns randomized; ALL use requires unzipping — defense always costs vulnerability)

**Go faster (loud or risky by design):**
- **Sugar rush** (candy bowl / energy drink): temporary shuffle-speed and max-stamina boost (values in repo) — but your character giggles uncontrollably (audible noise ping)
- **Skateboard:** flop your bag onto it; fastest movement in the game, zero brakes, rumbles like thunder on hardwood
- **Banister slide & laundry chute:** fixed map shortcuts, fast, fun, and noisy

**Fight back (the monster can't be killed — you escape it or outlast it):**
- **Disposable camera:** flash stuns the monster 3s; audible wind-up whine telegraphs it
- **Wind-up alarm clock:** place or lob it; rings after 10s — a throwable noise decoy
- **Nightlights:** small glow auras the monster won't enter; it can unplug them (10s animation) — breathing room, not bunkers
- **Door slam:** any unzipped player slams a door; monster bashes through in ~2s

### 3.4 The monster ("The Housesitter" — working name)

**PLAYER-CONTROLLED, randomly assigned, secret until first scare (headline mode, 4+ player lobbies):**
- At lights-out, one player is secretly chosen: they "fall asleep," their empty bag stays visibly in the living room, and they respawn as the monster elsewhere in the house. The mid-round realization — "whose bag is that... WHERE'S TYLER" — is the game's best clip.
- Monster kit: fast movement (tuned against a full-stamina hop chain), dark-adapted vision, sees in-game noise (hop thumps, tumbles, zippers, knocked props) as visible ripples through walls, unplugs nightlights, bashes doors, cocoons a caught survivor via 3s channel.
- Monster objective: cocoon all survivors before escape or sunrise. Monster gets its own recap awards ("Rudest Awakening").

**AI monster (build FIRST, ships as the 2–3 player fallback):**
- Required for small lobbies and solo practice, and it's the balance baseline the player-monster's ability budget is tuned against. All behavior below defines that baseline.
- Hunts by **noise and light**, not sight cones: hop landings, tumbles, zippers, knocked props, and flashlights all generate noise/light "pings" the AI investigates.
- **The mic is NOT a mechanic** (deliberate cut — the genre has worn it out). Panic comes from the stamina economy instead: the monster hunts the noise your BODY makes, so terror becomes movement discipline — shuffle silently or gamble pips.
- Patrol → Investigate → Chase state machine. During Chase, it's faster than shuffling but slightly slower than a hop chain — meaning escapes are STAMINA-BOUND: you can outrun it exactly as long as your pips last. Every chase is a countdown the player can feel.

**Chase panic engineering (the freak-out is designed, not hoped for):**
- **You hear it before you see it:** floorboard creaks and breathing directionally audible 10–12m out. Dread phase before the chase phase.
- **Escalating audio stack during Chase:** heartbeat-in-the-bag intensifies, high-string sting layers in, friends' voices slightly muffle — the mix physically stresses players.
- **The lunge:** at 3m the monster does a short screech-and-burst. Purpose: force the panic hop-spam that drains stamina and causes the tumble. This is the clip generator.
- **Near-miss tuning:** chases should END in escape ~60% of the time by design (monster gives up after 12s out of ping range). Panic that usually resolves = players immediately want it again; panic that usually kills = players quit.
- **Panic fumble, one only:** while in Chase state, unzip takes 1s longer with shaky-hand animation. Do NOT degrade movement controls — trembling hands are scary, unresponsive controls are just annoying.
- **Doors as drama:** an unzipped player can slam a door behind the group; monster bashes through in 2s. Buys time, costs a zipper. Every horror movie hallway moment, playable.
- Catches you → you're **cocooned**: zipped fully inside, screen goes fabric-dark, you can only yell for help over muffled proximity voice. Friends must shuffle to you and unzip you (5s, loud). Fully cocooned team = round loss.
- One monster at launch; variant behaviors (hunts light instead of sound; freezes when watched) are post-launch content drops.

### 3.5 Objectives (per round, randomized from a larger pool — see master-build catalog)
Escape requires 3 of 5 randomly-placed tasks, all designed to force unzipping in bad places:
1. Find the house keys (random drawer/couch cushion/dog bowl)
2. Flip the basement breaker (darkest room in the house)
3. Retrieve a phone from upstairs and call for help (30s of standing still while it rings)
4. Unlock the back door deadbolt (two players: one unzips to turn it, one lookout)
5. Find your glasses (that player's screen is blurred until retrieved — comedy handicap)

### 3.6 Round structure
- Lobby (living room, pillow-fight physics while waiting) → Lights Out → 10-min round → Sunrise win / cocoon loss → recap screen with stat awards ("Loudest Zipper," "Most Falls Down Stairs," "First Cocooned").
- Recap awards are screenshot-bait — they end every session with a shareable artifact.

### 3.7 Cosmetics & progression (retention layer)
- Sleeping bag skins ONLY (racecar bag, mummy bag, shark-eating-you bag, hot dog). Earned via play, no monetization at launch — goodwill play, review-score play.
- Steam achievements tuned for clip moments ("Tumble down both staircases in one round").

### 3.8 Camera design (the horror multiplier)
- **Default:** low third-person chase cam (~0.9m height, ~2.2m back, right-shoulder bias). The player's ground-level scale is the horror engine — furniture towers, hallways stretch, the top of the staircase is out of frame until you're on it.
- **Chase state:** FOV kicks from 70 → 82 + subtle shake when the monster is within 8m. Players feel it before they see it.
- **Cocooned:** snap to first-person INSIDE the bag — fabric weave filling the screen, breathing audio, muffled friends' voices. Claustrophobia as punishment; also the scariest clip in the game.
- **Tumble:** camera stays level while the character crashes — keeps tumbles readable, funny, and nausea-free.
- **Look-back key (Q):** quick 180° glance while wriggling. Seeing the thing behind you while barely able to move is the core fear fantasy.

### 3.9 Audio design notes
- The zipper is the signature sound. Make it iconic and slightly too loud — it's the "Among Us report" of this game.
- Monster proximity = your character's muffled heartbeat inside the bag. Voice proximity attenuation tightens (friends sound farther away when you're cocooned).

### 3.10 Clip-first level design rules
- Every staircase visible from a natural camera angle.
- 9:16 test: does the funniest 10 seconds of a round read on a phone screen? Wide hallways, high-contrast character colors against the house palette.
- Spectator mode after cocooning = free camera → dead players become the clip crew mid-match.

---

## PART 4 — SÉANCE: Fast-Follow Module (summary spec)

Ships on HouseKit ~Q1 2027. Full design doc when Sleepover hits content-complete. What it reuses vs. adds:

**Reuses from HouseKit/Sleepover:** house map (re-lit, Victorian dressing pass), lobby/networking, interaction + `knockable` prop tags, proximity voice, cosmetic/recap frameworks.

**Adds:**
- Asymmetric roles: 1 Ghost (noclip movement, can knock on tagged surfaces, nudge props, flicker lights — each action costs regenerating "presence" energy) vs. 2–5 Mediums.
- Deduction target: Ghost is assigned a secret (killer's identity among portrait suspects, location of the will, cause of death). Mediums win by deducing it before the presence meter — or the ghost's patience — runs out.
- Séance table: Mediums place hands to open yes/no question mode (1 knock = yes, 2 = no). Leaving the table to investigate = risk/reward.
- Twist option to test in prototype: one Medium is secretly the killer, motivated to misinterpret knocks. (Adds social deduction; validate in playtests, cut if it muddies the comedy.)

**Why this order works:** Sleepover teaches you monster AI, physics feel, and launch ops. Séance then only has ONE new hard problem (asymmetric ghost communication) instead of five.

---

## PART 5 — ROADMAP (Sleepover priority)

**Week 1 — Kill test** (Part 2 above). GO/NO-GO decision Friday.
**Weeks 2–3 — HouseKit core:** lobby flow, 4-player sync, interaction system, gray-box full house, proximity voice.
**Weeks 4–5 — Game loop:** AI monster first (noise-driven state machine — this is the balance baseline), objectives, pickups/tools, cocoon/rescue, dual win conditions, round timer. First full playable round.
**Week 6 — Art pass 1:** asset-pack house dressing, character/bag models, lighting. **Steam page goes live** (capsule art via Higgsfield, 5 screenshots, 30s gray-box-ok teaser). Wishlists start NOW.
**Weeks 7–8 — Content & juice:** player-controlled monster mode (random secret assignment, monster kit, noise-ripple vision) tuned against the AI baseline; all 5 objectives, recap awards, bag skins, zipper/heartbeat audio, spectator cam. Weekly Discord playtests begin (card-show friend group = playtest group zero).
**Weeks 9–10 — Polish & beta:** closed beta via Discord keys, feel tuning from footage review, Steam Deck check, achievements.
**Weeks 11–12 — Launch ops:** trailer (cut from playtest clips — jank is the aesthetic), press kit, 150–200 streamer keys 3 weeks out (friendslop/horror mid-tier, 5k–200k followers — build the outreach pipeline in your existing Firecrawl/Gmail stack), demo in Steam Next Fest if timing aligns, launch $5.99 with 10% launch discount, first week of October.

**Parallel marketing track (from week 4, ~5 hrs/wk):**
- Every playtest recorded via OBS → 2–3 TikToks/Shorts per week, 9:16 crops of funniest moments.
- Dev-log angle: "marketer with zero game dev experience builds a Steam game with AI" is itself a viral content lane — document the journey.
- Discord from day one; wishlist target at launch: 7k minimum, 10k stretch.
- Séance teased in Sleepover's post-launch content (poster on the house wall) — cross-pollinate audiences.

**Budget:** Steam Direct $100 + asset packs ~$60–150 + Godot/GodotSteam/Mixamo/Kenney free = **under $300 pre-launch.**

## Claude Code working notes
- One repo, milestone branches. Feed Claude Code one Part/section at a time as the task brief — never the whole doc at once.
- Ask it to write a `FEEL.md` tracking tuning constants (hop impulse, wobble stiffness, monster hearing radius) so iterations are one-line changes.
- GDScript + Godot 4.x; verify GodotSteam API calls against current docs (it moves fast) — have Claude Code fetch the GodotSteam docs when writing lobby code rather than trusting memory.
