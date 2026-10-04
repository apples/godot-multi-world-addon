class_name TubeUPNP extends Node
## Maps UDP ports on the local gateway using UPnP.
##
## Must be inside the scene tree to work. Discovery starts when the node enters the tree, and all active mappings are
## removed when it exits. Every UPnP request runs on a single worker thread, so requests are never concurrent and keep
## their order.


signal warning_raised(message: String)
signal port_mapping_ready
signal port_mapped(public_port: int, local_port: int)


const MAPPING_DURATION := 60*2 #sec, 2 minutes
const MAPPING_RENEW_TIME := 0.75*MAPPING_DURATION


enum _Command {
	ADD,
	DELETE,
	QUIT,
}


var mapped_ports: Dictionary[int, int] = {} # public to local
var mapped_times: Dictionary[int, float] = {}

var upnp := UPNP.new() # only used by the worker thread
var is_port_mapping_ready := false

var _thread: Thread
var _semaphore := Semaphore.new()
var _mutex := Mutex.new()
var _queue: Array[Dictionary] = []


static func is_supported() -> bool:
	return OS.get_name() != "Web"


func raise_warning(message: String):
	push_warning(message)
	warning_raised.emit(message)


func _enter_tree() -> void:
	if not is_supported() or null != _thread:
		return
	
	is_port_mapping_ready = false
	_thread = Thread.new()
	_thread.start(_thread_main)


func _exit_tree() -> void:
	if null == _thread:
		return
	
	clear_port_mapping()
	_push_command({"command": _Command.QUIT})
	_thread.wait_to_finish()
	_thread = null
	is_port_mapping_ready = false


func _process(delta: float):
	if not is_port_mapping_ready:
		return
	
	for port in mapped_ports.keys():
		mapped_times[port] += delta
		if MAPPING_RENEW_TIME < mapped_times[port]:
			_add_port_mapping(port, mapped_ports[port])


func add_port_mapping(p_public_port: int, p_local_port: int) -> void:
	if not is_supported():
		return
	
	if mapped_ports.has(p_public_port):
		return
	
	_add_port_mapping(p_public_port, p_local_port)


func delete_port_mapping(p_public_port: int) -> void:
	if not mapped_ports.has(p_public_port):
		return
	
	mapped_ports.erase(p_public_port)
	mapped_times.erase(p_public_port)
	_push_command({
		"command": _Command.DELETE,
		"public_port": p_public_port,
	})


func clear_port_mapping() -> void:
	for port in mapped_ports.keys():
		delete_port_mapping(port)


func _add_port_mapping(p_public_port: int, p_local_port: int) -> void:
	mapped_ports[p_public_port] = p_local_port
	mapped_times[p_public_port] = 0.0
	_push_command({
		"command": _Command.ADD,
		"public_port": p_public_port,
		"local_port": p_local_port,
	})


func _push_command(p_command: Dictionary) -> void:
	_mutex.lock()
	_queue.append(p_command)
	_mutex.unlock()
	_semaphore.post()


func _on_discovery_completed(p_success: bool) -> void:
	is_port_mapping_ready = p_success
	if p_success:
		port_mapping_ready.emit()


static func _result_string(p_result: int) -> String:
	var names := ClassDB.class_get_enum_constants("UPNP", "UPNPResult")
	if p_result < 0 or names.size() <= p_result:
		return str(p_result)
	
	return names[p_result]


# WORKER THREAD ###

func _thread_main() -> void:
	var gateway_ready := _discover()
	_on_discovery_completed.call_deferred(gateway_ready)
	
	var active_ports: Dictionary[int, bool] = {}
	while true:
		_semaphore.wait()
		_mutex.lock()
		var command: Dictionary = _queue.pop_front()
		_mutex.unlock()
		
		match command.command:
			_Command.ADD:
				if _map_port(gateway_ready, command.public_port, command.local_port):
					active_ports[command.public_port] = true
			
			_Command.DELETE:
				if active_ports.erase(command.public_port):
					_unmap_port(command.public_port)
			
			_Command.QUIT:
				return


func _discover() -> bool:
	var error := upnp.discover()
	if error:
		raise_warning.call_deferred(
			"cannot map port, upnp discover error: {error}".format({
			"error": _result_string(error),
		}))
		return false
	
	var gateway := upnp.get_gateway()
	if null == gateway:
		raise_warning.call_deferred("cannot map port, no gateway found")
		return false
	
	if not gateway.is_valid_gateway():
		raise_warning.call_deferred("cannot map port, gateway not valid")
		return false
	
	return true


func _map_port(p_gateway_ready: bool, p_public_port: int, p_local_port: int) -> bool:
	if not p_gateway_ready:
		raise_warning.call_deferred(
			"cannot map port {port} to internal port {internal_port}, upnp not ready".format({
			"port": p_public_port,
			"internal_port": p_local_port,
		}))
		return false
	
	var result := upnp.add_port_mapping(
		p_public_port,
		p_local_port,
		"Tube", #ProjectSettings.get_setting("application/config/name"),
		"UDP",
		MAPPING_DURATION
	)
	if result:
		raise_warning.call_deferred(
			"cannot map port {port} to internal port {internal_port}, error: {error}".format({
			"port": p_public_port,
			"internal_port": p_local_port,
			"error": _result_string(result),
		}))
		return false
	
	port_mapped.emit.call_deferred(
		p_public_port,
		p_local_port
	)
	return true


func _unmap_port(p_public_port: int) -> void:
	var result := upnp.delete_port_mapping(p_public_port, "UDP")
	if result:
		raise_warning.call_deferred(
			"cannot delete port mapping {port}, error: {error}".format({
			"port": p_public_port,
			"error": _result_string(result),
		}))
