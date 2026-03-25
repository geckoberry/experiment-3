class_name InputController
extends RefCounted

var host: Control
var tex_rect: TextureRect
var ui_root: Control
var top_bar: Control
var modify_panel: Control
var advanced_panel: Control
var ruleset_popup: PopupPanel
var save_panel: Control
var undo_btn: BaseButton
var redo_btn: BaseButton
var clear_btn: BaseButton
var reset_btn: BaseButton
var random_btn: BaseButton
var previous_btn: BaseButton
var save_as_btn: BaseButton
var save_btn: BaseButton
var confirm_btn: BaseButton

var W := 1
var H := 1
var trackpad_scroll_sensitivity := 0.06
const ENABLE_BRUSH_MODE_5 := false

var _pending_undo_redo_action := "" # "", "undo", "redo"
var _pending_button_shortcut_action := "" # generic button shortcut action id
var _pending_button_shortcut_keycode := -1
var _brush_mode := 1 # 1 = paint, 2 = erase, 3 = expel, 4 = vacuum, 5 = dead-shape stamp

var on_toggle_pause: Callable
var on_toggle_ui_chrome: Callable
var on_clear: Callable
var on_reset: Callable
var on_randomize: Callable
var on_previous: Callable
var on_view_switch: Callable
var on_undo: Callable
var on_redo: Callable
var can_undo: Callable
var can_redo: Callable
var on_set_brush_active: Callable
var on_adjust_brush_radius: Callable
var on_set_brush_center: Callable
var on_zoom_sim_view: Callable
var on_pan_sim_view: Callable
var on_save_as: Callable
var on_save: Callable
var on_save_confirm: Callable
var on_stamp_brush_once: Callable


func init(
	p_host: Control,
	p_tex_rect: TextureRect,
	p_ui_root: Control,
	p_top_bar: Control,
	p_modify_panel: Control,
	p_advanced_panel: Control,
	p_ruleset_popup: PopupPanel,
	p_save_panel: Control,
	p_undo_btn: BaseButton,
	p_redo_btn: BaseButton,
	p_clear_btn: BaseButton,
	p_reset_btn: BaseButton,
	p_random_btn: BaseButton,
	p_previous_btn: BaseButton,
	p_save_as_btn: BaseButton,
	p_save_btn: BaseButton,
	p_confirm_btn: BaseButton,
	p_w: int,
	p_h: int,
	p_trackpad_scroll_sensitivity: float,
	p_on_toggle_pause: Callable,
	p_on_toggle_ui_chrome: Callable,
	p_on_clear: Callable,
	p_on_reset: Callable,
	p_on_randomize: Callable,
	p_on_previous: Callable,
	p_on_view_switch: Callable,
	p_on_undo: Callable,
	p_on_redo: Callable,
	p_can_undo: Callable,
	p_can_redo: Callable,
	p_on_set_brush_active: Callable,
	p_on_adjust_brush_radius: Callable,
	p_on_set_brush_center: Callable,
	p_on_zoom_sim_view: Callable,
	p_on_pan_sim_view: Callable,
	p_on_save_as: Callable,
	p_on_save: Callable,
	p_on_save_confirm: Callable,
	p_on_stamp_brush_once: Callable
) -> void:
	host = p_host
	tex_rect = p_tex_rect
	ui_root = p_ui_root
	top_bar = p_top_bar
	modify_panel = p_modify_panel
	advanced_panel = p_advanced_panel
	ruleset_popup = p_ruleset_popup
	save_panel = p_save_panel
	undo_btn = p_undo_btn
	redo_btn = p_redo_btn
	clear_btn = p_clear_btn
	reset_btn = p_reset_btn
	random_btn = p_random_btn
	previous_btn = p_previous_btn
	save_as_btn = p_save_as_btn
	save_btn = p_save_btn
	confirm_btn = p_confirm_btn
	W = p_w
	H = p_h
	trackpad_scroll_sensitivity = p_trackpad_scroll_sensitivity
	on_toggle_pause = p_on_toggle_pause
	on_toggle_ui_chrome = p_on_toggle_ui_chrome
	on_clear = p_on_clear
	on_reset = p_on_reset
	on_randomize = p_on_randomize
	on_previous = p_on_previous
	on_view_switch = p_on_view_switch
	on_undo = p_on_undo
	on_redo = p_on_redo
	can_undo = p_can_undo
	can_redo = p_can_redo
	on_set_brush_active = p_on_set_brush_active
	on_adjust_brush_radius = p_on_adjust_brush_radius
	on_set_brush_center = p_on_set_brush_center
	on_zoom_sim_view = p_on_zoom_sim_view
	on_pan_sim_view = p_on_pan_sim_view
	on_save_as = p_on_save_as
	on_save = p_on_save
	on_save_confirm = p_on_save_confirm
	on_stamp_brush_once = p_on_stamp_brush_once


