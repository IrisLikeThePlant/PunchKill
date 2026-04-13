extends Node

const PORT := 8787
const MAX_PEERS := 2

signal connected_to_server
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal connection_failed
signal server_ready

var peer : ENetMultiplayerPeer = null
var local_peer_id := 1

func host() -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PEERS)
	assert(err == OK, "Failed to create server: %s" % err)
	multiplayer.multiplayer_peer = peer
	local_peer_id = 1
	print("Hosting on port %d" % PORT)
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	
func join(address: String) -> void:
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, PORT)
	assert(err == OK, "Failed to join server: %s" % err)
	multiplayer.multiplayer_peer = peer
	
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	print("Joining server %s:%d" % [address, PORT])
	
func _on_connected_to_server() -> void:
	local_peer_id = multiplayer.get_unique_id()
	print("Connected. Peer id: %d" % local_peer_id)
	emit_signal("connected_to_server")

func _on_connection_failed() -> void:
	print("Connection failed.")
	return

func _on_peer_connected(id: int) -> void:
	print("Peer connected: %d" % id)
	emit_signal("peer_connected", id)
	if multiplayer.is_server():
		emit_signal("server_ready")

func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: %d" % id)
	emit_signal("peer_disconnected", id)

func is_host() -> bool:
	return multiplayer.is_server()
	
func get_opponent_id() -> int:
	for id in multiplayer.get_peers():
		return id
	return -1
