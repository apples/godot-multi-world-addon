extends Node
class_name WorldAuthorityObserver

## Updates the target node's multiplayer authority whenever the world's authority changes.
##
## Add this to any node (inside a world) whose authority should follow the world host.

signal authority_changed(new_auth: int)

@export var target_node_path: NodePath = ^".."
@export var recursive: bool = true
## If true (and [member recursive] is true), only nodes owned by the same scene as the target
## are updated. This avoids overriding authority for nested scenes that have their own observer.
@export var local_to_scene: bool = true

var world: WorldInstance


func _enter_tree() -> void:
	world = WorldInstance.find(self)
	if world != null:
		world.register_authority_observer(self)
		_propagate(world.get_world_authority())


func _exit_tree() -> void:
	if world != null:
		world.unregister_authority_observer(self)
	world = null


func world_authority_changed(_new_authority: int) -> void:
	_propagate(world.get_world_authority())


func _propagate(new_auth: int) -> void:
	var target: Node = get_node(target_node_path)
	if not local_to_scene or not recursive:
		target.set_multiplayer_authority(new_auth, recursive)
	else:
		_propagate_scene(new_auth, target.owner if target.owner else target, target)
	
	authority_changed.emit(new_auth)


func _propagate_scene(new_auth: int, scene_owner: Node, target: Node) -> void:
	assert(recursive and local_to_scene)
	assert(target == scene_owner or target.owner == scene_owner)
	
	for c in target.get_children(true):
		if c.owner == scene_owner:
			_propagate_scene(new_auth, scene_owner, c)
	
	target.set_multiplayer_authority(new_auth, false)
