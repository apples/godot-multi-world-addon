@tool
extends Control
class_name RemoteSubViewportPanel
## A container that displays the contents of underlying SubViewport child nodes.
## It uses the combined size of the SubViewports as minimum size, unless stretch is enabled.
##
## Note: Changing a RemoteSubViewportPanel's Control.scale will cause its contents to appear
## distorted. To change its visual size without causing distortion, adjust the node's margins
## instead (if it's not already in a container).
##
## Note: The RemoteSubViewportPanel forwards mouse-enter and mouse-exit notifications
## to its sub-viewports.


## The SubViewport to display.
@export var sub_viewport: SubViewport: set = set_sub_viewport

## If true, the sub_viewport will be automatically resized to the control's size.
## Note: If true, this will prohibit changing sub_viewport.size manually.
@export var stretch: bool = false: set = set_stretch

## Divides the sub_viewport's effective resolution by this value while preserving its scale.
## This can be used to speed up rendering.
## For example, a 1280×720 sub_viewport with stretch_shrink set to 2 will be rendered at 640×360
## while occupying the same size in the container.
## Note: stretch must be true for this property to work.
@export_range(1, 32, 1, "or_greater") var stretch_shrink: int = 1: set = set_stretch_shrink

## Configure, if either the RemoteSubViewportPanel or alternatively the Control nodes of its
## SubViewport children should be available as targets of mouse-related functionalities, like
## identifying the drop target in drag-and-drop operations or cursor shape of hovered Control node.
## If false, the Control nodes inside its SubViewport children are considered as targets.
## If true, the RemoteSubViewportPanel itself will be considered as a target.
@export var mouse_target: bool = false: set = set_mouse_target


var _is_hovered: bool = false


func _init() -> void:
	set_process_input(false)
	set_process_unhandled_input(true)
	set_focus_mode(FOCUS_CLICK)


func _ready() -> void:
	focus_entered.connect(_focus_entered)
	focus_exited.connect(_focus_exited)
	visibility_changed.connect(_update_visibility)
	resized.connect(_resized)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _enter_tree() -> void:
	_update_visibility()


func _get_minimum_size() -> Vector2:
	if stretch:
		return Vector2()
	var ms := Vector2()
	if sub_viewport:
		ms = ms.max(sub_viewport.get_size())
	return ms


func set_sub_viewport(p_sub_viewport: SubViewport) -> void:
	if p_sub_viewport == sub_viewport:
		return
	if sub_viewport:
		if _is_hovered:
			sub_viewport.notify_mouse_exited()
		sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		sub_viewport.handle_input_locally = true
	sub_viewport = p_sub_viewport
	if sub_viewport:
		sub_viewport.handle_input_locally = false
		if _is_hovered:
			sub_viewport.notify_mouse_entered()
	_update_visibility()
	queue_redraw()


func set_stretch(p_enable: bool) -> void:
	if stretch == p_enable:
		return
	stretch = p_enable
	recalc_force_viewport_sizes()
	update_minimum_size()
	queue_redraw()


func is_stretch_enabled() -> bool:
	return stretch


func set_stretch_shrink(p_shrink: int) -> void:
	if p_shrink < 1:
		push_error("Shrink value must be >= 1")
		return
	if stretch_shrink == p_shrink:
		return
	stretch_shrink = p_shrink
	recalc_force_viewport_sizes()
	queue_redraw()


func recalc_force_viewport_sizes() -> void:
	if not stretch:
		return
	if sub_viewport:
		sub_viewport.size = get_size() / stretch_shrink


func _get_allowed_size_flags_horizontal() -> PackedInt32Array:
	return PackedInt32Array()


func _get_allowed_size_flags_vertical() -> PackedInt32Array:
	return PackedInt32Array()


func _resized() -> void:
	recalc_force_viewport_sizes()


func _update_visibility() -> void:
	if sub_viewport:
		if is_visible_in_tree():
			sub_viewport.set_update_mode(SubViewport.UPDATE_ALWAYS)
		else:
			sub_viewport.set_update_mode(SubViewport.UPDATE_DISABLED)


