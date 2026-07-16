# SLEEPOVER — Launch Master Plan
### Narrative • Objectives • Full Launch To-Do • Live-Ops Retention Architecture
*Companion to sleepover-build-spec.md (mechanics live there; this doc is story, content, and shipping.)*

---

## PART 1 — NARRATIVE: "Maple Street"

### 1.1 The premise
**Maple Street, 1998.** Suburban America, VHS tapes, landline phones (this is WHY there are no cellphones — the era is a design solution, not just an aesthetic). Whenever parents leave kids home alone overnight and the porch light burns out, something shows up to babysit.

### 1.2 The Housesitter (launch monster, canon)
It doesn't want to hurt you. **It wants you to go to sleep.** Cocooning isn't a kill — it's being *tucked in*. It shushes you when it's close. It hums a lullaby when it patrols. At sunrise, it has to leave — that's the survival win condition, in-fiction.

Tone law for all content: **Goosebumps, not Saw.** Creepy-cute, PG-13, zero gore. This maximizes the audience (younger streamers' communities are the viral engine), keeps clips advertiser-safe on TikTok/YouTube, and makes the comedy land harder against the dread.

### 1.3 Lore delivery = retention mechanic (The Scrapbook)
No cutscenes. Lore arrives as **collectible fragments randomly seeded into rounds:** answering machine messages, polaroids, crayon drawings by "the kid who lived here before," newspaper clippings, a babysitting flyer with a phone number that appears... nowhere.
- Collected fragments fill **The Scrapbook** (meta-progression menu). Completing pages unlocks cosmetics + deeper lore.
- Fragments are found mid-round, forcing risk ("there's a polaroid in the attic") — lore hunting IS gameplay.
- Deliberately leave gaps and contradictions. Mystery-theorizing content (YouTube lore videos, subreddit threads) is free marketing that games like FNAF and Lethal Company rode for years. Design the mystery to be argued about.

### 1.4 The anthology engine (why this never runs out of content)
Every future map = **another house on Maple Street.** Every future monster = **another neighborhood legend.** The street itself is the franchise: the cul-de-sac map select screen literally shows houses lighting up as content ships. Players watch the neighborhood grow — a visual roadmap that builds anticipation. New games aren't needed; new addresses are.

---

## PART 2 — OBJECTIVES 2.0 (problem-solving layer)

Every escape task is now **two-step: CLUE → ACTION**, with randomized bindings so no round plays the same. Fetch quests become puzzles; puzzles under monster pressure become panic.

**Complete any 3 to unlock an escape route. All actions require unzipping.**

1. **The Landline.** Find the emergency number (fridge note / mom's address book / scribbled on a takeout menu — location randomized) → dial it on the ROTARY phone. Rotary dialing is the mini-game: each digit is a slow, loud clatter; a wrong digit under pressure restarts the dial. Peak clip potential: someone whisper-screaming "SEVEN. THE NEXT ONE'S A SEVEN."
2. **The Breaker.** The basement fuse box is missing fuses; correct fuse colors + slot order are hinted by a diagram in the garage (randomized pattern). Darkest room in the house, and solving it turns the lights ON — which helps everyone but tells the monster where you were.
3. **The Dog Has The Keys.** Buster carries the house keys on his collar and jingles as he wanders. Lure him with a snack from the pantry — but hopping near Buster makes him bark (a noise ping you don't control). A moving objective that creates emergent chaos.
4. **The Deadbolt.** The back door's top bolt is out of reach — one player must hop-boost off another's shoulders (both unzipped, both helpless, pure trust exercise).
5. **The Garage Code.** The keypad code is a family birthday — find it on the birthday banner / cake photo / calendar (randomized). Wrong entries beep. Loudly.
6. **The Glasses** (comedy wildcard, one random player per round): your screen is badly blurred until you find your glasses. Your friends must describe what you're looking at. Built-in content generator.

**Escape routes (unlocked by any 3 tasks):** front door (keys), garage (code), or basement window (requires stacking boxes — physics puzzle). Multiple exits = strategy arguments = gameplay.

Design rule for all future objectives: **the solution must be communicable over voice by a panicking child.** If it needs a wiki, cut it.

---

## PART 3 — RETENTION ARCHITECTURE (the "don't die in a week" system)

### 3.1 Data-driven content framework (build this way from day one)
- Maps, monsters, objectives, and modifiers load from **data definitions (JSON/Godot resources), not hardcoded logic.** A new objective = a new data file + prefab, not an engine change. This is THE decision that makes monthly content drops feasible for a solo dev.
- Objective system: spawn-point pools + clue/solution binding tables per map.
- Monster framework: shared chassis (navigation, states, cocoon) + swappable "sense profile" (what it hunts), "quirk" (unique rule), and "tell" (how you detect it).

### 3.2 Monster roadmap (each one changes the CORE RULE — that's replayability)
- **Launch — The Housesitter:** hunts NOISE (hop thumps, tumbles, zippers, props). The tutorial legend.
- **Patch 1 (Halloween) — The Tooth Fairy:** hunts MOTION, freezes when any survivor looks at it. Inverts the game: staring contests, walking backwards, "someone watch it while we work." (Weeping Angels, party-game edition.)
- **Patch 2 — The Plumber:** travels through vents/pipes, senses VIBRATION through floors — hopping anywhere on its floor pings it. Forces shuffle-only rounds and vertical map thinking.
- Monster select: random by default (survivors don't know which legend until its first tell — re-terrifying every round), lobby-lockable for streamers.

### 3.3 House Rules (weekly mutators — near-zero-cost content)
Rotating global modifier, one live per week, announced in Discord/TikTok every Monday (a content calendar that writes itself):
- **Blackout** (no lights work, flashlights only) • **Sugar High** (infinite stamina, monster 15% faster) • **Silent Night** (all in-game noise pings travel twice as far) • **Two Sitters** (double monster, half round length) • **Slumber Party** (8-player lobbies, chaos tuning)
- Each is a config file. A weekend of work buys a quarter of "new" content headlines.

### 3.4 Progression & cosmetics
- Bag skins, pajama patterns, pillow hats — earned by play + Scrapbook completion. No paid cosmetics at launch (review-score protection); paid DLC skin packs only AFTER 'Overwhelmingly Positive' momentum is established.
- Recap awards feed a per-player stat card (career tumbles, hops taken, rescues made) — screenshot bait and identity investment.

### 3.5 Community flywheel
- Discord from week 1: playtest keys, House Rules votes ("community picks next week's mutator" = engagement lever), lore-theory channel.
- Clip pipeline: every playtest recorded; 2–3 TikToks/week minimum; "scream compilation" format is the proven banger.
- Streamer program: launch keys to 150–200 mid-tier horror/friendslop creators; POST-launch, ship each new monster to them 48h early. Every content drop re-triggers the creator wave — this cadence, not the launch, is what kills the week-two death.
- Steam Workshop / map editor: the endgame longevity play. Post-launch roadmap item, not launch scope.

### 3.6 Content calendar (first 90 days post-launch)
- **Week 1:** day-3 hotfix patch (there will be bugs; speed = goodwill), scream-compilation trailer from launch clips.
- **Week 2:** House Rules system live, first community vote.
- **Week 4 (Halloween):** The Tooth Fairy + attic map expansion + free skin drop. The second creator wave.
- **Week 8:** New house (Map 2: "The Miller Place" — bigger, two kids' bedrooms, treehouse exterior section).
- **Week 12:** The Plumber + basement-heavy Map 3 + first paid cosmetic pack (only if review score ≥ Very Positive).

---

## PART 4 — FULL LAUNCH TO-DO LIST

### PHASE 0 — Immediate (this week)
- [ ] **Multiplayer kill-test completion:** 2-player GodotSteam sync on the gray-box (the unfinished week-1 item — nothing else proceeds until two sleeping bags exist in one hallway)
- [ ] Stamina-panic spike validated with a real friend once multiplayer sync lands (do chases cause hop-spam tumbles?)
- [ ] GO/NO-GO call on locomotion feel (be brutal; Séance is the pivot)
- [ ] Verify the name: search Steam for "Sleepover" collisions, run a basic USPTO trademark search, secure X/TikTok/Discord handles + domain

### PHASE 1 — Core systems (weeks 2–3)
- [ ] HouseKit: lobby flow (create/invite/join), 4–6 player sync, host migration decision (recommend: host-quit ends round gracefully, don't build migration for v1)
- [ ] Interaction system (doors, drawers, props, unzip channel)
- [ ] Proximity voice (attenuation + wall/cocoon muffle) + push-to-talk fallback + mic device select in settings
- [x] Stamina/tumble tuning — DONE, optimized in Claude Code (FEEL.md in repo is source of truth)
- [ ] Gray-box the FULL house (all 14 rooms, both staircases, chute)

### PHASE 2 — Game loop (weeks 4–5)
- [ ] AI Housesitter: patrol/investigate/chase, noise-ping system, lunge, cocoon channel
- [ ] Cocoon/rescue loop + spectator cam for cocooned players
- [ ] Objectives 2.0: build the clue→action framework (data-driven from day one), implement Landline + Breaker + Deadbolt first
- [ ] Dual win conditions + round timer + sunrise sequence
- [ ] Recap screen with 6 launch awards
- [ ] First full playable round, recorded

### PHASE 3 — Content & art (weeks 6–7)
- [ ] Art pass: asset-pack dressing (Synty/KayKit), 1998 set dressing (CRT TVs, VHS shelves, rotary phone as a hero prop)
- [ ] Character/bag models + Mixamo-adapted animations (shuffle, hop, tumble, unzip)
- [ ] Lighting pass: moonlight + flashlights + the lights-on-after-breaker state
- [ ] The Housesitter model + lullaby hum + shush audio (audio identity > visual fidelity on this budget)
- [ ] Remaining objectives (Dog, Garage Code, Glasses) + 3 escape routes
- [ ] Scrapbook system + first 20 lore fragments written and seeded
- [ ] **STEAM PAGE LIVE** — capsule art (Higgsfield), 5 screenshots, 30-sec teaser, wishlist tracking starts
- [ ] Discord server public

### PHASE 4 — Player monster + juice (weeks 8–9)
- [ ] Player-controlled Housesitter (secret assignment, monster kit, noise-ripple vision) tuned vs. AI baseline
- [ ] Zipper/heartbeat/creak audio stack, chase music sting, camera FOV/shake
- [ ] Cosmetic system + 8 launch bag skins + Scrapbook unlock hooks
- [ ] Steam achievements (15, half of them clip-shaped: "Tumble down both staircases in one round")
- [ ] Weekly Discord playtests begin — every session recorded, TikTok pipeline starts NOW (2–3/week)

### PHASE 5 — Beta & hardening (weeks 10–11)
- [ ] Closed beta via Discord keys (target 100+ testers, 6-player stress rounds)
- [ ] Netcode hardening: packet loss simulation, host-quit handling, rejoin behavior
- [ ] Performance: 60fps on GTX 1060-class hardware; Steam Deck verified-ish pass
- [ ] Settings: rebinds, audio mix sliders, accessibility (arachnophobia-safe? subtitle the monster's audio tells for deaf players — cheap and widens audience)
- [ ] Steam build pipeline: depots, branches (beta/default), cloud saves for Scrapbook/cosmetics
- [ ] Steam review process submitted (build review takes 3–5 business days; page review is separate — buffer BOTH)
- [ ] Price finalized ($5.99, 10% launch discount), regional pricing auto-set
- [ ] Business ops: Steam tax interview + bank info complete, LLC decision (recommend yes — cheap liability shield, you know this drill), basic EULA/privacy page

### PHASE 6 — Launch ops (weeks 11–12)
- [ ] Trailer cut from real playtest chaos (jank + screams = the aesthetic; open on a tumble-down-stairs)
- [ ] Press kit page (screens, GIFs, logo, contact, fact sheet)
- [ ] 150–200 streamer keys, 3 weeks out, via your Firecrawl/Gmail outreach stack — target friendslop/horror creators 5k–200k, personalize the top 30 by name/content
- [ ] Steam Next Fest demo IF the calendar aligns (demo = house + AI monster + 2 objectives only)
- [ ] Launch-day runbook: post schedule (Steam community, Discord, TikTok, X), hotfix triage plan, review-response etiquette
- [ ] Wishlist gate check: 7k minimum before committing to the date; if short, delay 2–4 weeks and push the TikTok pipeline harder — launching thin is the one unrecoverable mistake
- [ ] LAUNCH: Tuesday or Wednesday, first week of October, 10AM Pacific

### PHASE 7 — Post-launch (the actual game begins)
- [ ] Day-3 hotfix patch (pre-commit to it publicly — it converts bug reports into goodwill)
- [ ] Execute the 90-day content calendar (Part 3.6)
- [ ] Weekly House Rules cadence + Discord votes
- [ ] Monster #2 keys to streamers 48h early (Halloween wave)
- [ ] Begin Séance module on HouseKit once Sleepover's week-4 patch ships

---

## PART 5 — WHAT KILLS GAMES LIKE THIS (pre-mortem, read monthly)
1. **Launching thin on wishlists** → algorithm never picks you up. The gate check exists for this.
2. **Voice/netcode jank at launch** → refunds within the 2-hour window. Phase 5 hardening is not skippable.
3. **No content drop in the first 30 days** → creators move on, players follow. The Halloween monster IS the business plan.
4. **Scope creep pre-launch** → October window missed → competing with AAA horror season and losing the Halloween tailwind. When in doubt: cut to the data-driven framework and ship the content later.
5. **Monster balance rage** → player-monster feels unfair in either direction. The AI baseline + lobby-lockable modes are the pressure valves.
