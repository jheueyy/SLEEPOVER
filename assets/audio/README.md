# Sleepover sound assets

Downloaded September 6, 2026 directly from Kenney. All three packs include CC0 licenses permitting personal and commercial use; their original License.txt files are preserved beside the samples. No purchases or recordings were required.

| Files | Creator / source | License | In-game role |
|---|---|---|---|
| kenney-impact/footstep_carpet_000–002.ogg | [Kenney Impact Sounds 1.0](https://kenney.nl/assets/impact-sounds) | CC0 1.0 | Retained unused; replaced by cloth recordings |
| kenney-impact/impactSoft_heavy_000–002.ogg | Same pack | CC0 1.0 | Bag landings and existing thump cues |
| kenney-impact/footstep_wood_000–002.ogg | Same pack | CC0 1.0 | Retained unused; replaced by creak recordings |
| kenney-impact/impactMetal_light_000–002.ogg | Same pack | CC0 1.0 | Existing clatter cues |
| kenney-interface/click_001–002.ogg | [Kenney Interface Sounds 1.0](https://kenney.nl/assets/interface-sounds) | CC0 1.0 | Menu presses |
| kenney-interface/select_001.ogg | Same pack | CC0 1.0 | Menu hover / keyboard focus |

Audio files are unmodified originals. Runtime gain and pitch adjustments are defined at the call sites. SHA-256 hashes are recorded in checksums.json using project-relative paths. Only this selected subset ships; the full downloaded archives remain in the ignored .audit-user directory.

SoundKit selects variants without immediate repetition and uses its own RNG so selecting a footstep does not alter gameplay randomization. Movement sounds do not emit NoiseBus events; existing hop/tumble noise mechanics remain in charge of monster detection. Remote shuffle cadence uses replicated ground contact and interpolated distance. Monster footstep events are sent by the host because clients do not run the monster physics loop. Bag landings use a separate transient RPC, resolved to the sender's existing ghost position, with a 200 ms duplicate guard. Unknown peers, cocooned bags and inactive-round landings are ignored.

## Mix controls

Settings has Master, Sound effects, and incoming Voice sliders. Effects includes menu feedback, movement, monster cues and breathing. Clear voice, wall-muffled voice and cocoon-muffled voice all feed the Voice group, independently of effects. Zero truly mutes a group. Preferences apply live and save on Back/Escape, leaving a game, or transitioning out of Settings. Older saves default both new groups to full volume. The Settings overlay is scrollable and sits above the pause panel.

Hum, breathing, zipper, chase sting, lunge screech, shush and other unmapped cues still use procedural fallbacks. The Freesound zipper candidate at https://freesound.org/people/bmacphail/sounds/569540/ requires login for the original download and was NOT downloaded or included. No claim is made that the soundscape is finished; these files need an in-game listening/mix pass with real speakers/headphones.

## Verification

- `tests/AudioRegression.tscn`: 23 active Ogg samples load with positive duration; variants avoid immediate repetition; sample RNG leaves gameplay RNG unchanged; procedural fallback works; shuffle creates audio without NoiseBus events; blocked controls suppress new steps.
- Full gameplay selftest: ALL PASS after sample integration.
- Game-flow regression: PASS, including the client-side monster-footstep handler.
- Two-process ENet smoke: both reached ROUND; client logged two received monster footsteps and returned to menu when host exited. This verifies event transport, not subjective mix quality.
- Known remaining diagnostics: shutdown ObjectDB/resource warnings, sandbox certificate-store warning, and the pre-existing oversized synthetic voice packets. Audio import completed; editor cache writes outside the workspace were unavailable in the sandbox.

## Cloth and interaction revision

Kenney RPG Audio (https://kenney.nl/assets/rpg-audio), CC0; original license in kenney-rpg/License.txt. cloth1–4 provide sack rustles; creak1–3 provide Housesitter creaks; metalPot1–3 provide thrown-can impacts; metalLatch provides the key-lock cue; bookFlip1–3 provide readable-fragment page rustles. These are original recordings, with runtime processing only. Shuffle triggers every 0.65 m with a 0.32 s minimum interval, pitch multiplied by 0.85, and a soft onset/tail capped at 0.55 s. Local and remote bags share the tuning. The old carpet and wooden footstep assets are no longer selected. Headless validation verifies loading, routing and cleanup, not subjective sound quality.

Zipper revision: AntumDeluge's CC0 jacket zipper from https://opengameart.org/content/zipper now supplies all zipper calls, including rescue and unzip. Source/license are recorded in antumdeluge/License.txt. The earlier statement that zipper remains procedural is superseded. There are now 24 active sample entries.


Breathing revision: mikeask's Breathing Tired (https://opengameart.org/content/breathing-tired), CC0, replaces the procedural captured-player breathing. The unmodified WAV and source/license are in mikeask/. Runtime gain is -12 dB through InBag; phrases repeat after a 0.4 s rest only while captured during ROUND. Audio regression now validates 25 active WAV/Ogg entries. This supersedes earlier statements that breathing is procedural; subjective mix review remains needed.


The title menu now includes a Credits screen listing Kenney, AntumDeluge and mikeask with source locations and CC0 licensing. Back/Escape returns to the title. This is audio attribution, not a complete release dependency-license audit.


Procedural fallback RNG isolation: remaining generated sounds now use SoundKit's private random generator throughout. Constructing shush/clatter no longer consumes gameplay random values; the regression verifies this alongside sample-selection isolation.


Settings sound check: select shuffle, zipper, breathing, creak, can impact or page turn, then Play/Stop. Preview uses the Effects mix (breathing through InBag), replaces the previous preview, and stops when Settings closes. This previews clips without world-distance attenuation; shuffle preview uses lower pitch but not the in-world per-drag envelope. Tests verify the recorded zipper and stop-on-close behavior.


Dog bark revision: Brandon Morris / HaelDB's Dog barking mono, https://opengameart.org/content/dog-barking-mono, replaces the procedural bark under the source's CC0 option. Original WAV and license record are in brandon-morris/. Runtime gain -12 dB, 16 m range, pitch variation; gameplay noise unchanged. Added to Sound check and Credits. Audio regression validates 26 sample entries and bark duration against the existing four-second cadence. Subjective recording/mix quality remains to be reviewed.

