extends Panel
class_name AdvancedPanel

signal advanced_values_changed(
	thresholds: PackedFloat32Array,
	neighborhoods: PackedInt32Array,
	weights: PackedFloat32Array,
	channels: PackedFloat32Array,
	committed: bool
)
signal open_state_changed(is_open: bool)

@onready var header: Label = $Header
@onready var close_button: Button = $CloseButton
@onready var rows_root: VBoxContainer = $MarginContainer/ScrollContainer/VBoxContainer

var font: Font = preload("res://fonts/PixelOperator.ttf")

const THRESHOLD_FLOAT_COUNT := 32
const WEIGHT_COUNT := 16
const NEIGHBORHOOD_INT_COUNT := 8
const CHANNEL_FLOAT_COUNT := WEIGHT_COUNT * 6
const CHANNEL_VALUES_PER_RULE := 6
const CANDIDATE_COUNT := 4
const NEIGHBORHOOD_LABELS := ["A", "B", "C", "D", "E", "F", "G", "H"]
const CHANNEL_NAMES := ["red", "green", "blue"]
const ADVANCED_SLIDER_MIN := 0.0
const ADVANCED_SLIDER_MAX := 1.0
const WEIGHT_SLIDER_MIN := -1.0
const WEIGHT_SLIDER_MAX := 1.0
const ADVANCED_SLIDER_STEP := 0.0001
const ADVANCED_ROW_GAP := 12
const NEIGHBORHOOD_RING_COUNT := 12
const NEIGHBORHOOD_RING_MASK := 0xFFF
const NEIGHBORHOOD_LINE_EDIT_WIDTH := 190.0
const VALUE_LINE_EDIT_WIDTH := 100.0
const LINE_EDIT_HEIGHT := 42.0
const LINE_EDIT_FONT_SIZE := 35
const PANEL_FADE_IN_SEC := 0.08
const PANEL_FADE_OUT_SEC := 0.06
const SLIDER_KNOB_SIZE := 14
const ROW_EDGE_PAD_TOP := 4
const ROW_EDGE_PAD_RIGHT := 6
const SLIDER_TO_EDIT_GAP := 10

var _thresholds := PackedFloat32Array()
var _neighborhoods := PackedInt32Array()
var _weights := PackedFloat32Array()
var _channels := PackedFloat32Array()
var _candidate_neighborhood_counts := PackedInt32Array([2, 2, 2, 2])
var _advanced_open := false
var _advanced_candidate_index := -1
var _fade_tween: Tween
var _emit_close_on_fade := false
var _modify_slider_template: HSlider
var _slider_grabber_icon: Texture2D
var _slider_grabber_highlight_icon: Texture2D
var _slider_grabber_disabled_icon: Texture2D
var _slider_style_template: StyleBox
var _slider_grabber_area_style_template: StyleBox
var _slider_grabber_area_highlight_style_template: StyleBox


func _ready() -> void:
	visible = false
	_modify_slider_template = get_node_or_null("../ModifyPanel/MarginContainer/VBoxContainer/DeltaContainer/DeltaSlider") as HSlider
	_build_slider_styles()
	if close_button != null and not close_button.pressed.is_connected(_on_close_pressed):
		close_button.pressed.connect(_on_close_pressed)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if not (focus_owner is LineEdit):
		return
	var focused_edit := focus_owner as LineEdit
	if focused_edit == null or not is_ancestor_of(focused_edit):
		return
	if _is_point_over_any_line_edit(mb.position):
		return
	focused_edit.release_focus()


func _is_point_over_any_line_edit(screen_pos: Vector2) -> bool:
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back() as Node
		if node == null:
			continue
		for child_v in node.get_children():
			var child_node := child_v as Node
			if child_node == null:
				continue
			var edit := child_node as LineEdit
			if edit != null and edit.visible and edit.get_global_rect().has_point(screen_pos):
				return true
			stack.append(child_node)
	return false