func handle_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_SPACE:
			if not _is_text_input_focused():
				if on_toggle_pause.is_valid():
					on_toggle_pause.call()
				if host != null:
					host.accept_event()
			return true

		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_F1:
			if save_panel != null and save_panel.visible:
				if host != null:
					host.accept_event()
				return true
			if on_toggle_ui_chrome.is_valid():
				on_toggle_ui_chrome.call()
			elif ui_root != null:
				ui_root.visible = not ui_root.visible
			if host != null:
				host.accept_event()
			return true

		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_1 or key_event.keycode == KEY_KP_1):
			if _is_text_input_focused() or _ui_is_blocking_input():
				return false
			_set_brush_mode(1)
			if host != null:
				host.accept_event()
			return true

		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_2 or key_event.keycode == KEY_KP_2):
			if _is_text_input_focused() or _ui_is_blocking_input():
				return false
			_set_brush_mode(2)
			if host != null:
				host.accept_event()
			return true

		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_4 or key_event.keycode == KEY_KP_4):
			if _is_text_input_focused() or _ui_is_blocking_input():
				return false
			_set_brush_mode(4)
			if host != null:
				host.accept_event()
			return true

		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_3 or key_event.keycode == KEY_KP_3):
			if _is_text_input_focused() or _ui_is_blocking_input():
				return false
			_set_brush_mode(3)
			if host != null:
				host.accept_event()
			return true

		if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_5 or key_event.keycode == KEY_KP_5):
			if _is_text_input_focused() or _ui_is_blocking_input():
				return false
			if not ENABLE_BRUSH_MODE_5:
				if host != null:
					host.accept_event()
				return true
			_set_brush_mode(5)
			if host != null:
				host.accept_event()
			return true

		if key_event.pressed and (key_event.keycode == KEY_UP or key_event.keycode == KEY_DOWN):
			if _is_text_input_focused() or _ui_is_blocking_input():
				return false
			_adjust_brush_radius(2.0 if key_event.keycode == KEY_UP else -2.0)
			if host != null:
				host.accept_event()
			return true

	if _handle_button_shortcuts(event):
		return true
	if _handle_undo_redo_shortcuts(event):
		return true

	if _ui_is_blocking_input():
		_set_brush_active(false, _brush_mode)
		return true

	if not (event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventPanGesture):
		return false

	var pos: Vector2
	if event is InputEventPanGesture:
		pos = host.get_viewport().get_mouse_position()
	else:
		pos = (event as InputEventMouse).position

	if _mouse_over_undo_redo_buttons(pos):
		_set_brush_active(false, _brush_mode)
		return true
	if _mouse_over_top_ui(pos):
		_set_brush_active(false, _brush_mode)
		return true
	if _mouse_over_modify_panel(pos):
		_set_brush_active(false, _brush_mode)
		return true
	if _mouse_over_advanced_panel(pos):
		_set_brush_active(false, _brush_mode)
		return true
	if not _mouse_over_texture_rect(pos):
		_set_brush_active(false, _brush_mode)
		return true

	if event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		_zoom_sim_view(pos, -pan.delta.y * trackpad_scroll_sensitivity)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if _brush_mode == 5:
				if mb.pressed:
					_stamp_brush_once(pos, _brush_mode)
				_set_brush_active(false, _brush_mode)
			else:
				_set_brush_active(mb.pressed, _brush_mode)
				_set_brush_center(pos)
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_set_brush_active(false, _brush_mode)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_sim_view(pos, 1.0)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_sim_view(pos, -1.0)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_set_brush_active(false, _brush_mode)
			_pan_sim_view(motion.relative)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			if _brush_mode != 5:
				_set_brush_center(pos)

	return true


