extends Node
@export var offline_mode : bool = true

@onready var fighter1 : Fighter_Online = $Fighter1
@onready var fighter2 : Fighter_Online = $Fighter2

@onready var f1_hp: ProgressBar = $"../UI/F1_HP"
@onready var f1_charge: ProgressBar = $"../UI/F1_Charge"
@onready var f2_hp: ProgressBar = $"../UI/F2_HP"
@onready var f2_charge: ProgressBar = $"../UI/F2_Charge"

@onready var f1_visuals: Node3D = $"../Visuals/F1"
@onready var f2_visuals: Node3D = $"../Visuals/F2"


const P1_Action := "p1_charge"
const P2_Action := "p2_charge"

const COLOR_NORMAL    := Color(0.2, 0.6, 1.0)
const COLOR_SWEETSPOT := Color(1.0, 0.2, 0.1)

var game_active := false
var local_player := 0

var display_charge_start : Dictionary = {1: -1.0, 2: -1.0}

var release_times := {1: -999.0, 2: -999.0}
var consumed_as_parry := {1: false, 2: false}

func _ready() -> void:
	game_active = true
	if Network.is_host():
		local_player = 1
		call_deferred("_assign_players")
	
	fighter1.player_id = 1
	fighter2.player_id = 2
	
	fighter1.hp_changed.connect(_on_hp_changed)
	fighter2.hp_changed.connect(_on_hp_changed)
	fighter1.state_changed.connect(_on_state_changed)
	fighter2.state_changed.connect(_on_state_changed)
	fighter1.hit_landed.connect(_on_hit_landed)
	fighter2.hit_landed.connect(_on_hit_landed)
	
	Network.server_ready.connect(_on_server_ready)
	Network.connected_to_server.connect(_on_connected_to_server)
	Network.peer_disconnected.connect(_on_peer_disconnected)

func _on_server_ready() -> void:
	var client_id := Network.get_opponent_id()
	_rpc_assign_player.rpc_id(client_id, 2)
	local_player = 1
	_start_game()
	
func _on_connected_to_server() -> void:
	print("Connected to server. Waiting for host to start the game")
	
func _assign_players() -> void:
	var client_id := Network.get_opponent_id()
	_rpc_assign_player.rpc_id(client_id, 2)

@rpc("authority", "call_remote", "reliable")	
func _rpc_assign_player(pid: int) -> void:
	local_player = pid
	print("Assigned local player id %d" % pid)

func _start_game() -> void:
	game_active = true
	_rpc_start_game.rpc()
	
@rpc("authority", "call_remote", "reliable")
func _rpc_start_game() -> void:
	game_active = true
	print("Game started")

func _on_peer_disconnected(id: int) -> void:
	game_active = false
	print("Opponent disconnected")



func _input(event: InputEvent) -> void:
	if not game_active or local_player == 0:
		return

	var action := P1_Action if local_player == 1 else P2_Action
	
	if offline_mode:
		if event.is_action_pressed("p1_charge"):
			_send_charge_begin_for(1)
		elif event.is_action_released("p1_charge"):
			_send_charge_release_for(1)
		if event.is_action_pressed("p2_charge"):
			_send_charge_begin_for(2)
		elif event.is_action_released("p2_charge"):
			_send_charge_release_for(2)
	else:
		if event.is_action_pressed(action):
			_send_charge_begin()
		elif event.is_action_released(action):
			_send_charge_release()

func _send_charge_begin_for(pid: int) -> void:
	_on_charge_begun(pid)
	if Network.is_host():
		_host_receive_begin(pid)
		_rpc_notify_begin.rpc(pid)
	else:
		_rpc_begin.rpc_id(1, pid)

func _send_charge_release_for(pid: int) -> void:
	if Network.is_host():
		_host_receive_release(pid)
		_rpc_notify_release.rpc(pid)
	else:
		_rpc_release.rpc_id(1, pid)
		
func _send_charge_begin() -> void:
	_send_charge_begin_for(local_player)
	
func _send_charge_release() -> void:
	_send_charge_release_for(local_player)

func _on_charge_begun(pid: int) -> void:
	display_charge_start[pid] = _now()
	set_charge(pid, 0.0)
	set_stunned(pid, false)

func _on_charge_ended(pid: int) -> void:
	display_charge_start[pid] = -1.0
	set_charge(pid, 0.0)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_begin(pid: int) -> void:
	_on_charge_begun(pid)
	_host_receive_begin(pid)
	
@rpc("authority", "call_remote", "reliable")
func _rpc_notify_begin(pid: int) -> void:
	_on_charge_begun(pid)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_release(pid: int) -> void:
	_host_receive_release(pid)
	
@rpc("authority", "call_remote", "reliable")
func _rpc_notify_release(pid: int) -> void:
	_on_charge_ended(pid)



func _host_receive_begin(pid: int) -> void:
	assert(Network.is_host())
	var f := _get_fighter(pid)
	if f.state != Fighter_Online.State.IDLE:
		return
	f.host_begin_charge(_now())
	_rpc_sync_state.rpc(pid, Fighter_Online.State.CHARGING, f.hp)