func set_data(
	thresholds: PackedFloat32Array,
	neighborhoods: PackedInt32Array,
	weights: PackedFloat32Array,
	channels: PackedFloat32Array,
	candidate_neighborhood_counts: PackedInt32Array
) -> void:
	_thresholds = thresholds.duplicate()
	_neighborhoods = neighborhoods.duplicate()
	_weights = weights.duplicate()
	_channels = channels.duplicate()
	_candidate_neighborhood_counts = _normalize_candidate_neighborhood_counts(candidate_neighborhood_counts)

	if _neighborhoods.size() != NEIGHBORHOOD_INT_COUNT:
		var normalized_n := PackedInt32Array()
		normalized_n.resize(NEIGHBORHOOD_INT_COUNT)
		for i in range(min(_neighborhoods.size(), NEIGHBORHOOD_INT_COUNT)):
			normalized_n[i] = _neighborhoods[i]
		_neighborhoods = normalized_n
	if _thresholds.size() != THRESHOLD_FLOAT_COUNT:
		var normalized_t := PackedFloat32Array()
		normalized_t.resize(THRESHOLD_FLOAT_COUNT)
		for i in range(min(_thresholds.size(), THRESHOLD_FLOAT_COUNT)):
			normalized_t[i] = _thresholds[i]
		_thresholds = normalized_t
	if _weights.size() != WEIGHT_COUNT:
		var normalized_w := PackedFloat32Array()
		normalized_w.resize(WEIGHT_COUNT)
		for i in range(min(_weights.size(), WEIGHT_COUNT)):
			normalized_w[i] = _weights[i]
		_weights = normalized_w
	if _channels.size() != CHANNEL_FLOAT_COUNT:
		var normalized_c := PackedFloat32Array()
		normalized_c.resize(CHANNEL_FLOAT_COUNT)
		for i in range(min(_channels.size(), CHANNEL_FLOAT_COUNT)):
			normalized_c[i] = _channels[i]
		_channels = normalized_c

	if _advanced_open:
		_rebuild_rows()

func _normalize_candidate_neighborhood_counts(raw: PackedInt32Array) -> PackedInt32Array:
	var counts := PackedInt32Array([2, 2, 2, 2])
	if raw.size() != CANDIDATE_COUNT:
		return counts
	for i in range(CANDIDATE_COUNT):
		counts[i] = maxi(0, int(raw[i]))
	var total := 0
	for v in counts:
		total += int(v)
	if total != 8:
		return PackedInt32Array([2, 2, 2, 2])
	return counts

func _candidate_neighborhood_start(candidate_index: int) -> int:
	var start := 0
	for i in range(candidate_index):
		start += int(_candidate_neighborhood_counts[i])
	return start

func _candidate_threshold_range(candidate_index: int) -> Vector2i:
	var nh_start := _candidate_neighborhood_start(candidate_index)
	var nh_count := int(_candidate_neighborhood_counts[candidate_index])
	return Vector2i(nh_start * 4, nh_count * 4)

func _candidate_weight_range(candidate_index: int) -> Vector2i:
	var nh_start := _candidate_neighborhood_start(candidate_index)
	var nh_count := int(_candidate_neighborhood_counts[candidate_index])
	return Vector2i(nh_start * 2, nh_count * 2)

func _candidate_channel_range(candidate_index: int) -> Vector2i:
	var nh_start := _candidate_neighborhood_start(candidate_index)
	var nh_count := int(_candidate_neighborhood_counts[candidate_index])
	var channels_per_neighborhood := CHANNEL_VALUES_PER_RULE * 2
	return Vector2i(nh_start * channels_per_neighborhood, nh_count * channels_per_neighborhood)

func _neighborhood_label(local_neighborhood_index: int) -> String:
	if local_neighborhood_index >= 0 and local_neighborhood_index < NEIGHBORHOOD_LABELS.size():
		return str(NEIGHBORHOOD_LABELS[local_neighborhood_index])
	return "N%d" % (local_neighborhood_index + 1)

func _threshold_label(local_threshold_index: int) -> String:
	var local_neighborhood_index := int(local_threshold_index / 4)
	var within_neighborhood := local_threshold_index % 4
	var neighborhood_label := _neighborhood_label(local_neighborhood_index)
	if within_neighborhood == 0:
		return "lo%s1" % neighborhood_label
	if within_neighborhood == 1:
		return "hi%s1" % neighborhood_label
	if within_neighborhood == 2:
		return "lo%s2" % neighborhood_label
	return "hi%s2" % neighborhood_label

func _weight_label(local_weight_index: int) -> String:
	var local_neighborhood_index := int(local_weight_index / 2)
	var within_neighborhood := local_weight_index % 2
	return "%s%d" % [_neighborhood_label(local_neighborhood_index), within_neighborhood + 1]

