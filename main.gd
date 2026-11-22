extends Control
# Night Shift Dorm - original co-op survival game. Server-authoritative; UI built in code.

const NROOMS := 4
const NIGHT_TIME := 90.0
const NIGHTS := 3

var st := {"phase": "menu"}
var ui: Control
var _shown := ""
var room_list: VBoxContainer
var ip_edit: LineEdit
var _hdr: Label
var _panels: Array = []
var _bars: Array = []
var _rlabels: Array = []
var _b_sleep: Button
var _b_repair: Button
var _b_door: Button
var _b_bed: Button
var _ghost_t := 4.0
var _sync_acc := 0.0
var _b_salt: Button
var _b_light: Button
var _snd := {}
var _last_target := -1
var _last_night := 1
var _shake := 0.0

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.1)
	add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui = Control.new()
	add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Net.rooms_changed.connect(_fill_rooms)
	Net.failed.connect(_on_net_failed)
	Net.peers_changed.connect(_on_peers)
	_snd = {"warn": _tone(220, 0.3), "hit": _tone(80, 0.35, 0.7), "dawn": _tone(784, 0.6, 0.35)}
	if "--server" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_user_args():
		Net.host("Dedicated", true)
		_reset_lobby()
		return
	_menu()

# ---------- UI helpers ----------
func _lbl(t: String, sz := 28) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 90)
	b.add_theme_font_size_override("font_size", 28)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b

func _page() -> VBoxContainer:
	for c in ui.get_children():
		c.queue_free()
	var cc := CenterContainer.new()
	ui.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(700, 0)
	v.add_theme_constant_override("separation", 14)
	cc.add_child(v)
	return v

func _toast(t: String) -> void:
	var l := _lbl(t, 24)
	add_child(l)
	l.position = Vector2(40, size.y - 80)
	get_tree().create_timer(2.5).timeout.connect(l.queue_free)

# ---------- Screens ----------
func _menu() -> void:
	_shown = "menu"
	var v := _page()
	v.add_child(_lbl("NIGHT SHIFT DORM", 48))
	v.add_child(_lbl("Sleep to earn coins. Wake to fix your door. Survive until dawn.", 22))
	v.add_child(_btn("LAN / Hotspot: Host", _host_lan))
	v.add_child(_btn("LAN / Hotspot: Find games", _lan_find))
	v.add_child(_btn("Online: Join server", _online))

func _host_lan() -> void:
	if Net.host("%s's room" % OS.get_model_name()):
		_reset_lobby()
		_on_state()
	else:
		_toast("Could not host (port in use?)")

func _lan_find() -> void:
	_shown = "find"
	var v := _page()
	v.add_child(_lbl("Games on this Wi-Fi / hotspot", 34))
	v.add_child(_lbl("Host: turn on your hotspot and tap Host. Everyone else: join that hotspot, then open this screen.", 20))
	room_list = VBoxContainer.new()
	v.add_child(room_list)
	v.add_child(_btn("Back", _back_menu))
	Net.start_search()
	_fill_rooms()

func _fill_rooms() -> void:
	if _shown != "find" or room_list == null:
		return
	for c in room_list.get_children():
		c.queue_free()
	if Net.rooms.is_empty():
		room_list.add_child(_lbl("Searching...", 26))
	for ip in Net.rooms:
		var r: Dictionary = Net.rooms[ip]
		room_list.add_child(_btn("%s  (%d players)" % [r.name, r.players], _join.bind(ip)))

func _back_menu() -> void:
	Net.stop_search()
	_menu()

func _online() -> void:
	_shown = "online"
	var v := _page()
	v.add_child(_lbl("Server address (IP or domain)", 34))
	ip_edit = LineEdit.new()
	ip_edit.text = _load_addr()
	ip_edit.placeholder_text = "e.g. 203.0.113.5"
	ip_edit.custom_minimum_size = Vector2(0, 80)
	ip_edit.add_theme_font_size_override("font_size", 28)
	v.add_child(ip_edit)
	v.add_child(_btn("Join", _join_typed))
	v.add_child(_lbl("Works for LAN too if auto-discovery is blocked.", 20))
	v.add_child(_btn("Back", _menu))

func _join_typed() -> void:
	var a := ip_edit.text.strip_edges()
	_save_addr(a)
	_join(a)

