extends SubViewport
class_name WorldViewport

## The SubViewport that holds the contents of a world.
##
## Created on every peer by the [WorldFactory]. Contains the world's scene, plus one
## "player actor" per peer that is a member of the world (spawned and despawned by the world's
## authority).

## Scene instantiated for every peer that joins the world. Leave empty for no per-peer nodes.
## If the instantiated root has a `peer_id` property, it is set to the peer's id.
@export var player_actor_scene: PackedScene = null
## The node that the world's scene and the player actors are added to.
@export var world_root: Node

## The root of the world's scene, set by [method add_scene].
var scene: Node

var player_actors: Dictionary[int, Node]

@onready var player_actor_multiplayer_spawner: MultiplayerSpawner = $PlayerActorMultiplayerSpawner


func _enter_tree() -> void:
	var parent_viewport = get_parent().get_viewport()
	
	size = parent_viewport.size
	parent_viewport.size_changed.connect(_on_viewport_size_changed)


func _exit_tree() -> void:
	var parent_viewport = get_parent().get_viewport()
	parent_viewport.size_changed.disconnect(_on_viewport_size_changed)


func _ready() -> void:
	player_actor_multiplayer_spawner.spawn_function = _player_spawn_function
	player_actor_multiplayer_spawner.spawn_path = player_actor_multiplayer_spawner.get_path_to(world_root)
	if player_actor_scene:
		player_actor_multiplayer_spawner.add_spawnable_scene(player_actor_scene.resource_path)


## Adds the world's scene to [member world_root] and records it as [member scene].
## Intended to be called by a [WorldFactory] before the viewport enters the tree.
func add_scene(p_scene: Node) -> void:
	world_root.add_child(p_scene)
	scene = p_scene


func player_joined(peer_id: int) -> void:
	if is_multiplayer_authority() and player_actor_scene:
		assert(peer_id not in player_actors)
		MultiWorldLog.log("%s: spawning player_actor %s" % [self, peer_id])
		
		player_actors[peer_id] = player_actor_multiplayer_spawner.spawn({
			peer_id = peer_id,
		})


func player_left(peer_id: int) -> void:
	if is_multiplayer_authority() and player_actor_scene:
		assert(peer_id in player_actors)
		player_actors[peer_id].queue_free()
		player_actors.erase(peer_id)


func _player_spawn_function(data: Variant) -> Node:
	if not WorldNetUtils.validate(data, TYPE_DICTIONARY, {
		peer_id = TYPE_INT,
	}):
		push_error("Invalid data received.")
		return null
	
	var pa = player_actor_scene.instantiate()
	pa.name = "PlayerActor__" + str(data.peer_id)
	if "peer_id" in pa:
		pa.peer_id = data.peer_id
	return pa


func _on_viewport_size_changed() -> void:
	var parent_viewport = get_parent().get_viewport()
	size = parent_viewport.size


func _on_player_actor_multiplayer_spawner_spawned(node: Node) -> void:
	MultiWorldLog.log("%s: player_actor remote spawned %s" % [self, node])
	var peer_id := _get_actor_peer_id(node)
	assert(peer_id not in player_actors)
	player_actors[peer_id] = node


func _on_player_actor_multiplayer_spawner_despawned(node: Node) -> void:
	MultiWorldLog.log("%s: player_actor remote de-spawned %s" % [self, node])
	var peer_id := _get_actor_peer_id(node)
	assert(peer_id in player_actors)
	player_actors.erase(peer_id)


func _get_actor_peer_id(actor: Node) -> int:
	return int(str(actor.name).get_slice("__", 1))