func _set_brush_active(active: bool, mode: int) -> void:
	if on_set_brush_active.is_valid():
		on_set_brush_active.call(active, mode)

func _set_brush_mode(mode: int) -> void:
	if mode == 5 and not ENABLE_BRUSH_MODE_5:
		return
	_brush_mode = _sanitize_brush_mode(mode)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _brush_mode == 5:
			_set_brush_active(false, _brush_mode)
		else:
			_set_brush_active(true, _brush_mode)


func get_brush_mode() -> int:
	return _brush_mode

func _sanitize_brush_mode(mode: int) -> int:
	if mode == 5 and not ENABLE_BRUSH_MODE_5:
		return 1
	match mode:
		1, 2, 3, 4, 5:
			return mode
		_:
			return 1


func _adjust_brush_radius(delta: float) -> void:
	if on_adjust_brush_radius.is_valid():
		on_adjust_brush_radius.call(delta)


func _set_brush_center(screen_pos: Vector2) -> void:
	var t: Vector2i = _screen_to_texel(screen_pos)
	if t.x < 0:
		return
	if on_set_brush_center.is_valid():
		on_set_brush_center.call(t.x, t.y)


func _stamp_brush_once(screen_pos: Vector2, mode: int) -> void:
	if mode == 5 and not ENABLE_BRUSH_MODE_5:
		return
	var t: Vector2i = _screen_to_texel(screen_pos)
	if t.x < 0:
		return
	if on_stamp_brush_once.is_valid():
		on_stamp_brush_once.call(t.x, t.y, mode)


func _zoom_sim_view(screen_pos: Vector2, steps: float) -> void:
	if on_zoom_sim_view.is_valid():
		on_zoom_sim_view.call(screen_pos, steps)


func _pan_sim_view(delta: Vector2) -> void:
	if on_pan_sim_view.is_valid():
		on_pan_sim_view.call(delta)

func is_mouse_over_sim(screen_pos: Vector2) -> bool:
	if host == null or tex_rect == null:
		return false
	if _ui_is_blocking_input():
		return false
	if _mouse_over_undo_redo_buttons(screen_pos):
		return false
	if _mouse_over_top_ui(screen_pos):
		return false
	if _mouse_over_modify_panel(screen_pos):
		return false
	if _mouse_over_advanced_panel(screen_pos):
		return false
	return _mouse_over_texture_rect(screen_pos)


func _screen_to_texel(screen_pos: Vector2) -> Vector2i:
	var local := tex_rect.get_global_transform_with_canvas().affine_inverse() * screen_pos
	var rect := tex_rect.get_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2i(-1, -1)

	var u: float = local.x / rect.size.x
	var v: float = local.y / rect.size.y
	if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
		return Vector2i(-1, -1)

	var x := int(floor(u * float(W)))
	var y := int(floor(v * float(H)))
	x = clamp(x, 0, W - 1)
	y = clamp(y, 0, H - 1)
	return Vector2i(x, y)


func _ui_is_blocking_input() -> bool:
	if ui_root != null and not ui_root.visible:
		return false
	if ruleset_popup != null and ruleset_popup.visible:
		return true
	if save_panel != null and save_panel.visible:
		return true
	return false


func _is_text_input_focused() -> bool:
	if host == null:
		return false
	var focus_owner := host.get_viewport().gui_get_focus_owner()
	return (focus_owner is LineEdit) or (focus_owner is TextEdit)


func _mouse_over_texture_rect(screen_pos: Vector2) -> bool:
	var local: Vector2 = tex_rect.get_global_transform_with_canvas().affine_inverse() * screen_pos
	return Rect2(Vector2.ZERO, tex_rect.size).has_point(local)


func _mouse_over_modify_panel(screen_pos: Vector2) -> bool:
	if ui_root != null and not ui_root.visible:
		return false
	if modify_panel == null or not modify_panel.visible:
		return false
	return modify_panel.get_global_rect().has_point(screen_pos)


