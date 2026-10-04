extends RichTextLabel
class_name WorldDebugLabel

## Debug overlay listing the worlds, their member peers and their player actors.
## Flags player actors that exist for peers that are not members of the world in red.
##
## Call [method attach] once the [WorldSystems] exist.

var _systems: WorldSystems


func attach(systems: WorldSystems) -> void:
	_systems = systems
	if not _systems:
		return
	_systems.multi_world.child_order_changed.connect(_update)
	_systems.multi_world.world_created.connect(_update.unbind(1))
	_systems.membership_manager.peer_joined_world.connect(_update.unbind(3))
	_systems.membership_manager.peer_left_world.connect(_update.unbind(2))
	_update()


func _physics_process(_delta: float) -> void:
	_update()


func _update() -> void:
	if not _systems:
		text = "no world systems"
		return
	
	var out = ""
	for c in _systems.multi_world.get_children():
		if c is WorldInstance:
			out += c.name + "\n"
			
			if not c.child_order_changed.is_connected(_update):
				c.child_order_changed.connect(_update)
			
			var peers = _systems.membership_manager.get_world_peers(c.world_key)
			out += "  Peers:" + ", ".join(Array(peers).map(func (x): return str(x))) + "\n"
			
			if c.world_viewport:
				var spawner: MultiplayerSpawner = c.world_viewport.player_actor_multiplayer_spawner
				var sp = spawner.get_node_or_null(spawner.spawn_path)
				if sp and not sp.child_order_changed.is_connected(_update):
					sp.child_order_changed.connect(_update)
				
				out += "  " + c.world_viewport.name + "\n"
				for p in peers:
					var ac = c.world_viewport.player_actors.get(p)
					if ac:
						out += "    " + str(p) + ": " + ac.name + "\n"
				for p in c.world_viewport.player_actors:
					if p not in peers:
						var ac = c.world_viewport.player_actors[p]
						out += "    [color=red]" + str(p) + ": " + ac.name + "[/color]\n"
	
	text = out
