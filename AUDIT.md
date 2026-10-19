# Sleepover engineering audit — September 6, 2026

## Assessment

Playable co-op prototype with a substantial solo acceptance harness. Not yet ready for an unrestricted public multiplayer playtest. The highest priority is completing host validation and late-join state transfer, before adding another monster or map.

This pass inspected startup/menu flow, lobby transport and roster, persistence, voice transport, gameplay RPCs, design documents, and existing tests. Headless execution exercised player physics, map coverage, objectives, inventory, monster containment, camera state, and round outcomes. It does not certify visual quality, real microphones, Steam invitations/cloud, internet latency, or exported builds.

## Changes delivered

- Lobby start now enforces readiness in the manager itself, requires an active player, and avoids sending a solo RPC. Repeated start delivery is idempotent.
- Lobby lifecycle clears pending connection/ready state; registration rejects duplicate/invalid senders and over-capacity rosters. Cosmetic indices and displayed names are bounded.
- Save loading tolerates invalid field types, deduplicates known fragment IDs, rejects locked skin selections, and bounds career counters.
- Save writes use a temporary sibling file and replacement after a successful flush. Failures are reported and do not upload new state to Steam Cloud. This is not a backup or cloud-conflict resolution system.
- Mouse sensitivity now affects the active game and newly loaded rounds. Master volume and sensitivity are persisted when closing Settings with Back.
- Added ten targeted regression assertions and refreshed setup documentation. Existing uncommitted Main.gd changes were preserved.

## Open findings, in priority order

| Priority | Finding and evidence | Required next work |
|---|---|---|
| P1 | Main.gd `_net_report_escape` trusts a supplied peer ID and ends an armed round without confirming that sender is alive at an open exit. `_report_objective` and `_net_request_keys_turned` similarly accept completion claims without enough host-side interaction validation. | Derive identity from transport; verify phase, roster membership, player state, proximity, and task-specific completion on the host. Add adversarial two-peer tests. |
| P1 | `_net_request_spawn_item` accepts arbitrary item kinds/positions; `_authoritative_take_item` lacks host-owned inventory capacity checks. `_net_rescued` accepts direct peer rescue claims. | Introduce host-owned inventory and rescue transactions; validate consumption, ownership, distance and timing before broadcasting results. |
| P1 | `_net_bag_state` trusts transforms and hidden/cocooned flags. Client position/state claims can override host-observed capture and inject invalid transforms. | Validate finite transforms and movement envelopes; keep gameplay state authoritative on host. Position checks alone do not solve client-authoritative movement. |
| P1 | Late `_register` marks a spectator but does not deliver START/current round snapshot. `_ack_loaded` only starts an initial lobby round; `_become_spectator` only hides/freezes a local bag. | Implement snapshot transfer after scene-load acknowledgment, spectator camera targets, exclusion from player simulation, and reconnect/late-join integration tests. |
| P2 | SteamManager ignores return errors from peer `create_host` / `create_client`; AppRoot handles server disconnect but not `connection_failed`. | Surface transport failures, close failed peers/lobbies, and restore a retryable menu. Verify with Steam running. |
| P2 | Voice loopback emits 4,829-byte unreliable packets, exceeding ENet's reported 1,392-byte MTU. Observed in both process logs. | Packetize test PCM below transport limits; measure actual compressed Steam voice packets and packet loss separately. |
| P2 | Settings still have no rebinds; lobby monster/rules/map choices are stubs. Volume and sensitivity save on Back, not every possible close/crash path. | Implement remaining controls, clearly disable unsupported options, and define a consistent settings commit lifecycle. |
| P2 | Persistence has no backup recovery, save-version migration, or Steam Cloud conflict resolution. | Add explicit version handling and recovery policy before shipping progression. Test disk failure and cloud behavior on a real account. |
| P2 | Headless suite reports four leaked ObjectDB instances at shutdown; ENet host reports five. | Use verbose shutdown diagnostics to identify ownership leaks; repeat scene enter/leave cycles to determine whether leaks accumulate. |
| P3 | Main.gd combines a large embedded test harness, UI, world setup, inventory, objectives and replication. | Extract tests and one gameplay system at a time after host-state contracts are established. Avoid a broad refactor while networking behavior is unsettled. |

