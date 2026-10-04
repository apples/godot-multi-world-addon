extends Node
class_name WorldMembershipManager

## Tracks which peers are members of which worlds. Replicated to all peers.
##
## Only the authority (the server) may change memberships; changes are applied on every peer
## through reliable RPCs. A peer can be a member of several worlds at once. The most recently
## joined world is the peer's "current" world.

signal peer_left_world(peer_id: int, world_key: String)
signal peer_joined_world(peer_id: int, world_key: String, params: Variant)
## Emitted after a peer's current world (the most recently joined one) changes.
## `new_world_key` is empty if the peer is no longer in any world.
signal peer_current_world_changed(peer_id: int, old_world_key: String, new_world_key: String)

## The most recently readied manager. Convenient for code that has no better way to find it.
static var current: WorldMembershipManager

## Each entry has `peer_id`, `world_key` and `params`, in join order.
var memberships: Array[Dictionary]

var _current_world_keys: Dictionary[int, String]


func _ready() -> void:
	current = self
	
	# might be unnecessary, but is correct
	MultiWorldLog.log("%s._ready(): memberships = %s" % [self, memberships])
	for m in memberships:
		peer_joined_world.emit(m.peer_id, m.world_key, m.params)
		_update_current_world(m.peer_id)


## Server only. Adds the peer to the world, keeping its other memberships.
func add_peer_to_world(peer_id: int, world_key: String, params: Variant) -> void:
	if not is_multiplayer_authority():
		push_error("Must be authority!")
		return
	
	_add_peer_to_world_rpc.rpc(peer_id, world_key, params)


## Server only. Removes the peer from the world.
func remove_peer_from_world(peer_id: int, world_key: String) -> void:
	if not is_multiplayer_authority():
		push_error("Must be authority!")
		return
	
	_remove_peer_from_world_rpc.rpc(peer_id, world_key)


## Server only. Removes the peer from all its worlds, then adds it to the given one.
func move_peer_to_world(peer_id: int, world_key: String, params: Variant) -> void:
	var peer_memberships: Array[Dictionary] = _get_memberships_for_peer(peer_id)
	peer_memberships.reverse()
	
	for m in peer_memberships:
		remove_peer_from_world(peer_id, m.world_key)
	
	add_peer_to_world(peer_id, world_key, params)


## Server only. Removes the peer from all its worlds (e.g. when it disconnects).
func erase_peer(peer_id: int) -> void:
	var peer_memberships: Array[Dictionary] = _get_memberships_for_peer(peer_id)
	peer_memberships.reverse()
	
	for m in peer_memberships:
		remove_peer_from_world(peer_id, m.world_key)


## Returns the keys of all worlds the peer is in, in join order.
func get_peer_world_keys(peer_id: int) -> PackedStringArray:
	return _get_memberships_for_peer(peer_id).map(func (m): return m.world_key)


## Returns the key of the most recently joined world of the peer, or "" if it is in none.
func get_peer_current_world_key(peer_id: int) -> String:
	var world_keys := get_peer_world_keys(peer_id)
	return world_keys[-1] if world_keys else ""


## Returns the peers in the world, in join order. The first one is the world's authority.
func get_world_peers(world_key: String) -> PackedInt64Array:
	return _get_memberships_for_world(world_key).map(func (m): return m.peer_id)


## Returns the params the peer joined the world with, or null.
func get_params_for(peer_id: int, world_key: String) -> Variant:
	for m in memberships:
		if m.peer_id == peer_id and m.world_key == world_key:
			return m.params
	return null


func _get_memberships_for_peer(peer_id: int) -> Array[Dictionary]:
	return memberships.filter(func (m): return m.peer_id == peer_id)


func _get_memberships_for_world(world_key: String) -> Array[Dictionary]:
	return memberships.filter(func (m): return m.world_key == world_key)


func _update_current_world(peer_id: int) -> void:
	var old_key: String = _current_world_keys.get(peer_id, "")
	var new_key := get_peer_current_world_key(peer_id)
	
	if new_key == "":
		_current_world_keys.erase(peer_id)
	else:
		_current_world_keys[peer_id] = new_key
	
	if new_key != old_key:
		peer_current_world_changed.emit(peer_id, old_key, new_key)


@rpc("authority", "call_local", "reliable")
func _add_peer_to_world_rpc(peer_id: int, world_key: String, params: Variant) -> void:
	MultiWorldLog.log("World membership added: (%s, %s, %s)" % [peer_id, world_key, params])
	
	var existing = memberships.find_custom(func (m): return m.peer_id == peer_id and m.world_key == world_key)
	if existing != -1:
		push_error("Tried to join world twice.")
		return
	
	memberships.append({
		"peer_id": peer_id,
		"world_key": world_key,
		"params": params,
	})
	MultiWorldLog.log("World memberships: %s" % [memberships])
	
	peer_joined_world.emit(peer_id, world_key, params)
	_update_current_world(peer_id)


@rpc("authority", "call_local", "reliable")
func _remove_peer_from_world_rpc(peer_id: int, world_key: String) -> void:
	MultiWorldLog.log("World membership removed: (%s, %s)" % [peer_id, world_key])
	
	var existing = memberships.find_custom(func (m): return m.peer_id == peer_id and m.world_key == world_key)
	if existing == -1:
		push_error("Peer not in world.")
		return
	
	memberships.remove_at(existing)
	MultiWorldLog.log("World memberships: %s" % [memberships])
	
	peer_left_world.emit(peer_id, world_key)
	_update_current_world(peer_id)
