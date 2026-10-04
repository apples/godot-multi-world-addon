extends Node
class_name MultiWorld

## Creates, tracks and destroys [WorldInstance]s.
##
## Worlds are created by the server and replicated to every peer. A world is destroyed by the
## server as soon as its last member leaves. What a world actually contains is up to the
## [WorldFactory].

signal world_created(world_key: String)
signal world_destroying(world_key: String)

const WORLD_INSTANCE = preload("world_instance.tscn")

## The most recently readied MultiWorld. Convenient for code that has no better way to find it.
static var current: MultiWorld

@export var membership_manager: WorldMembershipManager
@export var world_factory: WorldFactory

var worlds_by_world_key: Dictionary[String, WorldInstance]

## Next tag number for generated world keys.
var _i: int = 1


@onready var world_multiplayer_spawner: MultiplayerSpawner = $WorldMultiplayerSpawner


func _ready() -> void:
	current = self
	world_multiplayer_spawner.spawn_function = _spawn_function
	if multiplayer.is_server():
		membership_manager.peer_left_world.connect(_on_peer_left_world)


func get_world(world_key: String) -> WorldInstance:
	return worlds_by_world_key.get(world_key)


func get_worlds_of_type(world_type: String) -> Array[WorldInstance]:
	var result: Array[WorldInstance]
	for world: WorldInstance in worlds_by_world_key.values():
		if world.world_type == world_type:
			result.append(world)
	return result


## Server only. Returns the world with the given key, creating it first if it doesn't exist.
func get_or_create_world(world_key: String, world_type: String, params: Dictionary = {}) -> WorldInstance:
	if not multiplayer.is_server():
		push_error("get_or_create_world: must be server!")
		return null
	
	if world_key in worlds_by_world_key:
		return worlds_by_world_key[world_key]
	
	return create_world(world_type, params, world_key)


## Server only. Creates a new world. If `world_key` is empty, a unique key is generated
## from the world type.
func create_world(world_type: String, params: Dictionary = {}, world_key: String = "") -> WorldInstance:
	if not multiplayer.is_server():
		push_error("create_world: must be server!")
		return null
	
	if world_key == "":
		world_key = "%s__%s" % [world_type, _i]
		_i += 1
	elif world_key in worlds_by_world_key:
		push_error("create_world: world '%s' already exists!" % [world_key])
		return null
	
	MultiWorldLog.log("MultiWorld: Spawning world %s" % [world_key])
	
	var world: WorldInstance = world_multiplayer_spawner.spawn({
		world_type = world_type,
		world_key = world_key,
		params = params,
	})
	
	worlds_by_world_key[world_key] = world
	
	world_created.emit(world_key)
	
	return world


func _spawn_function(data: Variant) -> Node:
	if not WorldNetUtils.validate(data, TYPE_DICTIONARY, {
		world_type = TYPE_STRING,
		world_key = TYPE_STRING,
		params = TYPE_DICTIONARY,
	}):
		push_error("Invalid data")
		return null
	
	var world: WorldInstance = WORLD_INSTANCE.instantiate()
	world.name = "World__" + data.world_key
	world.world_type = data.world_type
	world.world_key = data.world_key
	world.params = data.params
	
	return world


func _on_world_multiplayer_spawner_spawned(node: Node) -> void:
	MultiWorldLog.log("%s: remote spawned world %s" % [self, node.world_key])
	worlds_by_world_key[node.world_key] = node
	world_created.emit(node.world_key)


func _on_world_multiplayer_spawner_despawned(node: Node) -> void:
	MultiWorldLog.log("%s: remote de-spawned world %s" % [self, node.world_key])
	worlds_by_world_key.erase(node.world_key)


func _on_peer_left_world(_peer_id: int, world_key: String) -> void:
	assert(multiplayer.is_server())
	
	var world = get_world(world_key)
	
	if not world:
		push_error("Player left non-existent World")
		return
	
	var remaining_peers = membership_manager.get_world_peers(world_key)
	
	if remaining_peers.is_empty():
		MultiWorldLog.log("MultiWorld: Destroying world %s" % [world_key])
		world_destroying.emit(world.world_key)
		worlds_by_world_key.erase(world.world_key)
		world.queue_free()
