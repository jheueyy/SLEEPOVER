# Sleepover: plan for a finished first release

## The release we should finish

Proposed scope: one carefully authored house, one AI Housesitter, solo practice plus a tested co-op player limit, a complete ten-minute night, all existing task types, rescue/spectate, three endings, replay, scrapbook progression, and finished settings. Choose the shipping player limit through tests; the code's limit of eight is not proof eight feels good.

Defer secret-player monster mode, additional maps, another monster, mutators, and extensive cosmetics until this release is enjoyable and stable. Each would multiply the work before the main experience is settled.

## Beginning-to-end experience

| Beat | Intended experience | Acceptance criterion |
|---|---|---|
| Title | A quiet bedroom invitation with one unsettling detail. Immediately readable Host, Join, Rules, Scrapbook, Settings. | A new player starts or joins without verbal coaching; controls work at the minimum supported resolution. |
| Lobby | Friends arrive, choose a bag, check voice, understand the night's goal, ready up. | Everyone can identify who is unready, hear a friend, and understand how to win. Unsupported options are absent. |
| Arrival | A short safe interval to shuffle, hop, notice stamina and locate a nearby interactable before lights fail. | A first-time player can move and complete one interaction before the first chase. Add contextual prompts, not a long mandatory text lesson. |
| Exploration | Discover clues, recognize rooms, decide which three tasks to pursue. | Players can remember rooms by sight; no clue is inaccessible; discoveries produce clear shared progress. |
| Pressure | Noise draws her toward choices players made; escaping costs stamina and route knowledge. | A caught player can explain why; audio/animation communicate windup, pursuit and recovery. |
| Cooperation | Someone finds a code, someone creates a distraction, someone risks a rescue. | Roles arise from tasks and space without forcing one player to wait doing nothing. |
| Escape | Three tasks arm escape, the relevant task unlocks a route, keys remain an explicit back-door requirement. | HUD and door state agree; no player has to guess why an exit remains locked. Decide explicitly whether first escape wins for everyone or each player must get out. Current code ends the round on the first escape. |
| Capture | A short oppressive cocoon beat, then clear rescue/spectator choices. | Caught players remain involved and know whether help is possible. |
| Ending | Escape, sunrise, or the quiet house; readable recap and earned rewards. | Every outcome offers an obvious next step, saves once, and resets cleanly. |
| Replay | Keep the party, clear round state, roll new tasks, begin again. | One click from the host; clients transition together without lost inventory/state or an empty lobby. |

## Art direction: provisional, pending owner choice

Handmade childhood sleepover horror. Muted quilt reds, dusty teal, warm cream paper, amber practical lights, blue-gray night. Familiar domestic objects should carry the atmosphere: an old phone, hallway coats, a crayon note, a stair light left on.

Use one reference sheet for bag proportions, eye placement, seams, monster silhouette, room scale, texture density, light temperature, UI spacing and typography. Keep shapes simple enough to animate well. Author asymmetry deliberately in selected hero props; do not sprinkle random grunge or noise everywhere.

The title scene should eventually use the same bag model and room materials as gameplay. The scrapbook should feel like a kept object, with consistent lettering and restrained paper details. Results can become a morning-after scrapbook page. Keep functional buttons, focus outlines and readable text even when the surrounding art is diegetic.

Avoid the assembled/generated look through consistency: a small palette, repeated materials with intentional variations, a single silhouette language, matching texture detail, and edited animation timing. Generated concept images can explore alternatives, but production meshes, UI text, logos and hero textures need an explicit review and cleanup pass. Record source and license for every external asset.

## Tools and people

| Tool / role | Use |
|---|---|
| Existing Godot project | Gameplay, networking, lighting, native Control UI, animation integration, builds and profiling. Keep the current engine rather than restarting. |
| Blender | Model, UV, rig and animate the bags, Housesitter and modular house props. Export reviewed game assets into Godot. |
| Krita | Paint texture sheets, scrapbook illustrations, logo studies and UI art. Preserve layered originals. |
| Audacity (free), or REAPER (paid, optional) | Edit recorded cloth/zipper/footstep sounds and monster cues. REAPER adds a fuller music/production workflow but is not required. |
| Git plus a backed-up asset source folder | Preserve code, source art, exports and a manifest of licenses. Use an appropriate large-file workflow once binary art grows. |
| A small recurring playtest group | Observe confusion, boredom, unfair captures, navigation, voice issues and replay desire. Record evidence and change one design variable at a time. |
| A consistent artist/animator and sound designer, if budget permits | Highest-value specialist work: bag/monster identity and movement; distinctive sound cues. Multiple unrelated asset packs are not an art direction. |

