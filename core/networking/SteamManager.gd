extends Node
## Steam bootstrap + lobby helpers (GodotSteam 4.20 GDExtension, Godot 4.7).
## Autoload. Initializes Steam under Spacewar (app 480) for dev. If Steam isn't
## running, the game stays in solo mode — the menu still works, host = solo.
##
## Menu flow: HOST creates a PUBLIC lobby stamped with a random 6-char join
## CODE (lobby data); JOIN BY CODE searches public lobbies for that code. The
## Steam overlay invite also works (activateInviteDialog + join_requested).
## Networking uses SteamMultiplayerPeer so Godot's RPC layer runs on top;
## LobbyManager owns lobby roster/ready and Main owns gameplay sync.

signal lobby_ready(lobby_id: int, is_host: bool)
signal lobby_failed(reason: String)

const APP_ID := 480
const LOBBY_TAG := "sleepover"
const MAX_PLAYERS := 8
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no ambiguous 0/O/1/I

var steam_ok: bool = false
var lobby_id: int = 0
var is_host: bool = false
var join_code: String = ""       ## the 6-char code for the current lobby

func _ready() -> void:
	# Dev loopback mode: `-- --enet-host` / `-- --enet-join` runs the same RPC
	# stack over ENet on localhost, no Steam. Drives the automated sync tests.
	var args := OS.get_cmdline_user_args()
	if args.has("--enet-host"):
		_start_enet(true)
		return
	if args.has("--enet-join"):
		_start_enet(false)
		return

	var res: Dictionary = Steam.steamInitEx(APP_ID)
	steam_ok = int(res.get("status", 1)) == Steam.STEAM_API_INIT_RESULT_OK
	if not steam_ok:
		push_warning("Steam init failed (%s) — solo mode, no lobbies." % res.get("verbal", "?"))
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)
	Steam.join_requested.connect(_on_join_requested)          # overlay "Join Game"
	# Launched via an invite? Steam passes +connect_lobby <id>.
	var connect_lobby := _cmdline_connect_lobby()
	if connect_lobby != 0:
		Steam.joinLobby(connect_lobby)

func _process(_delta: float) -> void:
	if steam_ok:
		Steam.run_callbacks()

func persona() -> String:
	return Steam.getPersonaName() if steam_ok else "Player"

func in_lobby() -> bool:
	return lobby_id != 0

# ── Host / join ────────────────────────────────────────────────────────────

func host_lobby() -> void:
	if lobby_id != 0:
		return
	if not steam_ok:
		# Solo: no Steam, but the menu still enters a one-player "lobby".
		is_host = true
		lobby_id = -2  # sentinel: solo (no peer)
		join_code = "SOLO"
		lobby_ready.emit(lobby_id, true)
		return
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)

func join_by_code(code: String) -> void:
	if not steam_ok or lobby_id != 0:
		lobby_failed.emit("Steam offline — can't join.")
		return
	Steam.addRequestLobbyListStringFilter("scode", code.to_upper(), Steam.LOBBY_COMPARISON_EQUAL)
	Steam.addRequestLobbyListStringFilter("game", LOBBY_TAG, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func invite_overlay() -> void:
	if steam_ok and lobby_id > 0:
		Steam.activateGameOverlayInviteDialog(lobby_id)

func leave_lobby() -> void:
	if steam_ok and lobby_id > 0:
		Steam.leaveLobby(lobby_id)
	if multiplayer.has_multiplayer_peer():
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	lobby_id = 0
	is_host = false
	join_code = ""

# ── Steam callbacks ────────────────────────────────────────────────────────

func _on_lobby_created(result: int, this_lobby_id: int) -> void:
	if result != 1:
		lobby_failed.emit("createLobby failed (result %d)" % result)
		return
	lobby_id = this_lobby_id
	is_host = true
	join_code = _gen_code()
	Steam.setLobbyData(lobby_id, "game", LOBBY_TAG)
	Steam.setLobbyData(lobby_id, "scode", join_code)
	var peer := SteamMultiplayerPeer.new()
	peer.create_host(0)
	peer.server_relay = true
	multiplayer.multiplayer_peer = peer
	lobby_ready.emit(lobby_id, true)

func _on_lobby_joined(this_lobby_id: int, _perms: int, _locked: bool, response: int) -> void:
	if is_host:
		return
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_failed.emit("join failed (response %d)" % response)
		return
	lobby_id = this_lobby_id
	join_code = Steam.getLobbyData(this_lobby_id, "scode")
	var owner_id: int = Steam.getLobbyOwner(this_lobby_id)
	if owner_id == Steam.getSteamID():
		return
	var peer := SteamMultiplayerPeer.new()
	peer.create_client(owner_id, 0)
	peer.server_relay = true
	multiplayer.multiplayer_peer = peer
	lobby_ready.emit(lobby_id, false)

func _on_lobby_match_list(lobbies: Array) -> void:
	if lobbies.is_empty():
		lobby_failed.emit("No lobby with that code. Check the 6 characters.")
		return
	Steam.joinLobby(lobbies[0])

func _on_join_requested(this_lobby_id: int, _friend_id: int) -> void:
	if lobby_id == 0:
		Steam.joinLobby(this_lobby_id)

# ── Helpers ────────────────────────────────────────────────────────────────

func _gen_code() -> String:
	var c := ""
	for i in 6:
		c += CODE_CHARS[randi() % CODE_CHARS.length()]
	return c

func _cmdline_connect_lobby() -> int:
	var args := OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "+connect_lobby" and i + 1 < args.size():
			return int(args[i + 1])
	return 0

func _start_enet(host: bool) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(24565, MAX_PLAYERS - 1) if host \
		else peer.create_client("127.0.0.1", 24565)
	if err != OK:
		lobby_failed.emit("ENet loopback setup failed (%d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	is_host = host
	lobby_id = -1  # sentinel: dev loopback
	join_code = "LOOPBK"
	print("[NETTEST] ENet %s ready" % ("host" if host else "client"))
	lobby_ready.emit.call_deferred(-1, host)
