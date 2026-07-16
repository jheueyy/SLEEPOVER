extends Node
## Host-authoritative lobby roster synced over the active multiplayer peer.
## Autoload, so its node path is stable for RPCs across the menu -> lobby ->
## game transition (AppRoot only swaps scenes; the peer and this node persist).
##
## The host owns `players`; clients register on join and receive full-roster
## broadcasts. Ready toggles and START route through the host. Late joiners are
## allowed before START and flagged `spectator` if they arrive after.

signal roster_changed
signal game_started

const MAX_PLAYERS := 8
const MIN_TO_START := 1

var players: Dictionary = {}   ## peer_id -> {name, ready, skin, spectator}
var started: bool = false
var _my_name: String = "Player"
var _connected: bool = false   ## client: true once the transport link is up
var _want_ready: bool = false  ## ready requested before the link was ready

func _ready() -> void:
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)

# ── Lifecycle ──────────────────────────────────────────────────────────────

func enter_lobby(my_name: String) -> void:
	_my_name = my_name
	players.clear()
	started = false
	_want_ready = false
	if _authority():
		_connected = true
		players[_id()] = _make_entry(my_name, _id())
		roster_changed.emit()
	elif _link_up():
		_on_connected()   # already connected before we got here
	# otherwise wait for connected_to_server

func _on_connected() -> void:
	# Client's transport link is up — safe to talk to the host now.
	_connected = true
	_register.rpc_id(1, _my_name)
	if _want_ready:
		_set_ready.rpc_id(1, true)

func leave() -> void:
	players.clear()
	started = false
	_connected = false
	roster_changed.emit()

func my_ready() -> bool:
	return players.get(_id(), {}).get("ready", false)

func toggle_ready() -> void:
	set_ready(not my_ready())

func set_ready(val: bool) -> void:
	if _authority():
		_apply_ready(_id(), val)
	elif _connected:
		_set_ready.rpc_id(1, val)
	else:
		_want_ready = val  # applied once connected

func can_start() -> bool:
	if players.size() < MIN_TO_START:
		return false
	for p: Dictionary in players.values():
		if not p.get("spectator", false) and not p.get("ready", false):
			return false
	return true

func start_game() -> void:
	if not _authority() or started:
		return
	started = true
	_start.rpc()
	game_started.emit()

# ── RPCs (host-authoritative) ──────────────────────────────────────────────

@rpc("any_peer", "call_remote", "reliable")
func _register(name: String) -> void:
	if not _authority():
		return
	var pid := multiplayer.get_remote_sender_id()
	players[pid] = _make_entry(name, pid)
	if started:
		players[pid]["spectator"] = true
	_broadcast()

@rpc("any_peer", "call_remote", "reliable")
func _set_ready(val: bool) -> void:
	if _authority():
		_apply_ready(multiplayer.get_remote_sender_id(), val)

@rpc("authority", "call_remote", "reliable")
func _sync_roster(r: Dictionary) -> void:
	players = r
	roster_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _start() -> void:
	started = true
	game_started.emit()

# ── Internals ──────────────────────────────────────────────────────────────

func _apply_ready(pid: int, val: bool) -> void:
	if players.has(pid):
		players[pid]["ready"] = val
		_broadcast()

func _on_peer_disconnected(pid: int) -> void:
	if _authority() and players.has(pid):
		players.erase(pid)
		_broadcast()

func _broadcast() -> void:
	if _peer_live():
		_sync_roster.rpc(players)
	roster_changed.emit()

func _make_entry(name: String, pid: int) -> Dictionary:
	return {"name": name, "ready": false, "skin": BagVisual.skin_for_peer(pid), "spectator": false}

func _peer_live() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

func _link_up() -> bool:
	return multiplayer.has_multiplayer_peer() \
		and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

func _authority() -> bool:
	return not _peer_live() or multiplayer.is_server()

func _id() -> int:
	return multiplayer.get_unique_id() if _peer_live() else 1