Primary tool references: [Blender modeling](https://www.blender.org/features/modeling/), [Blender animation](https://www.blender.org/features/animation/), [Krita features](https://krita.org/en/features/), [REAPER](https://www.reaper.fm/about.php). No purchases or installations have been made.

### Budget clarification

The development software can be free: Godot, Blender, Krita and [Audacity](https://www.audacityteam.org/). REAPER is optional and paid after its evaluation period: [license details](https://www.reaper.fm/purchase.php). Steam charges a [100 USD submission fee per product](https://partner.steamgames.com/steamdirect?l=english). Paid art, audio, contractors and AI services are separate optional costs; existing hardware and labor still matter. Use original assets or verify the commercial-use license for each third-party asset.

### Sack movement direction — September 6

Provisional shuffle reduced from 2.0 to 1.45 m/s, with flat propulsion reduced from 45 to 32 N. An initial 18 N trial failed friction/traction checks. Stairs retain the 1.25 m/s target and separate 45 N propulsion; hop launch values are unchanged. Review monster fairness after testing the new pacing.

Added a shared visual-only gait prototype: distance-driven side-to-side weight transfer (up to five degrees) and slight fabric compression. It settles when stopped and rejects teleport-sized displacement. Local movement suppresses it when airborne/tumbled/cocooned; ghosts estimate eligibility from vertical movement and upright pose. A replicated grounded/state flag is needed for exact remote animation fidelity.

For the final Blender rig, animate alternating internal foot plants, delayed upper-body weight transfer, fabric bunching near the leading foot, a separate two-foot hop, and a heavy landing recovery. Use travel distance to match stride length. Review in third person and with another player; preserve a stable first-person camera. This procedural prototype is not the finished rigged walk cycle.

## Production order and gates

1. **Make one night work.** Finish host authority, late join policy, disconnect behavior, task clarity, fair capture, onboarding and replay. Test with two real players before adding content.
2. **Finish one representative room.** One production bag, one production monster, one complete room and connecting hall, representative interactables, lighting, sound and menu sample. Test visual readability from the actual 0.45 m camera height. Approve this sample before decorating the whole house.
3. **Apply the style to the house.** Build modular doors/stairs/walls, landmark props and material variations. Preserve collision and navigation tests while replacing gray-box visuals.
4. **Finish the surrounding experience.** Lobby bag selection, mic setup, contextual hints, accessible settings/rebinds, recap, credits and coherent menu transitions. Test controller support if it is in the chosen release scope.
5. **Release preparation.** Agreed hardware target, performance profiling, exported-build tests, real Steam invitations/cloud/voice, packet-loss tests, asset/license ledger, accessibility checks, store materials and external playtests. Set dates only after the representative-room workload is measured.

## Asset checklist for the representative slice

- Bag mesh/materials with readable eyes and zipper; idle, shuffle, hop, tumble, recovery and cocoon presentation.
- Housesitter silhouette; patrol, investigate, chase, lunge, recoil and tuck-in animation/audio tells.
- Living-room/hall kit, door, staircase sample, curtain/window, lamp, couch and carpet; recognizable proportions at player height.
- Finished phone/keypad, can, popper, keys and one lore fragment; consistent interaction highlight.
- Title logo/typography choice, button states and controller/keyboard focus; one scrapbook spread and recap layout.
- Cloth movement, landing, zipper, footsteps, door/phone feedback, monster cues, ambient room tone and a short musical identity.

## This implementation pass

Added rules in the title/lobby, a provisional native title composition, direct recap replay/leave actions, input blocking while the menu or recap is open, and developer-only R reset (`--dev-controls`). Removed nonfunctional lobby choices. Added a focused game-flow regression scene. These are production foundations; they do not represent finished artwork or a completed balance pass.

New test: run Godot headlessly with `--scene res://tests/GameFlowRegression.tscn`, using the isolated APPDATA workflow in README. The existing full `--selftest` remains the physics/gameplay acceptance suite.