func _mouse_over_advanced_panel(screen_pos: Vector2) -> bool:
	if ui_root != null and not ui_root.visible:
		return false
	if advanced_panel == null or not advanced_panel.visible:
		return false
	return advanced_panel.get_global_rect().has_point(screen_pos)


func _mouse_over_top_ui(screen_pos: Vector2) -> bool:
	if ui_root != null and not ui_root.visible:
		return false
	if top_bar != null and top_bar.visible and top_bar.get_global_rect().has_point(screen_pos):
		return true
	return false


func _mouse_over_undo_redo_buttons(screen_pos: Vector2) -> bool:
	if undo_btn != null and undo_btn.is_visible_in_tree() and undo_btn.get_global_rect().has_point(screen_pos):
		return true
	if redo_btn != null and redo_btn.is_visible_in_tree() and redo_btn.get_global_rect().has_point(screen_pos):
		return true
	return false


func _handle_undo_redo_shortcuts(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if key_event.echo:
		return false
	if key_event.keycode != KEY_Z:
		return false

	if key_event.pressed:
		if not _is_primary_shortcut_modifier_pressed(key_event):
			return false
		if _is_text_input_focused():
			return false
		if save_panel != null and save_panel.visible:
			return false

		if key_event.shift_pressed:
			if _can_redo():
				_pending_undo_redo_action = "redo"
				_set_shortcut_button_visual(redo_btn, true)
				host.accept_event()
				return true
			return false

		if _can_undo():
			_pending_undo_redo_action = "undo"
			_set_shortcut_button_visual(undo_btn, true)
			host.accept_event()
			return true
		return false

	if _pending_undo_redo_action == "undo":
		_set_shortcut_button_visual(undo_btn, false)
		_pending_undo_redo_action = ""
		if _can_undo():
			if on_undo.is_valid():
				on_undo.call()
			host.accept_event()
			return true
		return false
	if _pending_undo_redo_action == "redo":
		_set_shortcut_button_visual(redo_btn, false)
		_pending_undo_redo_action = ""
		if _can_redo():
			if on_redo.is_valid():
				on_redo.call()
			host.accept_event()
			return true
		return false
	return false


func _handle_button_shortcuts(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key_event := event as InputEventKey
	if key_event.echo:
		return false

	if key_event.pressed:
		var key_id := _button_shortcut_key_id_from_event(key_event)
		var action := _button_shortcut_action_from_press_event(key_event, key_id)
		if action == "":
			return false
		if not _can_start_button_shortcut(action):
			return false
		_set_pending_button_shortcut(action, key_id)
		if host != null:
			host.accept_event()
		return true

	if _pending_button_shortcut_action == "":
		return false
	var release_key_id := _button_shortcut_key_id_from_event(key_event)
	if _pending_button_shortcut_keycode != -1 and _pending_button_shortcut_keycode != release_key_id:
		return false

	var execute_action := _pending_button_shortcut_action
	var btn := _button_for_button_shortcut_action(execute_action)
	_set_shortcut_button_visual(btn, false)
	_pending_button_shortcut_action = ""
	_pending_button_shortcut_keycode = -1

	if _can_execute_button_shortcut(execute_action):
		_execute_button_shortcut_action(execute_action)
	if host != null:
		host.accept_event()
	return true

func _button_shortcut_key_id_from_event(key_event: InputEventKey) -> int:
	var direct := key_event.keycode
	if _is_button_shortcut_keycode(direct):
		return direct
	var physical := key_event.physical_keycode
	if _is_button_shortcut_keycode(physical):
		return physical
	var label := key_event.key_label
	if _is_button_shortcut_keycode(label):
		return label
	return direct


func _set_pending_button_shortcut(action: String, keycode: int) -> void:
	if _pending_button_shortcut_action != "":
		var old_btn := _button_for_button_shortcut_action(_pending_button_shortcut_action)
		_set_shortcut_button_visual(old_btn, false)
	_pending_button_shortcut_action = action
	_pending_button_shortcut_keycode = keycode
	var btn := _button_for_button_shortcut_action(action)
	_set_shortcut_button_visual(btn, true)


func _button_shortcut_action_from_press_event(key_event: InputEventKey, key_id: int) -> String:
	if _is_enter_keycode(key_id):
		return "save_confirm" if save_panel != null and save_panel.visible else ""
	if key_id == KEY_S and _is_primary_shortcut_modifier_pressed(key_event):
		return "save_as" if key_event.shift_pressed else "save"
	return _button_shortcut_action_from_keycode(key_id)


func _button_shortcut_action_from_keycode(keycode: int) -> String:
	match keycode:
		KEY_C:
			return "clear"
		KEY_R:
			return "reset"
		KEY_RIGHT:
			return "randomize"
		KEY_LEFT:
			return "previous"
		KEY_V:
			return "view_switch"
		_:
			return ""


func _is_button_shortcut_keycode(keycode: int) -> bool:
	match keycode:
		KEY_C, KEY_R, KEY_RIGHT, KEY_LEFT, KEY_V, KEY_S, KEY_ENTER, KEY_KP_ENTER:
			return true
		_:
			return false


func _is_enter_keycode(keycode: int) -> bool:
	return keycode == KEY_ENTER or keycode == KEY_KP_ENTER


func _is_primary_shortcut_modifier_pressed(key_event: InputEventKey) -> bool:
	if _is_macos():
		return key_event.meta_pressed
	return key_event.ctrl_pressed


func _is_macos() -> bool:
	return OS.get_name() == "macOS"


func _can_start_button_shortcut(action: String) -> bool:
	match action:
		"save", "save_as":
			var btn := _button_for_button_shortcut_action(action)
			return btn != null and not btn.disabled
		"save_confirm":
			var btn := _button_for_button_shortcut_action(action)
			return save_panel != null and save_panel.visible and btn != null and not btn.disabled
		_:
			if _is_text_input_focused() or _ui_is_blocking_input():
				return false
			var btn := _button_for_button_shortcut_action(action)
			return btn != null and not btn.disabled


func _can_execute_button_shortcut(action: String) -> bool:
	var btn := _button_for_button_shortcut_action(action)
	if action == "save_confirm":
		return save_panel != null and save_panel.visible and btn != null and not btn.disabled
	return btn != null and not btn.disabled


func _execute_button_shortcut_action(action: String) -> void:
	match action:
		"clear":
			if on_clear.is_valid():
				on_clear.call()
		"reset":
			if on_reset.is_valid():
				on_reset.call()
		"randomize":
			if on_randomize.is_valid():
				on_randomize.call()
		"previous":
			if on_previous.is_valid():
				on_previous.call()
		"view_switch":
			if on_view_switch.is_valid():
				on_view_switch.call()
			elif modify_panel != null and modify_panel.has_method("is_split_mode") and modify_panel.has_method("set_split_mode"):
				var split_enabled := bool(modify_panel.call("is_split_mode"))
				modify_panel.call("set_split_mode", not split_enabled, true)
		"save":
			if on_save.is_valid():
				on_save.call()
		"save_as":
			if on_save_as.is_valid():
				on_save_as.call()
		"save_confirm":
			if on_save_confirm.is_valid():
				on_save_confirm.call()
		_:
			return


func _button_for_button_shortcut_action(action: String) -> BaseButton:
	match action:
		"clear":
			return clear_btn
		"reset":
			return reset_btn
		"randomize":
			return random_btn
		"previous":
			return previous_btn
		"view_switch":
			return _split_button_for_shortcut()
		"save":
			return save_btn
		"save_as":
			return save_as_btn
		"save_confirm":
			return confirm_btn
		_:
			return null


func _split_button_for_shortcut() -> BaseButton:
	if modify_panel == null:
		return null
	var node := modify_panel.get_node_or_null("MarginContainer/VBoxContainer/MiscContainer/SplitButton")
	return node as BaseButton


func _set_shortcut_button_visual(btn: BaseButton, pressed: bool) -> void:
	if btn == null:
		return
	btn.toggle_mode = true
	btn.set_pressed_no_signal(pressed)
	if not pressed:
		btn.toggle_mode = false


func _can_undo() -> bool:
	if can_undo.is_valid():
		return bool(can_undo.call())
	return false


func _can_redo() -> bool:
	if can_redo.is_valid():
		return bool(can_redo.call())
	return false
