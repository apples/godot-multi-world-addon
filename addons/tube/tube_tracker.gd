class_name TubeTracker extends RefCounted


const MAX_INTERVAL := 120.0 #sec
const MAX_RECONNECT_DELAY := 30.0 #sec
const RECONNECT_STABLE_TIME := 30.0 #sec the connection must stay open to reset reconnect attempts


signal failed
signal connected
signal disconnected
signal received_answer(data: Dictionary)
signal interval_timeout
signal reconnecting(attempt: int, delay: float)


signal warning_raised(message: String)
signal state_changed

signal data_sent(data: Dictionary)
signal received_data(data: Dictionary)


const CLOSE_CODE_CLIENT: int = 3001
const CLOSE_CODE_FAILED: int = 3002
# https://developer.mozilla.org/en-US/docs/Web/API/WebSocket/close, custom code 3000-4999
# https://www.rfc-editor.org/rfc/rfc6455.html#section-7.4.1


var url: String
var error_message: String
var socket := WebSocketPeer.new()
var state := socket.get_ready_state()

var connecting_time: float = 0.0 #sec
var up_time: float = 0.0 #sec
var interval_time: float = 0.0 #sec
var interval_time_left: float = -1.0

var reconnect_attempts: int = 0
var reconnect_time_left: float = -1.0 # sec, negative if no reconnection is pending

var _closed_by_client := false


func _to_string() -> String:
	var string := socket.get_requested_url()
	
	if "Web" != OS.get_name():
		if WebSocketPeer.STATE_OPEN == socket.get_ready_state():
			string += "({protocol}://{address}:{port})".format({
				"protocol": socket.get_selected_protocol(),
				"address": socket.get_connected_host(),
				"port": socket.get_connected_port(),
			})
	
	return string


func raise_warning(message: String):
	push_warning(message)
	warning_raised.emit(message)


func connect_to_url(p_url: String) -> Error:
	url = p_url
	var error := socket.connect_to_url(p_url)
	if error:
		error_message = "connection failed: {error}".format({
			"error": error_string(error) 
		})
		failed.emit()
		return error
	
	state = socket.get_ready_state()
	_closed_by_client = false
	return error


## Schedules a reconnection after an exponential backoff: [param p_base_delay] doubled for every consecutive attempt,
## up to [constant MAX_RECONNECT_DELAY]. Returns the delay.
func schedule_reconnect(p_base_delay: float) -> float:
	var delay := minf(p_base_delay * pow(2.0, reconnect_attempts), MAX_RECONNECT_DELAY)
	reconnect_attempts += 1
	reconnect_time_left = delay
	reconnecting.emit(reconnect_attempts, delay)
	return delay


func is_reconnect_pending() -> bool:
	return 0.0 <= reconnect_time_left


func cancel_reconnect() -> void:
	reconnect_time_left = -1.0


func _reconnect() -> void:
	reconnect_time_left = -1.0
	socket = WebSocketPeer.new()
	connecting_time = 0.0
	up_time = 0.0
	interval_time = 0.0
	interval_time_left = -1.0
	error_message = ""
	if OK == connect_to_url(url):
		state_changed.emit()


func is_open() -> bool:
	return WebSocketPeer.STATE_OPEN == socket.get_ready_state()


## Whether the connection is open or opening.
func is_alive() -> bool:
	var ready_state := socket.get_ready_state()
	return WebSocketPeer.STATE_OPEN == ready_state or WebSocketPeer.STATE_CONNECTING == ready_state


func is_close() -> bool:
	return WebSocketPeer.STATE_CLOSED == socket.get_ready_state()


func close(p_info_hash: String, p_peer_id_hash: String):
	cancel_reconnect()
	if is_open():
		send_stop(
			p_info_hash,
			p_peer_id_hash
		)
	
	if not is_close():
		_closed_by_client = true
		socket.close(
			CLOSE_CODE_CLIENT,
			"Close by client",
		)


func _socket_connection_opened():
	connected.emit()


func _socket_connection_closed(p_previous_state: WebSocketPeer.State, p_code: int, p_reason: String):
	if not _closed_by_client:
		if WebSocketPeer.STATE_CONNECTING == p_previous_state:
			error_message = "connection impossible"
			failed.emit()
		
		elif WebSocketPeer.STATE_OPEN == p_previous_state:
			error_message = "connection failed: {reason}".format({
				"reason": p_reason if p_reason else "Closed unexpectedly, code: {code}".format({
					"code": p_code,
				}),
			})
			failed.emit()
	
	disconnected.emit()


## Encodes tracker packet data as JSON string.
func encode_data(data: Dictionary) -> String:
	var json := JSON.stringify(data)
	return json


## Decodes tracker packet data from a [PackedByteArray].
func decode_packet(p_packet: PackedByteArray) -> Variant:
	var string := p_packet.get_string_from_utf8()
	var data = JSON.parse_string(string)
	return data


func send_data(p_data: Dictionary) -> Error:
	var text := encode_data(p_data)
	var error := socket.send_text(
		text
	)
	
	if error:
		raise_warning(
			"Cannot send text: {error}".format({
			"error": error_string(error)
		}))
	
	else:
		data_sent.emit(p_data)
	
	return error


func send_announce(p_info_hash: String, p_peer_id_hash: String) -> Error:
	return send_data({
		"action": "announce",
		"info_hash": p_info_hash,
		"peer_id": p_peer_id_hash,
		
		"uploaded": 0,
		"downloaded": 0,
	})


