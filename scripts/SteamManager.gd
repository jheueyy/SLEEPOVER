extends Node
## Steam bootstrap + lobby helpers (GodotSteam 4.20 GDExtension, Godot 4.7).
## Autoload. Initializes Steam under Spacewar (app 480) for dev. If Steam isn't
## running, the game silently stays in solo mode — nothing else breaks.
##
## Dev flow (no Steam overlay needed, it doesn't work in-editor):
##   Host: H  -> createLobby(PUBLIC) tagged "sleepover_kill_test", becomes server
##   Join: J  -> requestLobbyList filtered on that tag, joins the first match
## Networking uses SteamMultiplayerPeer (bundled in the GDExtension) so Godot's
## normal RPC layer works on top; Main.gd does the actual state sync.

signal lobby_ready(lobby_id: int, is_host: bool)
signal lobby_failed(reason: String)

const APP_ID := 480
const LOBBY_TAG := "sleepover_kill_test"
const MAX_PLAYERS := 6

var steam_ok: bool = false
var lobby_id: int = 0
var is_host: bool = false

func _ready() -> void:
	# Dev loopback mode: `-- --enet-host` / `-- --enet-join` runs the exact same
	# RPC sync over ENet on localhost, no Steam needed. Used for automated
	# two-instance sync tests; Steam transport itself is tested with a friend.
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
		push_warning("Steam init failed (%s) — running solo, no lobbies." % res.get("verbal", "?"))
		return
	Steam.lobby_created.connect(_on_lobby_created)
	Steam.lobby_joined.connect(_on_lobby_joined)
	Steam.lobby_match_list.connect(_on_lobby_match_list)

func _process(_delta: float) -> void:
	if steam_ok:
		Steam.run_callbacks()

func persona() -> String:
	return Steam.getPersonaName() if steam_ok else "offline"

func host_lobby() -> void:
	if not steam_ok or lobby_id != 0:
		return
	# PUBLIC (not friends-only) so the J-key lobby search finds it without the
	# overlay invite flow, which doesn't work in the editor.
	Steam.createLobby(Steam.LOBBY_TYPE_PUBLIC, MAX_PLAYERS)

func join_lobby() -> void:
	if not steam_ok or lobby_id != 0:
		return
	Steam.addRequestLobbyListStringFilter("game", LOBBY_TAG, Steam.LOBBY_COMPARISON_EQUAL)
	Steam.requestLobbyList()

func _on_lobby_created(result: int, this_lobby_id: int) -> void:
	if result != 1:
		lobby_failed.emit("createLobby failed (result %d)" % result)
		return
	lobby_id = this_lobby_id
	is_host = true
	Steam.setLobbyData(lobby_id, "game", LOBBY_TAG)
	var peer := SteamMultiplayerPeer.new()
	peer.create_host(0)
	peer.server_relay = true
	multiplayer.multiplayer_peer = peer
	lobby_ready.emit(lobby_id, true)

func _on_lobby_joined(this_lobby_id: int, _perms: int, _locked: bool, response: int) -> void:
	if is_host:
		return  # the host receives lobby_joined for its own lobby; ignore
	if response != Steam.CHAT_ROOM_ENTER_RESPONSE_SUCCESS:
		lobby_failed.emit("join failed (response %d)" % response)
		return
	lobby_id = this_lobby_id
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
		lobby_failed.emit("no open lobby found — has the host pressed H?")
		return
	Steam.joinLobby(lobbies[0])

func _start_enet(host: bool) -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(24565, MAX_PLAYERS - 1) if host \
		else peer.create_client("127.0.0.1", 24565)
	if err != OK:
		lobby_failed.emit("ENet loopback setup failed (%d)" % err)
		return
	multiplayer.multiplayer_peer = peer
	is_host = host
	lobby_id = -1  # sentinel: dev loopback, not a Steam lobby
	print("[NETTEST] ENet %s ready" % ("host" if host else "client"))
	# Defer so Main exists and has connected to lobby_ready before we emit.
	lobby_ready.emit.call_deferred(-1, host)
