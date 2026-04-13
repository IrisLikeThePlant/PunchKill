extends Control

@onready var offline: Button = $Offline
@onready var host: Button = $Host
@onready var join: Button = $Join
@onready var address: LineEdit = $Address

func _ready() -> void:
	address.placeholder_text = "Enter IP address"

	offline.pressed.connect(_on_offline_pressed)
	host.pressed.connect(_on_host_pressed)
	join.pressed.connect(_on_join_pressed)
	
	Network.server_ready.connect(_on_server_ready)
	
func _on_offline_pressed() -> void:
	get_tree().change_scene_to_file("res://root.tscn")
	
func _on_host_pressed() -> void:
	offline.disabled = true
	host.disabled = true
	join.disabled = true
	Network.host()

func _on_join_pressed() -> void:
	offline.disabled = true
	host.disabled = true
	join.disabled = true
	Network.join(address.text.strip_edges())

func _on_server_ready() -> void:
	rpc_load_game.rpc()

@rpc("authority", "call_local", "reliable")
func rpc_load_game() -> void:
	get_tree().change_scene_to_file("res://root_online.tscn")