## Validation evidence

- Godot executable available locally: 4.7.stable.official.5b4e0cb0f.
- Baseline selftest failed its two persistence checks with the default sandbox data location. Redirecting APPDATA to a workspace test directory resolved those checks; this is an environment issue, not evidence of broken normal-user saves.
- Full gameplay selftest after save/lobby changes: `RESULT: ALL PASS`, exit 0. Checks include three round outcomes, 46 floor anchors, walkable stairs, hop economy, items, keys, first-person/cocoon/spectator state, lore and voice preferences.
- Dedicated regression scene: ten assertions pass, exit 0, including malformed saves, replacing an existing save, saved audio/mouse preferences, unready starts and spectators-only lobbies.
- Two ENet processes: both entered LIGHTS_OUT then ROUND; matching objective/item setup appeared in logs; voice packets and a client noise event reached the host; both basement navigation probes reached their targets. Timed host termination returned the client to the menu. This is a startup/transport smoke test, not a full multiplayer acceptance suite.
- Environment warnings: Windows root certificate store unavailable and Steam absent in the sandbox. Navigation voxel-radius rounding also warns. Monster out-of-bounds warning is deliberately triggered by its containment test.
- Logs are local ignored artifacts: `audit-baseline.log`, `audit-verified.log`, `audit-final.log`, `audit-regression.log`, `audit-host.log`, `audit-client.log`.

## Next build acceptance target

Two clients must be unable to award themselves objectives, inventory, escapes, rescues or protected state through forged requests. A third client joining an active round must receive a complete snapshot and spectate without affecting the round. Run those checks under disconnects and delayed packets, then perform a rendered friend playtest before expanding content.

Escape validation revision: escape reports now derive identity from the transport and reject mismatched claims, inactive rounds, unknown bags, captured bags, and positions outside open exit zones. Five focused flow assertions pass. This is partial host validation: replicated transforms and cocoon flags still need their own authority hardening; objective and inventory claims remain open findings.


Transform validation revision: network updates require a connected sender, finite position/quaternion, bounded world position and usable quaternion length; accepted rotations are normalized and tumble counters bounded. Flow regressions pass. This does not yet impose a movement-speed envelope or replace client-authored capture flags. Synthetic voice test cadence is now 20 ms (960-byte PCM payload), with a transport-budget assertion; actual Steam compressed voice remains unchanged.


Rescue transaction revision: only the host broadcasts completed rescues. Requests use transport identity and validate round, known distinct bags, capture state, finite positions and rescue range. Credit is awarded once by the host. Target changes reset local hold progress, and rescue clears voice muffling. Focused tests cover unknown/self/distant requests, nearby success and duplicate credit. Remaining: the five-second hold is still client-timed, and replicated capture flags/positions still require stronger authority.


Rescue timing revision: the host now accumulates the five-second hold while valid clients send 200 ms hold updates. A 650 ms silence, lost proximity, invalid capture state, target switch, key release or pause cancels the attempt. Movement packets can no longer override host-owned capture state. Timing and stale capture packet regressions pass. Remaining networking validation includes real two-peer rescue under latency, host relay of capture presentation, movement authority and the other objective/inventory transactions.


Capture relay revision: host capture events now broadcast reliably to every peer (including captures of the host). Movement flags no longer change capture state on clients. Regression covers stale captured flags after rescue. Two ENet processes reached ROUND and exchanged movement, monster footsteps and smaller synthetic voice packets without the previous MTU warnings. This startup smoke did not perform an actual two-player rescue.


Two-process rescue acceptance: tests/NetworkRescueRegression.tscn runs with --enet-host and --enet-join. On local ENet, the client observed host capture, sent a canceled hold followed by a sustained hold through RPCs, observed restored state, and the host verified exactly one rescue credit. Both exited 0; host reported [RESCUE NET] PASS. This uses frozen bags and synthetic hold requests to isolate protocol behavior, not physical keyboard interaction or internet latency. Existing shutdown ObjectDB warnings remain.


