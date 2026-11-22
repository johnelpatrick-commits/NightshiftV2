extends Node
# Networking: ENet for gameplay, UDP broadcast for zero-code LAN/hotspot discovery.
const GAME_PORT := 24567
const DISC_PORT := 24568
const MAGIC := "NSDORM1"

signal rooms_changed
signal connected
signal failed
signal peers_changed

var rooms := {}          # ip -> {name, players, t}
var hosting := false
var dedicated := false
var room_name := "Room"
var _listen: PacketPeerUDP
var _bcasts: Array = []
var _timer := 0.0

func _ready() -> void:
	multiplayer.peer_connected.connect(func(_id): peers_changed.emit())
	multiplayer.peer_disconnected.connect(func(_id): peers_changed.emit())
	multiplayer.connected_to_server.connect(func(): connected.emit())
	multiplayer.connection_failed.connect(func(): failed.emit())
	multiplayer.server_disconnected.connect(func(): failed.emit())

func host(name_: String, is_dedicated := false) -> bool:
	var p := ENetMultiplayerPeer.new()
	if p.create_server(GAME_PORT, 4) != OK:
		return false
	multiplayer.multiplayer_peer = p
	hosting = true
	dedicated = is_dedicated
	room_name = name_.replace("|", "")
	_bcasts.clear()
	if not dedicated:
		var targets := ["255.255.255.255"]
		for a in IP.get_local_addresses():
			var parts: PackedStringArray = a.split(".")
			if parts.size() == 4 and not a.begins_with("127.") and not a.begins_with("169.254."):
				targets.append("%s.%s.%s.255" % [parts[0], parts[1], parts[2]])
		for t in targets:
			var u := PacketPeerUDP.new()
			u.set_broadcast_enabled(true)
			u.set_dest_address(t, DISC_PORT)
			_bcasts.append(u)
	return true

func join(addr: String) -> bool:
	var p := ENetMultiplayerPeer.new()
	if addr == "" or p.create_client(addr, GAME_PORT) != OK:
		return false
	multiplayer.multiplayer_peer = p
	return true

func leave() -> void:
	stop_search()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	hosting = false
	dedicated = false
	_bcasts.clear()

func start_search() -> void:
	stop_search()
	rooms.clear()
	_listen = PacketPeerUDP.new()
	if _listen.bind(DISC_PORT) != OK:
		_listen = null

func stop_search() -> void:
	if _listen:
		_listen.close()
		_listen = null

func _process(d: float) -> void:
	_timer += d
	if hosting and not dedicated and _timer >= 1.0:
		_timer = 0.0
		var msg := ("%s|%s|%d" % [MAGIC, room_name, multiplayer.get_peers().size() + 1]).to_utf8_buffer()
		for b in _bcasts:
			b.put_packet(msg)
	if _listen:
		var changed := false
		while _listen.get_available_packet_count() > 0:
			var data := _listen.get_packet().get_string_from_utf8().split("|")
			var ip := _listen.get_packet_ip()
			if data.size() == 3 and data[0] == MAGIC:
				rooms[ip] = {"name": data[1], "players": int(data[2]), "t": Time.get_ticks_msec()}
				changed = true
		for ip in rooms.keys():
			if Time.get_ticks_msec() - rooms[ip].t > 4000:
				rooms.erase(ip)
				changed = true
		if changed:
			rooms_changed.emit()