func _channel_label(local_channel_index: int) -> String:
	var local_rule_index := int(local_channel_index / CHANNEL_VALUES_PER_RULE)
	var within_rule := local_channel_index % CHANNEL_VALUES_PER_RULE
	var local_neighborhood_index := int(local_rule_index / 2)
	var rule_in_neighborhood := (local_rule_index % 2) + 1
	var channel_name := str(CHANNEL_NAMES[within_rule % 3])
	var rw := "R" if within_rule < 3 else "W"
	return "%s_%s%s%d" % [channel_name, rw, _neighborhood_label(local_neighborhood_index), rule_in_neighborhood]


func open_for_candidate(candidate_index: int) -> void:
	if candidate_index < 0 or candidate_index >= CANDIDATE_COUNT:
		return
	var was_open := _advanced_open
	_emit_close_on_fade = false
	_advanced_open = true
	_advanced_candidate_index = candidate_index
	if header != null:
		header.text = " Advanced (C%d)" % candidate_index
	_rebuild_rows()
	if not was_open:
		open_state_changed.emit(true)
		_fade_in()
	else:
		_kill_fade_tween()
		visible = true
		modulate.a = 1.0
		move_to_front()


func hide_panel() -> void:
	if not _advanced_open and not visible:
		return
	_emit_close_on_fade = _emit_close_on_fade or _advanced_open
	_fade_out()


func is_open() -> bool:
	return _advanced_open


func _on_close_pressed() -> void:
	hide_panel()

func _build_slider_styles() -> void:
	_slider_style_template = null
	_slider_grabber_area_style_template = null
	_slider_grabber_area_highlight_style_template = null
	_slider_grabber_icon = null
	_slider_grabber_highlight_icon = null
	_slider_grabber_disabled_icon = null

	if _modify_slider_template != null:
		_slider_style_template = _duplicate_stylebox(_modify_slider_template.get_theme_stylebox("slider"))
		_slider_grabber_area_style_template = _duplicate_stylebox(_modify_slider_template.get_theme_stylebox("grabber_area"))
		_slider_grabber_area_highlight_style_template = _duplicate_stylebox(_modify_slider_template.get_theme_stylebox("grabber_area_highlight"))
		_slider_grabber_icon = _modify_slider_template.get_theme_icon("grabber")
		_slider_grabber_highlight_icon = _modify_slider_template.get_theme_icon("grabber_highlight")
		_slider_grabber_disabled_icon = _modify_slider_template.get_theme_icon("grabber_disabled")

	# Fallback for environments where the template slider is unavailable.
	if _slider_grabber_icon == null:
		_slider_grabber_icon = _make_square_icon(SLIDER_KNOB_SIZE, Color(1.0, 1.0, 1.0, 0.95))
	if _slider_grabber_highlight_icon == null:
		_slider_grabber_highlight_icon = _slider_grabber_icon
	if _slider_grabber_disabled_icon == null:
		_slider_grabber_disabled_icon = _make_square_icon(SLIDER_KNOB_SIZE, Color(0.7, 0.7, 0.7, 0.6))

func _duplicate_stylebox(style: StyleBox) -> StyleBox:
	if style == null:
		return null
	return style.duplicate(true)

func _make_square_icon(size_px: int, color: Color) -> Texture2D:
	var img := Image.create(size_px, size_px, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)

func _style_slider(slider: HSlider) -> void:
	if slider == null:
		return
	if _slider_grabber_area_style_template != null:
		slider.add_theme_stylebox_override("grabber_area", _slider_grabber_area_style_template.duplicate(true))
	if _slider_grabber_area_highlight_style_template != null:
		slider.add_theme_stylebox_override("grabber_area_highlight", _slider_grabber_area_highlight_style_template.duplicate(true))
	if _slider_style_template != null:
		slider.add_theme_stylebox_override("slider", _slider_style_template.duplicate(true))
	elif _slider_grabber_area_style_template == null:
		# Fallback style path if no template style is available.
		var left_style := _make_slider_left_style(slider)
		slider.add_theme_stylebox_override("grabber_area", left_style)
		slider.add_theme_stylebox_override("grabber_area_highlight", left_style.duplicate())
		var right_style := _make_slider_right_style(slider)
		slider.add_theme_stylebox_override("slider", right_style)

	if _slider_grabber_icon != null:
		slider.add_theme_icon_override("grabber", _slider_grabber_icon)
	if _slider_grabber_highlight_icon != null:
		slider.add_theme_icon_override("grabber_highlight", _slider_grabber_highlight_icon)
	if _slider_grabber_disabled_icon != null:
		slider.add_theme_icon_override("grabber_disabled", _slider_grabber_disabled_icon)