func _join(addr: String) -> void:
	Net.stop_search()
	if not Net.join(addr):
		_toast("Could not connect")
		return
	_shown = "connecting"
	var v := _page()
	v.add_child(_lbl("Connecting to %s ..." % addr, 32))
	v.add_child(_btn("Cancel", _leave))

func _leave() -> void:
	Net.leave()
	st = {"phase": "menu"}
	_menu()

func _on_net_failed() -> void:
	_leave()
	_toast("Connection failed or lost")

func _lobby() -> void:
	_shown = "lobby"
	var v := _page()
	v.add_child(_lbl("Lobby", 44))
	_hdr = _lbl("", 30)
	v.add_child(_hdr)
	v.add_child(_btn("Start night", _act.bind("start")))
	v.add_child(_btn("Leave", _leave))

func _game() -> void:
	_shown = "play"
	for c in ui.get_children():
		c.queue_free()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	ui.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 12)
	_hdr = _lbl("", 28)
	root.add_child(_hdr)
	var grid := HBoxContainer.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(grid)
	_panels.clear()
	_bars.clear()
	_rlabels.clear()
	for i in NROOMS:
		var p := PanelContainer.new()
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(p)
		var pv := VBoxContainer.new()
		p.add_child(pv)
		var l := _lbl("", 22)
		pv.add_child(l)
		var b := ProgressBar.new()
		b.custom_minimum_size = Vector2(0, 36)
		b.show_percentage = false
		pv.add_child(b)
		_panels.append(p)
		_rlabels.append(l)
		_bars.append(b)
	var row := HBoxContainer.new()
	root.add_child(row)
	var row2 := HBoxContainer.new()
	root.add_child(row2)
	_last_target = -1
	_last_night = 1
	_b_sleep = _btn("Sleep", _act.bind("sleep"))
	_b_repair = _btn("Repair door", _act.bind("repair"))
	_b_door = _btn("Door+", _act.bind("door"))
	_b_bed = _btn("Bed+", _act.bind("bed"))
	_b_salt = _btn("Salt", _act.bind("salt"))
	_b_light = _btn("Night-light", _act.bind("light"))
	row.add_child(_b_sleep)
	row.add_child(_b_repair)
	for b in [_b_door, _b_bed, _b_salt, _b_light]:
		row2.add_child(b)

func _end() -> void:
	_shown = "end"
	var v := _page()
	v.add_child(_lbl("DAWN - YOU SURVIVED" if st.phase == "win" else "THE GHOST WON", 44))
	v.add_child(_lbl(str(st.msg), 26))
	v.add_child(_btn("Back to lobby", _act.bind("again")))
	v.add_child(_btn("Leave", _leave))

# ---------- State -> UI ----------
func _on_state() -> void:
	if Net.dedicated:
		return
	match str(st.get("phase", "menu")):
		"lobby":
			if _shown != "lobby":
				_lobby()
			var t := ""
			for id in st.players:
				t += "%s%s\n" % [st.players[id], " (you)" if id == multiplayer.get_unique_id() else ""]
			_hdr.text = t
		"play":
			if _shown != "play":
				_game()
			_refresh_game()
		"win", "lose":
			if _shown != "end":
				_end()

func _my_room() -> int:
	for i in st.rooms.size():
		if st.rooms[i].pid == multiplayer.get_unique_id():
			return i
	return -1