func _draw() -> void:
	if sub_viewport:
		if stretch:
			draw_texture_rect(sub_viewport.get_texture(), Rect2(Vector2(), get_size()), false)
		else:
			draw_texture_rect(sub_viewport.get_texture(), Rect2(Vector2(), sub_viewport.get_size()), false)
	
	if OS.is_debug_build():
		var f = get_theme_default_font()
		var fs = get_theme_default_font_size()
		var s = str(sub_viewport.get_path()) if sub_viewport else "<no sub_viewport>"
		var ss = f.get_string_size(s, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs)
		var a = f.get_ascent(fs)
		var p = Vector2(size.x - ss.x, 0)
		draw_rect(Rect2(p, ss), Color.BLACK)
		draw_string(f, Vector2(p.x, a), s, HORIZONTAL_ALIGNMENT_RIGHT, -1, fs, Color.WHITE)


func _focus_entered() -> void:
	# If focused, send InputEvent to the SubViewport before the Gui-Input stage.
	set_process_input(true)
	set_process_unhandled_input(false)


func _focus_exited() -> void:
	# A different Control has focus and should receive Gui-Input before the
	# InputEvent is sent to the SubViewport.
	set_process_input(false)
	set_process_unhandled_input(true)


func _input(p_event: InputEvent) -> void:
	_propagate_nonpositional_event(p_event)


func _unhandled_input(p_event: InputEvent) -> void:
	_propagate_nonpositional_event(p_event)


func _propagate_nonpositional_event(p_event: InputEvent) -> void:
	if p_event == null:
		push_error("p_event is null")
		return
	
	if Engine.is_editor_hint():
		return
	
	if _is_propagated_in_gui_input(p_event):
		return
	
	if not _propagate_input_event(p_event):
		return
	
	_send_event_to_viewport(p_event)


func _gui_input(p_event: InputEvent) -> void:
	if p_event == null:
		push_error("p_event is null")
		return

	if Engine.is_editor_hint():
		return

	if not _is_propagated_in_gui_input(p_event):
		return

	if not _propagate_input_event(p_event):
		return

	if stretch and stretch_shrink > 1:
		var xform := Transform2D()
		xform = xform.scaled(Vector2(1.0, 1.0) / float(stretch_shrink))
		_send_event_to_viewport(p_event.xformed_by(xform))
	else:
		_send_event_to_viewport(p_event)


func _on_mouse_entered() -> void:
	_is_hovered = true
	if sub_viewport:
		sub_viewport.notify_mouse_entered()


func _on_mouse_exited() -> void:
	_is_hovered = false
	if sub_viewport:
		sub_viewport.notify_mouse_exited()


func _send_event_to_viewport(p_event: InputEvent) -> void:
	if not sub_viewport or sub_viewport.gui_disable_input:
		return
	sub_viewport.push_input(p_event)


func _is_propagated_in_gui_input(p_event: InputEvent) -> bool:
	# Propagation of events with a position property happen in gui_input.
	# Propagation of other events happen in input.
	if p_event is InputEventMouse \
			or p_event is InputEventScreenDrag \
			or p_event is InputEventScreenTouch \
			or p_event is InputEventGesture:
		return true
	return false


func set_mouse_target(p_enable: bool) -> void:
	mouse_target = p_enable


func is_mouse_target_enabled() -> bool:
	return mouse_target


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	
	if not sub_viewport:
		warnings.push_back("This node doesn't have a sub_viewport assigned, so it can't display its intended content.")
	
	if get_default_cursor_shape() != Control.CURSOR_ARROW:
		warnings.push_back("The default mouse cursor shape of SubViewportContainer has no effect.\nConsider leaving it at its initial value `CURSOR_ARROW`.")
	
	return warnings


## Override in a subclass to control whether a given event is forwarded to the sub_viewport.
## Return false to suppress forwarding, true to allow it.
@warning_ignore("unused_parameter")
func _propagate_input_event(event: InputEvent) -> bool:
	return true