func _make_slider_left_style(slider: HSlider) -> StyleBoxFlat:
	var left_base := slider.get_theme_stylebox("grabber_area")
	var left := StyleBoxFlat.new()
	if left_base is StyleBoxFlat:
		left = (left_base as StyleBoxFlat).duplicate() as StyleBoxFlat
	else:
		var slider_base := slider.get_theme_stylebox("slider")
		if slider_base is StyleBoxFlat:
			left = (slider_base as StyleBoxFlat).duplicate() as StyleBoxFlat
	_square_stylebox(left)
	return left

func _make_slider_right_style(slider: HSlider) -> StyleBoxFlat:
	var right_base := slider.get_theme_stylebox("slider")
	if right_base is StyleBoxFlat:
		var right := (right_base as StyleBoxFlat).duplicate() as StyleBoxFlat
		right.bg_color = Color8(74, 74, 74, 255)
		_square_stylebox(right)
		return right
	var fallback := StyleBoxFlat.new()
	fallback.bg_color = Color8(74, 74, 74, 255)
	_square_stylebox(fallback)
	return fallback

func _square_stylebox(style: StyleBoxFlat) -> void:
	if style == null:
		return
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_right = 0
	style.corner_radius_bottom_left = 0

func _style_line_edit(edit: LineEdit) -> void:
	if edit == null:
		return
	edit.add_theme_font_override("font", font)
	edit.add_theme_font_size_override("font_size", LINE_EDIT_FONT_SIZE)
	edit.add_theme_stylebox_override("normal", _make_line_edit_normal_style())
	var normal_style := edit.get_theme_stylebox("normal")
	if normal_style != null:
		edit.add_theme_stylebox_override("focus", normal_style.duplicate(true))
	edit.alignment = HORIZONTAL_ALIGNMENT_LEFT

func _make_line_edit_normal_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color8(0, 0, 0, 109) # 0000006d
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color8(255, 255, 255, 56) # ffffff38
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_right = 0
	style.corner_radius_bottom_left = 0
	return style

func _fade_in() -> void:
	_kill_fade_tween()
	visible = true
	move_to_front()
	modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 1.0, PANEL_FADE_IN_SEC) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)

func _fade_out() -> void:
	_kill_fade_tween()
	if not visible:
		_finish_close_after_fade()
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(self, "modulate:a", 0.0, PANEL_FADE_OUT_SEC) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN)
	_fade_tween.finished.connect(_finish_close_after_fade)

func _kill_fade_tween() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

func _finish_close_after_fade() -> void:
	_kill_fade_tween()
	visible = false
	modulate.a = 1.0
	var should_emit := _emit_close_on_fade
	_emit_close_on_fade = false
	_advanced_open = false
	_advanced_candidate_index = -1
	if should_emit:
		open_state_changed.emit(false)


func _clear_rows() -> void:
	if rows_root == null:
		return
	for child_v in rows_root.get_children():
		var child := child_v as Node
		if child != null:
			child.queue_free()


func _rebuild_rows() -> void:
	if not _advanced_open:
		return
	if rows_root == null:
		return
	var c := _advanced_candidate_index
	if c < 0 or c >= CANDIDATE_COUNT:
		return
	var nh_start := _candidate_neighborhood_start(c)
	var nh_count := int(_candidate_neighborhood_counts[c])
	var thr_range := _candidate_threshold_range(c)
	var w_range := _candidate_weight_range(c)
	var ch_range := _candidate_channel_range(c)
	_clear_rows()
	_add_edge_top_padding()

	for n in range(nh_count):
		_add_neighborhood_row(nh_start + n, n)

	_add_spacer()

	for t in range(thr_range.y):
		_add_threshold_row(thr_range.x + t, t)

	_add_spacer()

	for w_i in range(w_range.y):
		_add_weight_row(w_range.x + w_i, w_i)

	_add_spacer()

	for ch_i in range(ch_range.y):
		_add_channel_row(ch_range.x + ch_i, ch_i)


