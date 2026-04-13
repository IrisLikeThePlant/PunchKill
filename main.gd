extends Node

@onready var fighter1: Node = $Fighter1
@onready var fighter2: Node = $Fighter2

@onready var f1_hp: ProgressBar = $"../UI/F1_HP"
@onready var f1_charge: ProgressBar = $"../UI/F1_Charge"
@onready var f2_hp: ProgressBar = $"../UI/F2_HP"
@onready var f2_charge: ProgressBar = $"../UI/F2_Charge"

const P1_Action := "p1_charge"
const P2_Action := "p2_charge"

var game_over: bool = false

func _ready() -> void:
	fighter1.player_id = 1
	fighter2.player_id = 2
	fighter1.opponent = fighter2
	fighter2.opponent = fighter1
	
	fighter1.hp_changed.connect(_on_hp_changed)
	fighter2.hp_changed.connect(_on_hp_changed)
	fighter1.state_changed.connect(_on_state_changed)
	fighter2.state_changed.connect(_on_state_changed)
	fighter1.hit_landed.connect(_on_hit_landed)
	fighter2.hit_landed.connect(_on_hit_landed)
	
	f1_hp.value = 100.0
	f2_hp.value = 100.0
	f1_charge.value = 0.0
	f2_charge.value = 0.0
	
func _input(event: InputEvent) -> void:
	if game_over:
		return
	
	if event.is_action_pressed(P1_Action):
		fighter1.begin_charge()
	elif event.is_action_released(P1_Action):
		fighter1.release()
		
	if event.is_action_pressed(P2_Action):
		fighter2.begin_charge()
	elif event.is_action_released(P2_Action):
		fighter2.release()
		
func _on_hp_changed(player_id: int, new_hp: float) -> void:
	print("P%d HP: %.1f" % [player_id, new_hp])
	if player_id == 1:
		f1_hp.value = new_hp
	else:
		f2_hp.value = new_hp
	
	if new_hp <= 0.0:
		_end_game(player_id)

func _on_state_changed(player_id: int, new_state, charge_ratio: float) -> void:
	if player_id == 1:
		f1_charge.value = charge_ratio
	else:
		f2_charge.value = charge_ratio
	
func _on_hit_landed(attacker_id: int, damage: float, hit_type: String) -> void:
	print("P%d hit! type=%s dmg=%.1f" % [attacker_id, hit_type, damage])

func _end_game(loser_id: int) -> void:
	game_over = true
	var winner := 2 if loser_id == 1 else 1
	print("Player %d wins!" % winner)
