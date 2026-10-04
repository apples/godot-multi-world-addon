@abstract
extends RefCounted
class_name WorldNetUtils

## Networking helpers for the multi-world addon.


## Validates that `data` matches the `type`.
## If `type` is TYPE_DICTIONARY, each entry is also validated using matching
## entries from `type_meta`, which can either be a `Type` or a `[Type, type_meta]` tuple.
## Useful for validating spawn data and RPC parameters.
static func validate(data: Variant, type: Variant.Type, type_meta: Variant = null) -> bool:
	if typeof(data) != type:
		push_error("Data does not match type ", type)
		return false
	
	match type:
		TYPE_DICTIONARY:
			if type_meta:
				for k in data:
					if k not in type_meta:
						push_error("Key %s in data not found in type_meta" % [k])
						return false
					match type_meta[k]:
						var t when t is int:
							if not validate(data[k], t):
								return false
						[var t, var m] when t is int:
							if not validate(data[k], t, m):
								return false
						_:
							push_error("Invalid type_meta")
							return false
				for k in type_meta:
					if k not in data:
						push_error("Key %s not found in data" % [k])
						return false
	
	return true


## Enables replication for the specified properties, using the WorldViewport as the sync root.
##
## A "spawn" property is only included in a node's spawn packet when the synchronizer's
## `root_path` is the spawned node. Since everything inside a world is spawned as part of the
## WorldViewport, synchronizers for nodes inside a world need the viewport as their root.
## This helper sets up the synchronizers (and an authority observer) needed to do that.
##
## `properties` is an array of dictionaries with these keys:
## - `path` (String): property path relative to `this`, e.g. `".:position"`.
## - `spawn` (bool, default true): include the property in the spawn packet.
## - `mode` (SceneReplicationConfig.ReplicationMode, default REPLICATION_MODE_NEVER).
##
## Ideal to call from a node's _ready(). Must only be called once per node.
static func enable_world_replication(this: Node, properties: Array[Dictionary]) -> void:
	if Engine.is_editor_hint():
		return
	
	const AUTH_NODE_NAME = "WorldNetUtils_WorldAuthorityObserver"
	const VIS_NODE_NAME = "WorldNetUtils_VisibilitySynchronizer"
	const SYNC_NODE_NAME = "WorldNetUtils_WorldSynchronizer"
	
	var auth: WorldAuthorityObserver = this.get_node_or_null(AUTH_NODE_NAME)
	var vis: WorldVisibleMultiplayerSynchronizer = this.get_node_or_null(VIS_NODE_NAME)
	var sync: WorldVisibleMultiplayerSynchronizer = this.get_node_or_null(SYNC_NODE_NAME)
	
	if auth or vis or sync:
		push_error("enable_world_replication must only be called once for a node!")
		return
	
	var root_node = this.get_viewport()
	assert(root_node is WorldViewport)
	
	auth = WorldAuthorityObserver.new()
	auth.name = AUTH_NODE_NAME
	auth.recursive = false
	assert(auth.name == AUTH_NODE_NAME)
	
	vis = WorldVisibleMultiplayerSynchronizer.new()
	vis.name = VIS_NODE_NAME
	vis.replication_config = SceneReplicationConfig.new()
	auth.authority_changed.connect(vis.set_multiplayer_authority.bind(false))
	
	var repl := SceneReplicationConfig.new()
	var root_to_this := str(root_node.get_path_to(this))
	for prop in properties:
		assert(prop.path is String)
		var path: NodePath = root_to_this.path_join(prop.path)
		repl.add_property(path)
		repl.property_set_spawn(path, prop.get("spawn", true))
		repl.property_set_replication_mode(path, prop.get("mode", SceneReplicationConfig.REPLICATION_MODE_NEVER))
	
	sync = WorldVisibleMultiplayerSynchronizer.new()
	sync.name = SYNC_NODE_NAME
	sync.replication_config = repl
	sync.root_path = "..".path_join(str(this.get_path_to(root_node)))
	auth.authority_changed.connect(sync.set_multiplayer_authority.bind(false))
	
	this.add_child(auth, true, Node.INTERNAL_MODE_FRONT)
	
	this.add_child(vis, true, Node.INTERNAL_MODE_FRONT)
	assert(vis.name == VIS_NODE_NAME)
	assert(vis.get_node(vis.root_path) == this)
	assert(vis.get_multiplayer_authority() == auth.world.get_world_authority())
	
	this.add_child(sync, true, Node.INTERNAL_MODE_FRONT)
	assert(sync.name == SYNC_NODE_NAME)
	assert(sync.get_node(sync.root_path) == root_node)
	assert(sync.get_multiplayer_authority() == auth.world.get_world_authority())
