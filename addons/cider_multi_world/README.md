# Multi-World

> **Requires** a Godot build in which `MultiplayerSpawner` nodes can change authority at runtime.
> With stock Godot, the host handoff will not work.

This addon implements a system where players can exist in separately loaded worlds,
with authority transfer when the world host leaves.

- A world is a self-contained scene running in its own `SubViewport`.
- Each world **elects** a host from its members (the longest-standing member).
  If that peer leaves, the next eligible host takes over.
  This way, the session server does not need to have every world loaded.
- A peer can be a member of **several worlds at once**.
  (e.g. a temporary battle scene that is visited while never leaving the dungeon.)
  The most recently joined world is the peer's **current world**.
- Worlds are created on demand by the session server and torn down when their last member leaves.
- Different types of worlds can be created via a `WorldFactory`.

## Overview

| Class name                            | Description                                                                       |
| ------------------------------------- | --------------------------------------------------------------------------------- |
| `WorldSystemsSpawner`                 | Spawns the core `WorldSystems`, owned by the session host.                        |
| `WorldSystems`                        | Holds `MultiWorld` and `WorldMembershipManager`.                                  |
| `MultiWorld`                          | Manages world lifecycles.                                                         |
| `WorldMembershipManager`              | Manages peer world memberships.                                                   |
| `WorldInstance`                       | Manages a world's authority and viewport lifecycle. Uses `WorldFactory`.          |
| `WorldFactory`                        | **Abstract.** Instantiates and sets up a world using game-specific logic.         |
| `WorldViewport`                       | The `SubViewport` holding a world's scene and one "player actor" per member peer. |
| `WorldAuthorityObserver`              | Syncs a node/scene's authority to that of the world.                              |
| `WorldVisibleMultiplayerSynchronizer` | `MultiplayerSynchronizer` that is only visible to the world's members.            |
| `RemoteSubViewportPanel`              | A `SubViewportPanel` that displays a subviewport that isn't its child.            |
| `LocalWorldSubViewportPanel`          | Displays the local player's current world viewport.                               |
| `WorldNetUtils`                       | Helper methods.                                                                   |
| `MultiWorldLog`                       | Optional debug logging hook. Silent by default.                                   |
| `WorldDebugLabel`                     | Optional debug overlay showing world membership states.                           |

## Quick Start

### 1. Create a `WorldFactory` and world viewport

```gdscript
class_name MyWorldFactory
extends WorldFactory

func _create_world_viewport(world: WorldInstance) -> WorldViewport:
	var viewport: WorldViewport = preload("res://my_world_viewport.tscn").instantiate()
	var scene: Node = load("res://levels/%s.tscn" % world.world_key).instantiate()
	viewport.add_scene(scene)
	return viewport
```

`my_world_viewport.tscn` should be inherited from `addons/multi-world/core/world_viewport.tscn`.
Set `player_actor_scene` on it if every member peer should get a node in the world
(if that scene's root has a `peer_id` property, it is assigned automatically),
and set `world_root` if the world's scene should live somewhere other than the viewport itself.

### 2. Create your world systems scene

Create a scene inheriting `addons/multi-world/core/world_systems.tscn` and assign an instance of
your factory to `MultiWorld.world_factory`.

### 3. Spawn the systems

Add a `WorldSystemsSpawner` to your top-level scene.
Set its `systems_scene` to the scene from step 2.

After setting up your multiplayer connection, call `spawner.host()`.

```gdscript
@onready var spawner: WorldSystemsSpawner = $WorldSystemsSpawner

func start_hosting() -> void:
	# ...after multiplayer.multiplayer_peer is set up as the server...
	spawner.host()
```

### 4. Show the local peer's world

Add a `LocalWorldSubViewportPanel` to your UI and call `panel.attach(systems)` from `systems_ready`.
It always displays the viewport of the local peer's current world.

### 5. Create worlds and add peers (session server only)

```gdscript
var world := systems.multi_world.get_or_create_world("town", "town") # (key, type, params)
systems.membership_manager.add_peer_to_world(peer_id, world.world_key, null)

# Auto-generated key ("battle__1", ...), custom params for the factory:
var battle := systems.multi_world.create_world("battle", { enemies = [...] })
systems.membership_manager.add_peer_to_world(peer_id, battle.world_key, null)

# Leave everything and enter another world:
systems.membership_manager.move_peer_to_world(peer_id, "dungeon_1", null)

# On disconnect:
systems.membership_manager.erase_peer(peer_id)
```

The third argument of `add_peer_to_world` is per-membership data that any peer can read with
`membership_manager.get_params_for(peer_id, world_key)` (e.g. a spawn position).

## Creating entities that live inside a world

Everything inside a world (the scene, its children, the player actors) is created through the
world's `WorldViewport` spawn. Three helpers make such nodes work with the world's host handoff:

- **`WorldAuthorityObserver`**: add it to a node and that node (and, by default, the other nodes of
  the same scene) will always have the world authority as multiplayer authority. It emits
  `authority_changed(new_authority)`. The root of a `WorldViewport` has one by default.
- **`WorldVisibleMultiplayerSynchronizer`**: a `MultiplayerSynchronizer` whose visibility is
  restricted to the peers in the world. Use it instead of a plain synchronizer inside a world.
- **`WorldNetUtils.enable_world_replication(node, properties)`**: call from `_ready()` to
  replicate properties of a node. A synchronizer's "spawn" properties are only sent along with the
  *spawned* node, and in a world that is the `WorldViewport`. This helper creates synchronizers
  rooted at the viewport, and wires up authority and visibility.

  ```gdscript
  func _ready() -> void:
  	WorldNetUtils.enable_world_replication(self, [
  		{ path = ".:health" },                       # sent with the spawn packet only (default)
  		{ path = ".:position",
  		  mode = SceneReplicationConfig.REPLICATION_MODE_ALWAYS },
  	])
  ```

From any node inside a world:

```gdscript
var world := WorldInstance.find(self)
world.world_key
world.get_world_authority()   # peer id of the world host
world.world_viewport.player_actors[peer_id]
world.world_spawned           # emitted when the viewport exists locally
```

## Signals worth knowing

- `MultiWorld.world_created(world_key)` / `world_destroying(world_key)`
- `WorldMembershipManager.peer_joined_world(peer_id, world_key, params)` / `peer_left_world(peer_id, world_key)`
- `WorldMembershipManager.peer_current_world_changed(peer_id, old_key, new_key)`
- `WorldInstance.world_spawned()`
- `WorldAuthorityObserver.authority_changed(new_authority)`

## Logging

The addon is silent unless told otherwise:

```gdscript
MultiWorldLog.sink = MyLogger.print_   # func(message: String) -> void
# or
MultiWorldLog.enabled = true           # plain print()
```

## Notes

- `MultiWorld.current` and `WorldMembershipManager.current` are static convenience references to
  the most recently created instance. They assume one set of world systems per game.
- The base `WorldViewport` scene only enables `own_world_3d` (so 3D worlds are isolated from each
  other). Other rendering options (audio listener, shadow atlas size, picking, ...) are
  intentionally left to your own `WorldViewport` scene.
