extends Node
class_name WorldSystems

## Root of the shared multi-world infrastructure: a [MultiWorld] and a [WorldMembershipManager].
##
## Spawn it with a [WorldSystemsSpawner]. To give the world systems a [WorldFactory], create a
## scene inheriting from `world_systems.tscn` and assign [member MultiWorld.world_factory].

@export var multi_world: MultiWorld
@export var membership_manager: WorldMembershipManager
