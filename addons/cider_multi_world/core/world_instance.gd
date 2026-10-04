extends Node
class_name WorldInstance

## A single world, as seen by one peer.
##
## Created by [MultiWorld] on every peer. The peer that is elected as the world's authority
## (the longest-standing member) instantiates the [WorldViewport], which is replicated to the
## other members. When the authority leaves, the next member takes over.

## Emitted when this peer has a [member world_viewport] available (spawned locally or remotely).
signal world_spawned()

## Game-defined world type, interpreted by the [WorldFactory].
@export var world_type: String
## Unique key of this world.
@export var world_key: String
## Game-defined parameters, interpreted by the [WorldFactory].
@export var params: Dictionary

var world_viewport: WorldViewport

var _cached_authority_peer_id: int = 0

var _authority_observers: Array[WorldAuthorityObserver]
var _world_synchronizers: Array[WorldVisibleMultiplayerSynchronizer]

@onready var multi_world: MultiWorld = get_parent()
@onready var world_viewport_multiplayer_spawner: MultiplayerSpawner = %WorldViewportMultiplayerSpawner


## Returns the WorldInstance that `node` is inside of, or null.
static func find(node: Node) -> WorldInstance:
	while node:
		if node is WorldInstance:
			return node
		node = node.get_parent()
	return null


func _ready() -> void:
	world_viewport_multiplayer_spawner.spawn_function = _spawn_function
	var membership := get_membership_manager()
	membership.peer_joined_world.connect(_on_peer_joined_world)
	membership.peer_left_world.connect(_on_peer_left_world)


func get_membership_manager() -> WorldMembershipManager:
	return (get_parent() as MultiWorld).membership_manager


## Returns the peer id that is currently the authority (host) of this world.
func get_world_authority() -> int:
	return _cached_authority_peer_id


func register_authority_observer(wao: WorldAuthorityObserver) -> void:
	assert(wao not in _authority_observers)
	_authority_observers.append(wao)


func unregister_authority_observer(wao: WorldAuthorityObserver) -> void:
	assert(wao in _authority_observers)
	_authority_observers.erase(wao)


func register_synchronizer(sync: WorldVisibleMultiplayerSynchronizer) -> void:
	assert(sync not in _world_synchronizers)
	_world_synchronizers.append(sync)


func unregister_synchronizer(sync: WorldVisibleMultiplayerSynchronizer) -> void:
	assert(sync in _world_synchronizers)
	_world_synchronizers.erase(sync)


func _on_peer_joined_world(peer_id: int, p_world_key: String, _params: Variant) -> void:
	if p_world_key != world_key:
		return
	
	var old_authority = _cached_authority_peer_id
	var new_authority = _get_world_authority_nocache()
	
	if old_authority != new_authority:
		MultiWorldLog.log("World authority changed: %s: %s -> %s" % [p_world_key, _cached_authority_peer_id, new_authority])
		_cached_authority_peer_id = new_authority
		_authority_notify(new_authority)
	
	if world_viewport == null and new_authority == multiplayer.get_unique_id():
		assert(old_authority == 0)
		_instantiate_world()
	
	_join_notify(peer_id)
	
	if world_viewport:
		world_viewport.player_joined(peer_id)


func _on_peer_left_world(peer_id: int, p_world_key: String) -> void:
	if p_world_key != world_key:
		return
	
	var new_authority = _get_world_authority_nocache()
	
	if _cached_authority_peer_id != new_authority:
		MultiWorldLog.log("World authority changed: %s: %s -> %s" % [p_world_key, _cached_authority_peer_id, new_authority])
		_cached_authority_peer_id = new_authority
		_authority_notify(new_authority)
	
	_leave_notify(peer_id)
	
	if world_viewport:
		world_viewport.player_left(peer_id)


func _authority_notify(new_authority: int) -> void:
	for i: int in range(_authority_observers.size() - 1, -1, -1):
		_authority_observers[i].world_authority_changed(new_authority)


func _join_notify(peer_id: int) -> void:
	for i: int in _world_synchronizers.size():
		_world_synchronizers[i].peer_joined(peer_id)


func _leave_notify(peer_id: int) -> void:
	for i: int in range(_world_synchronizers.size() - 1, -1, -1):
		_world_synchronizers[i].peer_left(peer_id)


func _get_world_authority_nocache() -> int:
	var peer_ids = get_membership_manager().get_world_peers(world_key)
	return peer_ids[0] if peer_ids else _cached_authority_peer_id


func _spawn_function(data: Variant) -> Node:
	if not WorldNetUtils.validate(data, TYPE_NIL):
		push_error("Invalid data.")
		return null
	
	var factory := multi_world.world_factory
	if not factory:
		push_error("MultiWorld.world_factory is not set.")
		return null
	
	var wrv := factory.create_world_viewport(self)
	if not wrv:
		push_error("WorldFactory failed to create a viewport for world '%s' (type '%s')." % [world_key, world_type])
		return null
	
	return wrv


func _instantiate_world() -> void:
	MultiWorldLog.log("WorldInstance._instantiate_world() [%s]" % [world_key])
	assert(world_viewport_multiplayer_spawner.is_multiplayer_authority())
	world_viewport = world_viewport_multiplayer_spawner.spawn()
	world_spawned.emit()


func _on_world_viewport_multiplayer_spawner_spawned(node: Node) -> void:
	MultiWorldLog.log("%s: remote spawned %s" % [self, node])
	world_viewport = node
	world_spawned.emit()


func _on_world_viewport_multiplayer_spawner_despawned(node: Node) -> void:
	MultiWorldLog.log("%s: remote despawned %s" % [self, node])
	assert(world_viewport == node)
	world_viewport = null


func _on_world_viewport_multiplayer_spawner_authority_changed(old_authority: int) -> void:
	if world_viewport_multiplayer_spawner:
		MultiWorldLog.log("WorldViewportMultiplayerSpawner: authority changed from %s to %s" % [old_authority, world_viewport_multiplayer_spawner.get_multiplayer_authority()])