func _host_receive_release(pid: int) -> void:
	assert(Network.is_host())
	var attacker := _get_fighter(pid)
	var defender := _get_fighter(_other(pid))

	if attacker.state != Fighter_Online.State.CHARGING:
		return

	var now := _now()
	var held := attacker.charge_held(now)
	var opponent_release: float = release_times[_other(pid)]
	var is_parry := (now - opponent_release) <= Fighter_Online.PARRY_WINDOW and defender.state == Fighter_Online.State.IDLE

	release_times[pid] = now
	attacker.charge_start_time = -1.0
	attacker.apply_idle()
	_rpc_sync_state.rpc(pid, Fighter_Online.State.IDLE, attacker.hp)

	if is_parry:
		consumed_as_parry[_other(pid)] = true
		_apply_hit(pid, Fighter_Online.DMG_PARRY, "parry", defender)
		_rpc_sync_hit.rpc(pid, Fighter_Online.DMG_PARRY, "parry", defender.hp)
		return
		
	if consumed_as_parry[pid]:
		consumed_as_parry[pid] = false
		return
		
	if held >= Fighter_Online.SWEET_SPOT_START and held <= Fighter_Online.SWEET_SPOT_END:
		_apply_hit(pid, Fighter_Online.DMG_SWEET_SPOT, "sweet", defender)
		_rpc_sync_hit.rpc(pid, Fighter_Online.DMG_SWEET_SPOT, "sweet", defender.hp)
	else:
		var dmg := attacker.normal_damage(held)
		_apply_hit(pid, dmg, "normal", defender)
		_rpc_sync_hit.rpc(pid, dmg, "normal", defender.hp)

	_rpc_sync_state.rpc(pid, Fighter_Online.State.IDLE, attacker.hp)

func _host_check_overcharges() -> void:
	if not Network.is_host() or not game_active:
		return
	for pid in [1, 2]:
		var f := _get_fighter(pid)
		if f.host_check_overcharge(_now()):
			_rpc_sync_stun.rpc(pid)

func _apply_hit(attacker_id: int, dmg: float, hit_type: String, defender: Node) -> void:
	defender.apply_damage(dmg)
	emit_signal_hit(attacker_id, dmg, hit_type)
	if defender.hp <= 0.0:
		_rpc_game_over.rpc(_other(attacker_id))

func emit_signal_hit(attacker_id: int, dmg: float, hit_type: String) -> void:
	print("P%d landed %s for %.1f" % [attacker_id, hit_type, dmg])
	
	
@rpc("authority", "call_local", "reliable")
func _rpc_sync_state(pid: int, new_state: Fighter_Online.State, hp: float) -> void:
	var f := _get_fighter(pid)
	f.state = new_state
	f.hp = hp
	if new_state != Fighter_Online.State.CHARGING:
		_on_charge_ended(pid)

@rpc("authority", "call_local", "reliable")
func _rpc_sync_hit(attacker_id: int, dmg: float, hit_type: String, defender_hp: float) -> void:
	var defender := _get_fighter(_other(attacker_id))
	defender.hp = defender_hp
	defender.emit_signal("hp_changed", defender.player_id, defender_hp)
	defender.emit_signal("hit_landed", attacker_id, dmg, hit_type)
	print("P%d → %s %.1f dmg" % [attacker_id, hit_type, dmg])

@rpc("authority", "call_local", "reliable")
func _rpc_sync_stun(pid: int) -> void:
	_get_fighter(pid).apply_stun()
	print("P%d overcharged → stunned" % pid)

@rpc("authority", "call_local", "reliable")
func _rpc_game_over(loser_id: int) -> void:
	game_active = false
	print("Player %d wins!" % _other(loser_id))
	
	
	
func _process(_delta: float) -> void:
	_host_check_overcharges()
	
	for pid in [1, 2]:
		var started: float = display_charge_start[pid]
		if started >= 0.0:
			set_charge(pid, _now() - started)
	
	
	
	

func _get_fighter(pid: int) -> Fighter_Online:
	return fighter1 if pid == 1 else fighter2

func _other(pid: int) -> int:
	return 2 if pid == 1 else 1

func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

func _on_hp_changed(pid: int, hp: float) -> void:
	print("P%d HP: %.1f" % [pid, hp])
	set_hp(pid, hp)

func _on_state_changed(pid: int, s: Fighter_Online.State) -> void:
	match s:
		Fighter_Online.State.STUNNED:
			set_stunned(pid, true)
			set_charge(pid, 0.0)
			set_animation(pid, "Stunned_001")
		Fighter_Online.State.IDLE:
			set_stunned(pid, false)
			set_charge(pid, 0.0)
			set_animation(pid, "Idle_001")
		Fighter_Online.State.CHARGING:
			set_stunned(pid, false)
			set_animation(pid, "Charge_001")

func _on_hit_landed(attacker_id: int, dmg: float, hit_type: String) -> void:
	pass


func set_hp(pid: int, value: float) -> void:
	var hp_bar := f1_hp if pid == 1 else f2_hp
	hp_bar.value = value

func set_charge(pid: int, held: float) -> void:
	var charge_bar := f1_charge if pid == 1 else f2_charge
	charge_bar.value = clamp(held / Fighter_Online.OVERCHARGE_TIME, 0.0, 1.0)
	
	var color : Color
	if held >= Fighter_Online.SWEET_SPOT_START and held < Fighter_Online.SWEET_SPOT_END:
		color = COLOR_SWEETSPOT
	else:
		color = COLOR_NORMAL

	var style = charge_bar.get_theme_stylebox("fill").duplicate()
	if style is StyleBoxFlat:
		style.bg_color = color
		charge_bar.add_theme_stylebox_override("fill", style)

func set_stunned(pid: int, is_stunned: bool) -> void:
	var charge_bar := f1_charge if pid == 1 else f2_charge
	charge_bar.modulate = Color(0.5, 0.5, 0.5) if is_stunned else Color.WHITE
	
func set_animation(pid: int, animation_name: String) -> void:
	var visuals := f1_visuals if pid == 1 else f2_visuals
	var player := visuals.get_node("AnimationPlayer") as AnimationPlayer
	var animation_name_combined = "moves/" + animation_name
	player.play(animation_name_combined)