Connection failure revision: AppRoot handles connection_failed by closing the transport, clearing lobby/round state and showing a retryable menu message. Steam peer creation now checks errors and leaves failed lobbies before reporting failure. The flow regression exercises connection-failure cleanup successfully. Real Steam peer-creation failures remain untested because Steam is unavailable in this environment.


Objective interruption revision: pause/capture cancels local hold and rotary-digit timers and closes entry panels while allowing dog simulation to continue. Captured local/remote bags no longer count toward deadbolt helpers. Focused interruption/helper regression and game flow pass. Objective completion RPC authority remains an open finding.


Objective report validation: host rejects unknown/completed objective IDs, inactive-round reports, unknown or captured bags and distant claims. Glasses require the selected player; deadbolt requires two uncaptured bags. Positional allowance is 0.35 m beyond interaction reach for interpolation. Regression verifies rejection and a nearby living-player acceptance. Puzzle input/sequence proof, dog snack ownership and hold duration still require host-owned task state; this is not complete objective authority.


Objective rejection recovery: rejected local solves restore their props and clear pending entry/hold state so the task can be retried. Already completed reports receive the accepted host state again. Focused retry regression and game-flow suite pass. This prevents host validation from stranding a client with hidden unfinished task props.


Pickup request validation: host now checks active round, known living bag, finite position and pickup distance before consuming an item. Host-local pickup also checks free inventory space. Unknown/distant/captured rejection and nearby acceptance regressions pass. Remote inventory capacity and all item consumption/drop ownership still need a host ledger. Full gameplay selftest before this pickup edit passed; game flow after it passes.


Noise attribution revision: relayed remote NoiseBus events no longer count again as host noise. Reports require an active round, known peer, finite bounded position and loudness in (0,1]. Regression verifies malformed rejection and sender-only scoring. Action-source validation/rate limiting remains open; arbitrary in-bounds positions are not yet authenticated because decoys and task sounds originate away from the player.


Shutdown investigation: verbose flow runs showed variable audio-resource leak warnings rather than a stable leaked UI-node list. The flow test now explicitly queues its AppRoot for deletion and waits for audio cleanup before quitting. The next verbose run passed without ObjectDB/resource shutdown warnings; certificate/Steam/navigation environment warnings remain. This single clean run does not prove production scene cycles are leak-free.


Repeated scene lifecycle check: three start/leave cycles return to the baseline SceneTree node count, release the old game object and leave no voice players registered. This exposed a Player startup call to get_unique_id after solo transport cleanup; it now uses peer 1 when no multiplayer peer exists. All three cycles and the flow suite pass after the fix, with no missing-peer errors. GPU/audio memory over long real play sessions remains unmeasured.


Save recovery: each successful replacement now preserves the previous valid JSON save as .bak through a staged backup write. Loading tries primary, backup, then Cloud. Malformed primary files never overwrite the good backup. Tests verify corrupted-primary recovery, byte-for-byte backup preservation while saving recovered data, and missing-primary recovery. These checks pass; version migration, semantically corrupt but parseable files, Cloud conflict resolution and real disk failure remain unfinished.


Dog timer correction: barking now has its own timer instead of sharing rotary-input progress. Blocking player interaction no longer resets the dog's bark cadence every frame. The focused timer assertion and complete flow regression pass.

Key-turn confirmation: keys remain in inventory until the host confirms the back door opened. Host requests require an active round, known living bag and proximity to the back door. Invalid slot indexes are ignored. Flow regression covers rejection preserving keys, captured-peer rejection, successful consumption and missing local keys; the full gameplay selftest also passes, including the dog hand-off, key set-down and door unlock.