func _add_spacer() -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, ADVANCED_ROW_GAP)
	rows_root.add_child(spacer)

func _add_edge_top_padding() -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, ROW_EDGE_PAD_TOP)
	rows_root.add_child(pad)

func _add_row_right_padding(row: HBoxContainer) -> void:
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(ROW_EDGE_PAD_RIGHT, 0)
	row.add_child(pad)


func _add_neighborhood_row(nh_i: int, local_index: int) -> void:
	if nh_i < 0 or nh_i >= _neighborhoods.size():
		return

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 42)

	var label := Label.new()
	label.text = " Neighborhood %s (R1..R%d)" % [_neighborhood_label(local_index), NEIGHBORHOOD_RING_COUNT]
	label.custom_minimum_size = Vector2(240, 0)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 35)
	row.add_child(label)

	var mask := _sanitize_neighborhood_mask(int(_neighborhoods[nh_i]))

	var mask_edit := LineEdit.new()
	mask_edit.custom_minimum_size = Vector2(NEIGHBORHOOD_LINE_EDIT_WIDTH, LINE_EDIT_HEIGHT)
	mask_edit.text = _neighborhood_mask_to_bits(mask)
	_style_line_edit(mask_edit)
	row.add_child(mask_edit)
	_add_row_right_padding(row)

	mask_edit.text_submitted.connect(_on_neighborhood_mask_submitted.bind(nh_i, mask_edit))
	mask_edit.focus_exited.connect(_on_neighborhood_mask_focus_exited.bind(nh_i, mask_edit))

	rows_root.add_child(row)


func _sanitize_neighborhood_mask(v: int) -> int:
	return v & NEIGHBORHOOD_RING_MASK

func _neighborhood_mask_to_bits(mask: int) -> String:
	var out := ""
	for ring_i in range(NEIGHBORHOOD_RING_COUNT):
		if ((mask >> ring_i) & 1) != 0:
			out += "1"
		else:
			out += "0"
	return out

func _parse_neighborhood_mask_text(text: String, fallback: int) -> int:
	var trimmed := text.strip_edges()
	if trimmed.is_empty():
		return fallback
	if trimmed.length() == NEIGHBORHOOD_RING_COUNT:
		var mask := 0
		for i in range(NEIGHBORHOOD_RING_COUNT):
			var ch := trimmed.substr(i, 1)
			if ch == "1":
				mask |= (1 << i)
			elif ch != "0":
				mask = -1
				break
		if mask >= 0:
			return _sanitize_neighborhood_mask(mask)
	return _sanitize_neighborhood_mask(int(round(trimmed.to_float())))

func _on_neighborhood_mask_submitted(_text: String, nh_i: int, mask_edit: LineEdit) -> void:
	_commit_neighborhood_mask(nh_i, mask_edit)

func _on_neighborhood_mask_focus_exited(nh_i: int, mask_edit: LineEdit) -> void:
	_commit_neighborhood_mask(nh_i, mask_edit)

func _commit_neighborhood_mask(nh_i: int, mask_edit: LineEdit) -> void:
	if nh_i < 0 or nh_i >= _neighborhoods.size():
		return
	var fallback := _sanitize_neighborhood_mask(int(_neighborhoods[nh_i]))
	var mask := _parse_neighborhood_mask_text(mask_edit.text, fallback)
	_neighborhoods[nh_i] = mask
	mask_edit.text = _neighborhood_mask_to_bits(mask)
	_emit_values_update(true)

func _add_threshold_row(idx: int, local_index: int) -> void:
	if idx < 0 or idx >= _thresholds.size():
		return
	var row := _make_slider_lineedit_row(" %s" % _threshold_label(local_index), _thresholds[idx], idx, true, false)
	rows_root.add_child(row)


func _add_weight_row(idx: int, local_index: int) -> void:
	if idx < 0 or idx >= _weights.size():
		return
	var row := _make_slider_lineedit_row(" weight%s" % _weight_label(local_index), _weights[idx], idx, false, false)
	rows_root.add_child(row)

func _add_channel_row(idx: int, local_index: int) -> void:
	if idx < 0 or idx >= _channels.size():
		return
	var row := _make_slider_lineedit_row(" %s" % _channel_label(local_index), _channels[idx], idx, false, true)
	rows_root.add_child(row)

