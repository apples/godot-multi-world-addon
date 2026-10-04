@tool
extends MultiplayerSynchronizer
class_name WorldVisibleMultiplayerSynchronizer

## Updates visibility based on peers joined to the world.
##
## Only peers that are members of the enclosing [WorldInstance] receive this synchronizer's data.


var world: WorldInstance


func _init() -> void:
	public_visibility = false
	visibility_update_mode = MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		return
	
	world = WorldInstance.find(self)
	if not world:
		push_error("%s must be placed inside a WorldInstance." % [self])
		return
	
	world.register_synchronizer(self)
	
	for p in world.get_membership_manager().get_world_peers(world.world_key):
		set_visibility_for(p, true)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	
	if world:
		world.unregister_synchronizer(self)
	world = null


func peer_joined(peer_id: int) -> void:
	set_visibility_for(peer_id, true)


func peer_left(peer_id: int) -> void:
	set_visibility_for(peer_id, false)


func _property_can_revert(property: StringName) -> bool:
	if property == &"public_visibility":
		return true
	if property == &"visibility_update_mode":
		return true
	return false


func _property_get_revert(property: StringName) -> Variant:
	if property == &"public_visibility":
		return false
	if property == &"visibility_update_mode":
		return MultiplayerSynchronizer.VISIBILITY_PROCESS_NONE
	return null