Shared inventory revision: the host now owns remote two-slot inventories and validates item kind against the requested slot. Pickup capacity, can throws, popper consumption, key use, capture spills and disconnect spills update that ledger. Arbitrary client item-spawn requests were removed; throw and popper effects are authority-only RPCs. Clients keep their inventory until reliable host confirmation. The first accepted dog completion grants keys to its feeder or drops them when that bag is full; duplicate completion cannot mint more keys. Remote item noise is credited to the owner, not the host.

Validation: InventoryRegression passes capacity, forged and duplicate use, noise attribution, key ownership, hand-off, capture, disconnect, duplicate dog completion and round reset checks. NetworkInventoryRegression passes in two local ENet processes: both peers agree on capacity, one landing for duplicate throw requests, capture spills and key consumption at the back door. The full gameplay selftest passes after the inventory refactor. These are local tests, not Steam or latency/loss testing; shutdown resource warnings remain in some harness runs. Task sequence/snack validation, movement authority and late-join state still need work.

Lore pickup revision: host claims now require an active round, an existing uncollected fragment, a known living bag, reach and the perch height gate. Reading waits for accepted collection; duplicate application is ignored. Flow tests cover unknown/distant/captured/below-perch rejection and once-only credit. Hold duration and line-of-sight authority are still not enforced by this claim check.
Can impact timing: the host waits for the same 0.25–0.9 second duration used by the throw arc before emitting noise, broadcasting the impact sound and spawning the collectible can. Round cleanup invalidates pending landings. Inventory tests cover silence/unavailability in flight and cancellation across rounds; full selftests and two-process ENet inventory tests pass. Real network latency may still offset client visual timing from the host impact packet.
Late-join revision: newly registered spectators are sent START, then receive current round setup, remaining items, task/reveal state, collected fragment state, doors, timer, monster and bag capture state after their scene acknowledges loading. Main broadcasts target acknowledged scenes. Spectator bags are inert, excluded from active count and movement replication, and return to play on the next night. Two-process LateJoinRegression passes snapshot parity, spectator camera/inertness and next-night promotion without missing-scene packet errors; normal co-op inventory and flow checks also pass. Steam, many-client races and joins during every transition still require testing. The floor-anchor selftest now excludes the player body from its floor ray, after a spawn check hit the bag instead of the house.
Physical dog task: the round now seeds one shared beef-jerky pickup when the dog task is drawn. Jerky occupies a host-owned slot and can be set down, recovered, or spilled through the shared inventory system. Giving it to the nearby dog consumes the owned jerky and replaces it with keys; captured/distant/missing-item completion cannot grant keys. The old private snack pickup flag no longer grants the item. Inventory tests exercise pickup, set-down, recovery, feeding and duplicate completion; flow and full selftests pass. A dedicated two-client jerky hand-off and final prop/animation polish remain to be tested.
Dog replication: only the host now advances the dog navigation and bark timer. Clients interpolate authoritative dog positions and receive the recorded periodic bark as a host event. Flow regression verifies disabled client simulation; a two-process ENet test deliberately displaces the client dog and verifies convergence within 0.25 m, then completes the inventory/capture/key sequence. Dedicated jerky transfer between two players and feeding under latency remain untested.
Two-player physical hand-off verified: NetworkInventoryRegression now has the client pick up and drop jerky, the host recover and feed it to the dog, the host drop the earned keys, and the client recover the keys and open the back door. Both ENet processes exit successfully. Feeding noise and the recorded bark now occur on accepted host completion, covering both E and inventory-slot feeding. This is local transport validation; real player navigation, latency and subjective feel still need playtesting. Existing shutdown resource warnings remain.
Ambient dog noise no longer counts against the host in noise awards. Periodic barks still emit one gameplay hearing event; accepted feeding remains attributed once to the feeder. Flow and inventory regressions verify both paths and pass.
Recoverable drops: key/jerky set-downs and capture/disconnect spills now check the path against walls, leave clearance before an obstruction, and snap to nearby ground. Unsupported ledge targets fall back to ground beneath the bag. Inventory regression passes controlled wall and ledge fixtures plus existing ownership/feeding checks. Full prop-volume corner clearance and every staircase arrangement remain unverified.
