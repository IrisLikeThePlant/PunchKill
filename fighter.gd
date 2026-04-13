extends Node


const MAX_CHARGE: float = 3.0
const SWEET_SPOT_START: float = 2.8 
const SWEET_SPOT_END: float = 3.0
const OVERCHARGE_TIME: float = 3.0 
const STUN_DURATION: float = 1.5
const PARRY_WINDOW: float = 0.2 

const DMG_NORMAL_MIN: float = 1.0
const DMG_NORMAL_MAX: float = 25.0
const DMG_SWEET_SPOT: float = 999.0
const DMG_PARRY: float = 50.0


enum State { IDLE, CHARGING, STUNNED, DEAD }

var state: State = State.IDLE
var charge_time: float = 0.0
var stun_timer: float = 0.0
var hp: float = 100.0

var player_id: int 
var opponent: Node 


var opponent_just_released: bool = false
var opponent_release_timer: float = 0.0

signal hp_changed(player_id, new_hp)
signal state_changed(player_id, new_state, charge_ratio)
signal hit_landed(attacker_id, damage, hit_type)


func _process(delta: float) -> void:
	if opponent_just_released:
		opponent_release_timer -= delta
		if opponent_release_timer <= 0.0:
			opponent_just_released = false

	match state:
		State.CHARGING:
			charge_time += delta
			emit_signal("state_changed", player_id, state, charge_time)

			if charge_time >= OVERCHARGE_TIME:
				_enter_stun()

		State.STUNNED:
			stun_timer -= delta
			if stun_timer <= 0.0:
				state = State.IDLE
				emit_signal("state_changed", player_id, State.IDLE, 0.0)

func begin_charge() -> void:
	if state != State.IDLE:
		return
	charge_time = 0.0
	state = State.CHARGING
	emit_signal("state_changed", player_id, state, 0.0)

func release() -> void:
	if state != State.CHARGING:
		return

	if opponent != null and opponent_just_released:
		_do_parry()
		return

	var held := charge_time

	if held >= SWEET_SPOT_START and held < SWEET_SPOT_END:
		_land_hit(DMG_SWEET_SPOT, "sweet")
	else:
		var ratio: float = clamp(held / SWEET_SPOT_START, 0.0, 1.0)
		var dmg: float = lerp(0.0, DMG_NORMAL_MAX, ratio)
		_land_hit(dmg, "normal")

	charge_time = 0.0
	state = State.IDLE
	emit_signal("state_changed", player_id, State.IDLE, 0.0)
	
	if opponent != null:
		opponent.notify_opponent_released()


func notify_opponent_released() -> void:
	opponent_just_released = true
	opponent_release_timer = PARRY_WINDOW

func _land_hit(damage: float, hit_type: String) -> void:
	if opponent == null:
		return
	if opponent.state == State.DEAD:
		return
	opponent._take_damage(damage)
	emit_signal("hit_landed", player_id, damage, hit_type)
	
func _do_parry() -> void:
	opponent_just_released = false
	charge_time = 0.0
	state = State.IDLE
	emit_signal("state_changed", player_id, State.IDLE, 0.0)
	if opponent != null:
		opponent._take_damage(DMG_PARRY)
	emit_signal("hit_landed", player_id, DMG_PARRY, "parry")

func _enter_stun() -> void:
	charge_time = 0.0
	state = State.STUNNED
	stun_timer = STUN_DURATION
	emit_signal("state_changed", player_id, State.STUNNED, 0.0)

func _take_damage(amount: float) -> void:
	if state == State.DEAD:
		return
	hp = max(0.0, hp - amount)
	emit_signal("hp_changed", player_id, hp)
	if hp <= 0.0:
		state = State.DEAD
		emit_signal("state_changed", player_id, State.DEAD, 0.0)

func charge_ratio() -> float:
	return clamp(charge_time / MAX_CHARGE, 0.0, 1.0)

func is_in_sweet_spot() -> bool:
	return state == State.CHARGING and charge_time >= SWEET_SPOT_START and charge_time < SWEET_SPOT_END