func _refresh_game() -> void:
	if st.target != _last_target:
		if st.target >= 0:
			_play("warn")
		else:
			_play("hit")
			_shake = 0.25
		_last_target = st.target
	if st.night != _last_night:
		_play("dawn")
		_last_night = st.night
	var me := _my_room()
	var coins := 0
	var ghost := ""
	if st.target >= 0:
		ghost = "  %s at room %d!" % [str(st.gtype).to_upper(), st.target + 1]
	for i in NROOMS:
		var rm: Dictionary = st.rooms[i]
		var tag := "Empty"
		if rm.pid != 0:
			tag = ("YOU" if i == me else "Player")
			tag += (" - asleep" if rm.asleep else " - awake") if rm.alive else " - CAUGHT"
		_rlabels[i].text = "Room %d\n%s" % [i + 1, tag]
		_bars[i].max_value = rm.maxhp
		_bars[i].value = rm.hp
		_panels[i].modulate = Color(1, 0.35, 0.35) if i == st.target else (Color.WHITE if rm.alive else Color(0.45, 0.45, 0.45))
	var mine: Dictionary = {}
	if me >= 0:
		mine = st.rooms[me]
		coins = int(mine.coins)
	_hdr.text = "Night %d/%d   Dawn in %ds   Coins: %d%s" % [st.night, NIGHTS, ceili(st.t), coins, ghost]
	var ok: bool = me >= 0 and mine.alive
	_b_sleep.disabled = not ok
	_b_repair.disabled = not ok or mine.asleep or mine.cd > 0.0
	_b_door.disabled = not ok
	_b_bed.disabled = not ok
	_b_salt.disabled = not ok
	_b_light.disabled = not ok
	if me >= 0:
		_b_sleep.text = "Wake up" if mine.asleep else "Sleep (+coins)"
		_b_door.text = "Door+ (%d)" % (30 * (int(mine.lvl) + 1))
		_b_bed.text = "Bed+ (%d)" % (25 * (int(mine.bed) + 1))
		_b_salt.text = "Salt %d/5 (%d)" % [mine.salt, 50 * (int(mine.salt) + 1)]
		_b_light.text = "Light %d/5 (%d)" % [mine.light, 40 * (int(mine.light) + 1)]
	else:
		_b_sleep.text = "Spectating"

# ---------- Actions ----------
func _act(a: String) -> void:
	if multiplayer.is_server():
		_handle(1, a)
	else:
		rpc_id(1, "req", a)

@rpc("any_peer", "call_remote", "reliable")
func req(a: String) -> void:
	if multiplayer.is_server():
		_handle(multiplayer.get_remote_sender_id(), a)

@rpc("authority", "call_remote", "reliable")
func sync(s: Dictionary) -> void:
	st = s
	_on_state()

# ---------- Server logic ----------
func _on_peers() -> void:
	if not multiplayer.is_server():
		return
	if st.get("phase") == "lobby":
		_reset_lobby()
	else:
		_push()

func _reset_lobby() -> void:
	var ids: Array = []
	if not Net.dedicated:
		ids.append(1)
	for p in multiplayer.get_peers():
		ids.append(p)
	ids.sort()
	var pl := {}
	for i in ids.size():
		pl[ids[i]] = "Player %d" % (i + 1)
	st = {"phase": "lobby", "t": NIGHT_TIME, "rooms": [], "target": -1, "players": pl, "msg": "", "night": 1, "gtype": ""}
	_push()

func _push() -> void:
	_sync_acc = 0.0
	if multiplayer.get_peers().size() > 0:
		rpc("sync", st)
	_on_state()

func _start() -> void:
	var ids: Array = st.players.keys()
	ids.sort()
	var rooms: Array = []
	for i in NROOMS:
		var pid: int = ids[i] if i < ids.size() else 0
		rooms.append({"pid": pid, "hp": 100.0, "maxhp": 100.0, "lvl": 0, "bed": 0,
			"asleep": false, "alive": pid != 0, "coins": 0.0, "cd": 0.0, "salt": 0, "light": 0})
	st.rooms = rooms
	st.phase = "play"
	st.t = NIGHT_TIME
	st.target = -1
	st.night = 1
	st.gtype = ""
	_ghost_t = 4.0
	_push()

func _handle(id: int, a: String) -> void:
	if a == "start" and st.phase == "lobby":
		_start()
		return
	if a == "again" and (st.phase == "win" or st.phase == "lose"):
		_reset_lobby()
		return
	if st.phase != "play":
		return
	var r := -1
	for i in st.rooms.size():
		if st.rooms[i].pid == id:
			r = i
	if r < 0:
		return
	var rm: Dictionary = st.rooms[r]
	if not rm.alive:
		return
	match a:
		"sleep":
			rm.asleep = not rm.asleep
		"repair":
			if not rm.asleep and rm.cd <= 0.0:
				rm.hp = minf(rm.maxhp, rm.hp + 14.0)
				rm.cd = 0.4
		"door":
			var c: int = 30 * (int(rm.lvl) + 1)
			if rm.coins >= c:
				rm.coins -= c
				rm.lvl += 1
				rm.maxhp += 40.0
				rm.hp += 40.0
		"bed":
			var c2: int = 25 * (int(rm.bed) + 1)
			if rm.coins >= c2:
				rm.coins -= c2
				rm.bed += 1
		"salt":
			var c3: int = 50 * (int(rm.salt) + 1)
			if rm.salt < 5 and rm.coins >= c3:
				rm.coins -= c3
				rm.salt += 1
		"light":
			var c4: int = 40 * (int(rm.light) + 1)
			if rm.light < 5 and rm.coins >= c4:
				rm.coins -= c4
				rm.light += 1
	_push()