func _make_slider_lineedit_row(label_text: String, value: float, index: int, is_threshold: bool, is_channel: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.custom_minimum_size = Vector2(0, 42)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(200, 0)
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 35)
	row.add_child(label)

	var slider := HSlider.new()
	var slider_bounds := _slider_bounds(is_threshold, is_channel)
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size = Vector2(220, 30)
	slider.min_value = slider_bounds.x
	slider.max_value = slider_bounds.y
	slider.step = ADVANCED_SLIDER_STEP
	slider.set_value_no_signal(clampf(value, slider_bounds.x, slider_bounds.y))
	_style_slider(slider)
	row.add_child(slider)

	var edit := LineEdit.new()
	edit.custom_minimum_size = Vector2(VALUE_LINE_EDIT_WIDTH, LINE_EDIT_HEIGHT)
	edit.text = "%.4f" % slider.value
	_style_line_edit(edit)
	var edit_wrap := MarginContainer.new()
	edit_wrap.add_theme_constant_override("margin_left", SLIDER_TO_EDIT_GAP)
	edit_wrap.add_child(edit)
	row.add_child(edit_wrap)
	_add_row_right_padding(row)

	slider.value_changed.connect(_on_slider_value_changed.bind(edit, index, is_threshold, is_channel))
	slider.drag_ended.connect(_on_slider_drag_ended.bind(index, is_threshold, is_channel))
	edit.text_submitted.connect(_on_value_submitted.bind(slider, edit, index, is_threshold, is_channel))
	edit.focus_exited.connect(_on_value_focus_exited.bind(slider, edit, index, is_threshold, is_channel))
	return row


func _on_slider_value_changed(v: float, edit: LineEdit, index: int, is_threshold: bool, is_channel: bool) -> void:
	var slider_bounds := _slider_bounds(is_threshold, is_channel)
	var u := clampf(v, slider_bounds.x, slider_bounds.y)
	edit.text = "%.4f" % u
	_set_value_from_ui(index, is_threshold, is_channel, u)
	_emit_values_update(false)


func _on_slider_drag_ended(value_changed: bool, _index: int, _is_threshold: bool, _is_channel: bool) -> void:
	if not value_changed:
		return
	_emit_values_update(true)


func _on_value_submitted(_text: String, slider: HSlider, edit: LineEdit, index: int, is_threshold: bool, is_channel: bool) -> void:
	_commit_value_edit(slider, edit, index, is_threshold, is_channel)


func _on_value_focus_exited(slider: HSlider, edit: LineEdit, index: int, is_threshold: bool, is_channel: bool) -> void:
	_commit_value_edit(slider, edit, index, is_threshold, is_channel)


func _commit_value_edit(slider: HSlider, edit: LineEdit, index: int, is_threshold: bool, is_channel: bool) -> void:
	var slider_bounds := _slider_bounds(is_threshold, is_channel)
	var u := clampf(edit.text.to_float(), slider_bounds.x, slider_bounds.y)
	slider.set_value_no_signal(u)
	edit.text = "%.4f" % u
	_set_value_from_ui(index, is_threshold, is_channel, u)
	_emit_values_update(true)


func _set_value_from_ui(index: int, is_threshold: bool, is_channel: bool, ui_value: float) -> void:
	var slider_bounds := _slider_bounds(is_threshold, is_channel)
	var u := clampf(ui_value, slider_bounds.x, slider_bounds.y)
	if is_threshold:
		if index >= 0 and index < _thresholds.size():
			_thresholds[index] = u
	elif is_channel:
		if index >= 0 and index < _channels.size():
			_channels[index] = u
	else:
		if index >= 0 and index < _weights.size():
			_weights[index] = u


func _slider_bounds(is_threshold: bool, is_channel: bool) -> Vector2:
	if not is_threshold and not is_channel:
		return Vector2(WEIGHT_SLIDER_MIN, WEIGHT_SLIDER_MAX)
	return Vector2(ADVANCED_SLIDER_MIN, ADVANCED_SLIDER_MAX)


func _emit_values_update(committed: bool) -> void:
	advanced_values_changed.emit(
		_thresholds.duplicate(),
		_neighborhoods.duplicate(),
		_weights.duplicate(),
		_channels.duplicate(),
		committed
	)
