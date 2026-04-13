extends Node
class_name Fighter_Online

const MAX_CHARGE: float = 3.0
const SWEET_SPOT_START: float = 2.9 
const SWEET_SPOT_END: float = 3.0
const OVERCHARGE_TIME: float = 3.0 
const STUN_DURATION: float = 1.5
const PARRY_WINDOW: float = 0.1 

const DMG_NORMAL_MIN: float = 1.0
const DMG_NORMAL_MAX: float = 25.0
const DMG_SWEET_SPOT: float = 999.0
const DMG_PARRY: float = 50.0 # should be higher between own charge and enemy charge


enum State { IDLE, CHARGING, STUNNED, DEAD }

var state: State = State.IDLE
var stun_timer: float = 0.0
var hp: float = 100.0

var charge_start_time := -1.0
var last_release_time := -999.0

signal hp_changed(player_id, new_hp)
signal state_changed(player_id, new_state)
signal hit_landed(attacker_id, damage, hit_type)

var player_id: int = 0


func _process(delta: float) -> void:
	if state == State.STUNNED:
		stun_timer -= delta
		if stun_timer <= 0.0:
			_set_state(State.IDLE)
			
func host_begin_charge(server_time: float) -> void:
	if state != State.IDLE:
		return
	charge_start_time = server_time
	_set_state(State.CHARGING)
	
func host_check_overcharge(server_time: float) -> bool:
	if state != State.CHARGING:
		return false
	if server_time - charge_start_time > OVERCHARGE_TIME:
		charge_start_time = -1.0
		_enter_stun()
		return true
	return false
	
func charge_held(server_time: float) -> float:
	if charge_start_time < 0.0:
		return 0.0
	return server_time - charge_start_time
	
func apply_damage(amount: float) -> void:
	hp = max(0.0, hp - amount)
	emit_signal("hp_changed", player_id, hp)
	if hp == 0.0:
		_set_state(State.DEAD)

func apply_stun() -> void:
	_enter_stun()
	
func apply_idle() -> void:
	_set_state(State.IDLE)

func mark_released(server_time: float) -> void:
	last_release_time = server_time
	
func is_released_within_parry_window(server_time: float) -> bool:
	return (server_time - last_release_time) <= PARRY_WINDOW
	
func _enter_stun() -> void:
	stun_timer = STUN_DURATION
	_set_state(State.STUNNED)

func _set_state(s: State) -> void:
	state = s
	emit_signal("state_changed", player_id, s)
	

func normal_damage(held: float) -> float:
	if held < SWEET_SPOT_START:
		return lerp(0.0, DMG_NORMAL_MAX, held / SWEET_SPOT_START)
	else:
		var ratio :float= clamp((held - SWEET_SPOT_END) / (OVERCHARGE_TIME - SWEET_SPOT_END), 0.0, 1.0)
		return lerp(DMG_NORMAL_MAX, DMG_NORMAL_MIN, ratio)
