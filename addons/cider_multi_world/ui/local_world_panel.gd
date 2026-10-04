extends RemoteSubViewportPanel
class_name LocalWorldSubViewportPanel

## Displays the world the local peer is currently in.
##
## Call [method attach] once the [WorldSystems] exist (see [signal WorldSystemsSpawner.systems_ready]).
## From then on the panel shows the [WorldViewport] of the local peer's current world
## (the most recently joined one), and switches whenever that changes.

var _systems: WorldSystems
var _refresh_id: int = 0


func attach(systems: WorldSystems) -> void:
	if _systems == systems:
		return
	_detach()
	
	_systems = systems
	if not _systems:
		return
	
	_systems.membership_manager.peer_current_world_changed.connect(_on_peer_current_world_changed)
	_systems.multi_world.world_created.connect(_on_world_created)
	_systems.tree_exiting.connect(_detach)
	_refresh()


func _detach() -> void:
	_refresh_id += 1
	sub_viewport = null
	
	if not _systems:
		return
	_systems.membership_manager.peer_current_world_changed.disconnect(_on_peer_current_world_changed)
	_systems.multi_world.world_created.disconnect(_on_world_created)
	_systems.tree_exiting.disconnect(_detach)
	_systems = null


func _exit_tree() -> void:
	_detach()


func _on_peer_current_world_changed(peer_id: int, _old_world_key: String, _new_world_key: String) -> void:
	if peer_id == multiplayer.get_unique_id():
		_refresh()


func _on_world_created(world_key: String) -> void:
	if world_key == _systems.membership_manager.get_peer_current_world_key(multiplayer.get_unique_id()):
		_refresh()


func _refresh() -> void:
	_refresh_id += 1
	var refresh_id := _refresh_id
	
	var world_key := _systems.membership_manager.get_peer_current_world_key(multiplayer.get_unique_id())
	if world_key == "":
		MultiWorldLog.log("LocalWorldSubViewportPanel: local peer has no world")
		sub_viewport = null
		return
	
	var world := _systems.multi_world.get_world(world_key)
	if not world:
		MultiWorldLog.log("LocalWorldSubViewportPanel: local peer's current world does not exist (yet)")
		sub_viewport = null
		return
	
	if world.world_viewport == null:
		sub_viewport = null
		await world.world_spawned
		if refresh_id != _refresh_id:
			return
	
	sub_viewport = world.world_viewport
