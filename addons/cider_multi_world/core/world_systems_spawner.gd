extends MultiplayerSpawner
class_name WorldSystemsSpawner

## Spawns the [WorldSystems] on the server and replicates it to every other peer.
##
## Place it anywhere in your scene. The server calls [method host] once the multiplayer session
## has started. Every peer (including the server) is then notified through [signal systems_ready].

## Emitted on every peer once the [WorldSystems] exist.
signal systems_ready(systems: WorldSystems)

## The scene to spawn. Must be [code]world_systems.tscn[/code] or a scene inheriting from it.
@export var systems_scene: PackedScene

## The spawned systems, or null before [signal systems_ready].
var systems: WorldSystems


func _init() -> void:
	spawn_path = ^"."
	spawn_limit = 1


func _enter_tree() -> void:
	if systems_scene:
		add_spawnable_scene(systems_scene.resource_path)
	else:
		push_error("%s: systems_scene is not set." % [self])


func _ready() -> void:
	spawned.connect(_on_spawned)
	despawned.connect(_on_despawned)


## Server only. Spawns the world systems and returns them.
func host() -> WorldSystems:
	if not multiplayer.is_server():
		push_error("WorldSystemsSpawner.host: must be server!")
		return null
	if systems:
		push_error("WorldSystemsSpawner.host: already hosting!")
		return systems
	
	systems = systems_scene.instantiate()
	add_child(systems)
	systems_ready.emit(systems)
	return systems


func _on_spawned(node: Node) -> void:
	systems = node
	systems_ready.emit(systems)


func _on_despawned(node: Node) -> void:
	if node == systems:
		systems = null