func send_answer(
	p_info_hash: String,
	p_peer_id_hash: String,
	p_to_peer_id_hash: String,
	description: Dictionary,
	ice_candidates: Array
) -> Error:
	return send_data({
		"action": "announce",
		"info_hash": p_info_hash,
		"peer_id": p_peer_id_hash,
		
		"to_peer_id": p_to_peer_id_hash,
		"answer": {
			"type": description.type,
			"sdp": description.sdp,
			"ice_candidates": ice_candidates,
		},
		"offer_id": "0",
	})


func send_stop(p_info_hash: String, p_peer_id_hash: String) -> Error:
	return send_data({
	  "action": "announce",
	  "info_hash": p_info_hash,
	  "peer_id": p_peer_id_hash,
	  "event": "stopped"
	})


func _received_packet(p_packet: PackedByteArray):
	var data = decode_packet(p_packet)
	if not data is Dictionary:
		raise_warning("Received invalid packet: {packet}".format({
			"packet": str(p_packet)
		}))
		return
	
	received_data.emit(data)
	if data.has("answer"):
		_handle_answer(data)
		return
	
	_handle_announce(data)


func _handle_announce(p_data: Dictionary):
	if p_data.has("failure reason"):
		raise_warning("tracker failure: {reason}".format({
			"reason": p_data["failure reason"]
		}))
		return
	
	if not p_data.has("interval"):
		raise_warning("announce data has no interval")
		return
	
	if not p_data.interval is float:
		raise_warning("interval invalid data type")
		return
	
	interval_time = min(p_data.interval, MAX_INTERVAL)
	interval_time_left = interval_time


func _handle_answer(p_data: Dictionary):
	if not p_data is Dictionary:
		raise_warning("answer data invalid data type")
		return
	
	if not p_data.has("peer_id"):
		raise_warning("answer data has no peer_id")
		return
	
	if not p_data.peer_id is String:
		raise_warning("peer_id invalid data type")
		return
	
	if not p_data.has("answer"):
		raise_warning("answer data has no answer")
		return
	
	if not p_data.answer is Dictionary:
		raise_warning("answer invalid data type")
		return
	
	var answer: Dictionary = p_data.answer
	if not answer.has("sdp"):
		raise_warning("answer data has no sdp")
		return
	
	if not answer.sdp is String:
		raise_warning("sdp invalid data type")
		return
	
	if not answer.has("type"):
		raise_warning("answer data has no type")
		return
	
	if not answer.type is String:
		raise_warning("type invalid data type")
		return
	
	if not answer.has("ice_candidates"):
		raise_warning("answer data has no ice_candidates")
		return
	
	if not answer.ice_candidates is Array:
		raise_warning("ice_candidates invalid data type")
		return
	
	received_answer.emit(p_data)


static func get_peer_id_hash_from_answer_data(p_data: Dictionary) -> String:
	return p_data.peer_id


static func get_type_from_answer_data(p_data: Dictionary) -> String:
	return p_data.answer.type


static func get_sdp_from_answer_data(p_data: Dictionary) -> String:
	return p_data.answer.sdp


static func get_ice_candidates_from_answer_data(p_data: Dictionary) -> Array:
	return p_data.answer.ice_candidates


static func is_ice_candidate_data_valid(p_data: Variant) -> bool:
	if not p_data is Dictionary:
		push_error("Ice candidate data invalid data type")
		return false
	
	if not p_data.has("media"):
		push_error("Ice candidate data has no media")
		return false
	
	if not p_data.media is String:
		push_error("media invalid data type")
		return false
	
	if not p_data.has("index"):
		push_error("Ice candidate has no index")
		return false
	
	if not (typeof(p_data.index) in [TYPE_INT, TYPE_FLOAT]):
		push_error("index invalid data type")
		return false
	
	if not p_data.has("sdp"):
		push_error("Ice candidate has no sdp")
		return false
	
	if not p_data.sdp is String:
		push_error("Ice candidate sdp invalid data type")
		return false
	
	return true


static func get_media_from_ice_candidate_data(p_data: Dictionary) -> String:
	return p_data.media


static func get_index_from_ice_candidate_data(p_data: Dictionary) -> int:
	return int(p_data.index)


static func get_sdp_from_ice_candidate_data(p_data: Dictionary) -> String:
	return p_data.sdp


func _process(delta: float):
	socket.poll() # push error when 502 bad gateway, doesn't block anything
	
	var old_state := state
	state = socket.get_ready_state()
	if state != old_state:
		state_changed.emit()
	
	
	if WebSocketPeer.STATE_CONNECTING == state:
		connecting_time += delta
	
	if WebSocketPeer.STATE_OPEN == state:
		if WebSocketPeer.STATE_OPEN != old_state:
			_socket_connection_opened()
		
		while socket.get_available_packet_count():
			var packet := socket.get_packet()
			_received_packet(packet)
		
		up_time += delta
		if 0 < reconnect_attempts and RECONNECT_STABLE_TIME <= up_time:
			reconnect_attempts = 0
		
		if 0.0 < interval_time:
			interval_time_left -= delta
			if interval_time_left < 0.0:
				interval_time_left = interval_time
				interval_timeout.emit()
	
	
	elif WebSocketPeer.STATE_CLOSING == state:
		# Keep polling to achieve proper close.
		pass
	
	elif WebSocketPeer.STATE_CLOSED == state:
		if WebSocketPeer.STATE_CLOSED != old_state:
			_socket_connection_closed(
				old_state,
				socket.get_close_code(),
				socket.get_close_reason()
			)
		
		if is_reconnect_pending():
			reconnect_time_left -= delta
			if reconnect_time_left < 0.0:
				_reconnect()