func _process(d: float) -> void:
	if _shake > 0.0:
		_shake -= d
		ui.position = Vector2(randf_range(-10, 10), randf_range(-10, 10)) if _shake > 0.0 else Vector2.ZERO
	if Net.hosting and multiplayer.is_server() and st.get("phase") == "play":
		_tick(d)

func _tick(d: float) -> void:
	st.t -= d
	var elapsed: float = NIGHT_TIME - st.t
	var any_alive := false
	for rm in st.rooms:
		if rm.pid == 0 or not rm.alive:
			continue
		if rm.pid != 1 and not multiplayer.get_peers().has(rm.pid):
			rm.alive = false
			continue
		any_alive = true
		rm.cd = maxf(0.0, rm.cd - d)
		if rm.asleep:
			rm.coins += d * (2.0 + 1.5 * rm.bed)
		rm.hp = minf(rm.maxhp, rm.hp + d * 1.5 * rm.light)
	if not any_alive:
		st.phase = "lose"
		st.msg = "The ghost got everyone."
		_push()
		return
	if st.t <= 0.0:
		if st.night >= NIGHTS:
			st.phase = "win"
			st.msg = "You survived all %d nights!" % NIGHTS
		else:
			st.night += 1
			st.t = NIGHT_TIME
			st.target = -1
			_ghost_t = 4.0
			for rm2 in st.rooms:
				if rm2.pid != 0:
					rm2.alive = true
					rm2.hp = rm2.maxhp
					rm2.asleep = false
					rm2.coins += 40.0
		_push()
		return
	_ghost_t -= d
	if _ghost_t <= 0.0:
		if st.target < 0:
			var c: Array = []
			for i in st.rooms.size():
				if st.rooms[i].alive:
					c.append(i)
			st.target = c.pick_random()
			var pool := ["Poltergeist"]
			if st.night >= 2:
				pool.append("Brute")
			if st.night >= 3:
				pool.append("Wraith")
			st.gtype = pool.pick_random()
			_ghost_t = 1.0
		else:
			var rm: Dictionary = st.rooms[st.target]
			var dmg: float = (8.0 + elapsed / 6.0) * (1.0 + 0.35 * (st.night - 1))
			var gap: float = maxf(1.0, 3.0 - elapsed / 60.0)
			match st.gtype:
				"Poltergeist":
					dmg *= 0.6
					gap *= 0.5
				"Brute":
					dmg *= 1.8
					gap *= 1.3
				"Wraith":
					if rm.asleep:
						dmg *= 1.6
			dmg *= maxf(0.4, 1.0 - 0.12 * rm.salt)
			rm.hp -= dmg
			if rm.hp <= 0.0:
				rm.hp = 0.0
				rm.alive = false
				rm.asleep = false
			st.target = -1
			_ghost_t = gap
	_sync_acc += d
	if _sync_acc >= 0.15:
		_push()

# ---------- Saved server address ----------
func _load_addr() -> String:
	var c := ConfigFile.new()
	c.load("user://s.cfg")
	return str(c.get_value("net", "addr", ""))

func _save_addr(a: String) -> void:
	var c := ConfigFile.new()
	c.set_value("net", "addr", a)
	c.save("user://s.cfg")

# ---------- Procedural sound (no audio files needed) ----------
func _tone(freq: float, dur: float, vol := 0.4) -> AudioStreamWAV:
	var n := int(22050 * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := 1.0 - float(i) / n
		data.encode_s16(i * 2, int(sin(TAU * freq * i / 22050.0) * env * vol * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 22050
	w.data = data
	return w

func _play(n: String) -> void:
	if not _snd.has(n):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _snd[n]
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)
