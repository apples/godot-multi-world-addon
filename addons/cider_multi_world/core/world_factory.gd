@abstract
extends Resource
class_name WorldFactory

## Tells [MultiWorld] how to build the contents of a world. Subclass it and assign an instance
## to [member MultiWorld.world_factory].
##
## The factory is invoked on every peer that needs the world's viewport (locally on the world's
## authority, and while replicating the viewport on the other peers), so it must be
## deterministic: the same [WorldInstance] must produce the same node tree on all peers.


func create_world_viewport(world: WorldInstance) -> WorldViewport:
	return _create_world_viewport(world)


## Builds the [WorldViewport] for the world, based on its `world_type`, `world_key` and `params`.
## Typically this instantiates a WorldViewport scene, instantiates the world's scene, and
## attaches it with [method WorldViewport.add_scene].
@abstract func _create_world_viewport(world: WorldInstance) -> WorldViewport
