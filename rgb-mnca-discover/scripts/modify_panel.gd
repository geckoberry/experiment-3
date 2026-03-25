extends Panel
class_name ModifyPanel

signal candidate_toggled(candidate_index: int, enabled: bool)
signal seed_bias_changed(value: float)
signal seed_bias_committed(value: float)
signal blend_value_changed(value: float)
signal blend_value_committed(value: float)
signal decay_rate_changed(value: float)
signal decay_rate_committed(value: float)
signal parent_action_pressed(kind: String, candidate_index: int, flip_chance: float)
signal random_delta_requested(target: String, flip_chance: float)
signal split_toggled(enabled: bool)
signal shuffle_channels_requested
signal ruleset_name_changed(text: String)
signal advanced_values_changed(
	thresholds: PackedFloat32Array,
	neighborhoods: PackedInt32Array,
	weights: PackedFloat32Array,
	channels: PackedFloat32Array,
	committed: bool
)

@onready var tree: Tree = $MarginContainer/VBoxContainer/Tree
@onready var margin_container: MarginContainer = $MarginContainer
@onready var rows_container: VBoxContainer = $MarginContainer/VBoxContainer
@onready var padding2: Control = $MarginContainer/VBoxContainer/Padding2
@onready var misc_container: HBoxContainer = $MarginContainer/VBoxContainer/MiscContainer
@onready var delta_container: HBoxContainer = $MarginContainer/VBoxContainer/DeltaContainer
@onready var flip_chance_slider: HSlider = $MarginContainer/VBoxContainer/DeltaContainer/DeltaSlider
@onready var flip_chance_value: LineEdit = $MarginContainer/VBoxContainer/DeltaContainer/DeltaValue
@onready var all_button: Button = $MarginContainer/VBoxContainer/DeltaButtonContainer/AllButton
@onready var thresh_button: Button = $MarginContainer/VBoxContainer/DeltaButtonContainer/ThreshButton
@onready var nbrhd_button: Button = $MarginContainer/VBoxContainer/DeltaButtonContainer/NbrhdButton
@onready var weights_button: Button = $MarginContainer/VBoxContainer/DeltaButtonContainer/WeightsButton
@onready var channel_button: Button = $MarginContainer/VBoxContainer/DeltaButtonContainer/ChannelButton
@onready var split_button: Button = $MarginContainer/VBoxContainer/MiscContainer/SplitButton
@onready var shuffle_button: Button = $MarginContainer/VBoxContainer/MiscContainer/ShuffleButton
@onready var accordion_button: Button = $AccordionButton
@onready var header_label: Label = $Header
@onready var seed_bias_slider: HSlider = $MarginContainer/VBoxContainer/SeedBiasContainer/SeedBiasSlider
@onready var seed_bias_value: LineEdit = $MarginContainer/VBoxContainer/SeedBiasContainer/SeedBiasValue
@onready var blend_slider: HSlider = $MarginContainer/VBoxContainer/BlendContainer/BlendBiasSlider
@onready var blend_value: LineEdit = $MarginContainer/VBoxContainer/BlendContainer/BlendValue
@onready var decay_slider: HSlider = $MarginContainer/VBoxContainer/DecayContainer/DecaySlider
@onready var decay_value: LineEdit = $MarginContainer/VBoxContainer/DecayContainer/DecayValue
@onready var advanced_panel: AdvancedPanel = $"../AdvancedPanel"
var ruleset_name_edit: LineEdit

var font: Font = preload("res://fonts/PixelOperator.ttf")
var bold_font: Font = preload("res://fonts/PixelOperator-Bold.ttf")
var _thresholds := PackedFloat32Array()
var _display_thresholds := PackedFloat32Array()
var _neighborhoods := PackedInt32Array()
var _weights := PackedFloat32Array()
var _display_weights := PackedFloat32Array()
var _channels := PackedFloat32Array()
var _display_channels := PackedFloat32Array()
var _threshold_value_rows: Array = []
var _threshold_value_labels: PackedStringArray = PackedStringArray()
var _weight_value_rows: Array = []
var _weight_value_labels: PackedStringArray = PackedStringArray()
var _channel_value_rows: Array = []
var _channel_value_labels: PackedStringArray = PackedStringArray()
var _candidate_neighborhood_counts := PackedInt32Array([2, 2, 2, 2])
var _enabled := PackedInt32Array([1, 1, 1, 1])
var _section_collapsed_by_key: Dictionary = {} # "kind:candidate_index" -> bool
var w := size.x
var _collapsed := false
var _expanded_size := Vector2.ZERO
var _expanded_custom_minimum_size := Vector2.ZERO
var _row_visibility_before_collapse: Dictionary = {} # instance_id:int -> visible:bool
var _collapsed_top_spacer: Control
var _accordion_hover_style_expanded: StyleBox
var _accordion_pressed_style_expanded: StyleBox
var _accordion_hover_style_collapsed: StyleBox
var _accordion_pressed_style_collapsed: StyleBox

var icon_checked:= preload("res://icons/checked.png")
var icon_unchecked:= preload("res://icons/unchecked.png")
var icon_accordion_minus := preload("res://icons/minus.png")
var icon_accordion_plus := preload("res://icons/plus.png")

const ACTION_COL := 1
const CANDIDATE_DELTA_COL := 3
const CHECK_COL := 5

const ACTIVE_COLOR := Color(1, 1, 1, 1)
const DISABLED_COLOR := Color(0.6, 0.6, 0.6, 1)
const ACTION_TEXT_IDLE := Color(1, 1, 1, 0.8)
const ACTION_TEXT_HOVER := Color(1, 1, 1, 1)
const ACTION_TEXT_PRESSED := Color(1, 1, 1, 0.4)
const ACTION_TEXT_DISABLED := Color(1, 1, 1, 0.25)
const FLIP_CHANCE_MIN := 0.001
const FLIP_CHANCE_MAX := 0.05
const CANDIDATE_COUNT := 4
const THRESHOLD_FLOAT_COUNT := 32
const WEIGHT_COUNT := 16
const NEIGHBORHOOD_INT_COUNT := 8
const CHANNEL_FLOAT_COUNT := WEIGHT_COUNT * 6
const CHANNEL_VALUES_PER_RULE := 6
const NEIGHBORHOOD_RING_COUNT := 12
const NEIGHBORHOOD_RING_MASK := 0xFFF
const SEED_BIAS_MIN := 0.5
const SEED_BIAS_MAX := 2.5
const BLEND_MIN := 0.0
const BLEND_MAX := 1.0
const DECAY_RATE_MIN := 0.0
const DECAY_RATE_MAX := 0.010
const DECAY_RATE_STEP := 0.001
const TREE_MIN_HEIGHT := 500.0
const NEIGHBORHOOD_LABELS := ["A", "B", "C", "D", "E", "F", "G", "H"]
const CHANNEL_NAMES := ["red", "green", "blue"]
const COLLAPSED_HOVER_COLOR := Color(0.45, 0.45, 0.45, 0.35)
const COLLAPSED_PRESSED_COLOR := Color(0.3, 0.3, 0.3, 0.35)
const COLLAPSED_BORDER_COLOR := Color(1, 1, 1, 0.25)
const COLLAPSED_BUTTON_TOP_PADDING := 10.0
const COLLAPSED_PANEL_HEIGHT := 220.0

var _hover_action_key := ""
var _pressed_action_key := ""
var _split_mode := false
var _collapsed_before_split := false
var _ruleset_name_context_index := -1

var icon_split_grid := preload("res://icons/grid.png")
var icon_split_single := preload("res://icons/single.png")


func _ready() -> void:
	if header_label != null:
		ruleset_name_edit = header_label.get_node_or_null("NameEdit") as LineEdit
		if ruleset_name_edit == null:
			ruleset_name_edit = header_label.get_node_or_null("LineEdit") as LineEdit

	tree.custom_minimum_size.y = TREE_MIN_HEIGHT

	tree.columns = 6
	tree.hide_root = true
	tree.select_mode = Tree.SELECT_ROW
	tree.focus_mode = Control.FOCUS_NONE
	flip_chance_slider.focus_mode = Control.FOCUS_NONE
	seed_bias_slider.focus_mode = Control.FOCUS_NONE
	blend_slider.focus_mode = Control.FOCUS_NONE
	decay_slider.focus_mode = Control.FOCUS_NONE

	tree.set_column_expand(0, false) # label
	tree.set_column_expand(1, false) # action
	tree.set_column_expand(2, false) # spacer
	tree.set_column_expand(3, false) # candidate delta
	tree.set_column_expand(4, false) # spacer
	tree.set_column_expand(5, false) # checkbox

	tree.set_column_custom_minimum_width(0, w - 210.0)
	tree.set_column_custom_minimum_width(1, 42)
	tree.set_column_custom_minimum_width(2, 20)
	tree.set_column_custom_minimum_width(3, 42)
	tree.set_column_custom_minimum_width(4, 20)
	tree.set_column_custom_minimum_width(5, 30)

	tree.add_theme_font_override("font", font)
	tree.add_theme_font_size_override("font_size", 40)

	var empty := StyleBoxEmpty.new()
	tree.add_theme_stylebox_override("selected", empty)
	tree.add_theme_stylebox_override("cursor", empty)
	tree.add_theme_stylebox_override("cursor_unfocused", empty)

	var custom_btn := StyleBoxFlat.new()
	custom_btn.bg_color = Color(0.5, 0.5, 0.5, 0.25)
	custom_btn.border_width_left = 2
	custom_btn.border_width_top = 2
	custom_btn.border_width_right = 0
	custom_btn.border_width_bottom = 0
	custom_btn.border_blend = true
	custom_btn.border_color = Color(1, 1, 1, 0.25)
	custom_btn.content_margin_left = 0
	custom_btn.content_margin_right = 0
	custom_btn.content_margin_top = 0
	custom_btn.content_margin_bottom = 0

	var custom_btn_hover := custom_btn.duplicate()
	custom_btn_hover.bg_color = Color(0.5, 0.5, 0.5, 0.35)

	var custom_btn_pressed := custom_btn.duplicate()
	custom_btn_pressed.bg_color = Color(0.3, 0.3, 0.3, 0.35)
	custom_btn_pressed.border_color = Color(0.3, 0.3, 0.3, 0.35)

	tree.add_theme_stylebox_override("custom_button", custom_btn)
	tree.add_theme_stylebox_override("custom_button_hover", custom_btn_hover)
	tree.add_theme_stylebox_override("custom_button_pressed", custom_btn_pressed)

	tree.add_theme_icon_override("checked", icon_checked)
	tree.add_theme_icon_override("unchecked", icon_unchecked)

	if not tree.item_edited.is_connected(_on_tree_item_edited):
		tree.item_edited.connect(_on_tree_item_edited)
	if not tree.gui_input.is_connected(_on_tree_gui_input):
		tree.gui_input.connect(_on_tree_gui_input)
	if not flip_chance_slider.value_changed.is_connected(_on_flip_chance_slider_value_changed):
		flip_chance_slider.value_changed.connect(_on_flip_chance_slider_value_changed)
	if not flip_chance_value.text_submitted.is_connected(_on_flip_chance_value_submitted):
		flip_chance_value.text_submitted.connect(_on_flip_chance_value_submitted)
	if not flip_chance_value.focus_exited.is_connected(_on_flip_chance_value_focus_exited):
		flip_chance_value.focus_exited.connect(_on_flip_chance_value_focus_exited)
	if not all_button.pressed.is_connected(_on_all_button_pressed):
		all_button.pressed.connect(_on_all_button_pressed)
	if not thresh_button.pressed.is_connected(_on_thresh_button_pressed):
		thresh_button.pressed.connect(_on_thresh_button_pressed)
	if not nbrhd_button.pressed.is_connected(_on_nbrhd_button_pressed):
		nbrhd_button.pressed.connect(_on_nbrhd_button_pressed)
	if not weights_button.pressed.is_connected(_on_weights_button_pressed):
		weights_button.pressed.connect(_on_weights_button_pressed)
	if not channel_button.pressed.is_connected(_on_channel_button_pressed):
		channel_button.pressed.connect(_on_channel_button_pressed)
	if split_button != null and not split_button.pressed.is_connected(_on_split_button_pressed):
		split_button.pressed.connect(_on_split_button_pressed)
	if shuffle_button != null and not shuffle_button.pressed.is_connected(_on_shuffle_button_pressed):
		shuffle_button.pressed.connect(_on_shuffle_button_pressed)
	if accordion_button != null and not accordion_button.pressed.is_connected(_on_accordion_button_pressed):
		accordion_button.pressed.connect(_on_accordion_button_pressed)
	if not seed_bias_slider.value_changed.is_connected(_on_seed_bias_slider_value_changed):
		seed_bias_slider.value_changed.connect(_on_seed_bias_slider_value_changed)
	if not seed_bias_slider.drag_ended.is_connected(_on_seed_bias_slider_drag_ended):
		seed_bias_slider.drag_ended.connect(_on_seed_bias_slider_drag_ended)
	if not seed_bias_value.text_submitted.is_connected(_on_seed_bias_value_submitted):
		seed_bias_value.text_submitted.connect(_on_seed_bias_value_submitted)
	if not seed_bias_value.focus_exited.is_connected(_on_seed_bias_value_focus_exited):
		seed_bias_value.focus_exited.connect(_on_seed_bias_value_focus_exited)
	if not blend_slider.value_changed.is_connected(_on_blend_slider_value_changed):
		blend_slider.value_changed.connect(_on_blend_slider_value_changed)
	if not blend_slider.drag_ended.is_connected(_on_blend_slider_drag_ended):
		blend_slider.drag_ended.connect(_on_blend_slider_drag_ended)
	if not blend_value.text_submitted.is_connected(_on_blend_value_submitted):
		blend_value.text_submitted.connect(_on_blend_value_submitted)
	if not blend_value.focus_exited.is_connected(_on_blend_value_focus_exited):
		blend_value.focus_exited.connect(_on_blend_value_focus_exited)
	if not decay_slider.value_changed.is_connected(_on_decay_slider_value_changed):
		decay_slider.value_changed.connect(_on_decay_slider_value_changed)
	if not decay_slider.drag_ended.is_connected(_on_decay_slider_drag_ended):
		decay_slider.drag_ended.connect(_on_decay_slider_drag_ended)
	if not decay_value.text_submitted.is_connected(_on_decay_value_submitted):
		decay_value.text_submitted.connect(_on_decay_value_submitted)
	if not decay_value.focus_exited.is_connected(_on_decay_value_focus_exited):
		decay_value.focus_exited.connect(_on_decay_value_focus_exited)
	if ruleset_name_edit != null and not ruleset_name_edit.text_changed.is_connected(_on_ruleset_name_text_changed):
		ruleset_name_edit.text_changed.connect(_on_ruleset_name_text_changed)
	if ruleset_name_edit != null and not ruleset_name_edit.text_submitted.is_connected(_on_ruleset_name_text_submitted):
		ruleset_name_edit.text_submitted.connect(_on_ruleset_name_text_submitted)
	if advanced_panel != null:
		if not advanced_panel.advanced_values_changed.is_connected(_on_advanced_panel_values_changed):
			advanced_panel.advanced_values_changed.connect(_on_advanced_panel_values_changed)
		if not advanced_panel.open_state_changed.is_connected(_on_advanced_open_state_changed):
			advanced_panel.open_state_changed.connect(_on_advanced_open_state_changed)

	flip_chance_slider.min_value = FLIP_CHANCE_MIN
	flip_chance_slider.max_value = FLIP_CHANCE_MAX
	flip_chance_slider.step = 0.001
	flip_chance_slider.set_value_no_signal(0.015)
	flip_chance_value.text = "%.3f" % flip_chance_slider.value
	seed_bias_slider.min_value = SEED_BIAS_MIN
	seed_bias_slider.max_value = SEED_BIAS_MAX
	seed_bias_slider.step = 0.02
	blend_slider.min_value = BLEND_MIN
	blend_slider.max_value = BLEND_MAX
	blend_slider.step = 0.01
	blend_slider.set_value_no_signal(0.5)
	blend_value.text = "%.2f" % blend_slider.value
	decay_slider.min_value = DECAY_RATE_MIN
	decay_slider.max_value = DECAY_RATE_MAX
	decay_slider.step = DECAY_RATE_STEP
	decay_slider.set_value_no_signal(0.0)
	decay_value.text = "%.3f" % decay_slider.value
	if advanced_panel != null:
		advanced_panel.hide_panel()
	if split_button != null:
		split_button.toggle_mode = false
		split_button.set_pressed_no_signal(false)
	_ensure_collapsed_top_spacer()
	_cache_expanded_geometry()
	_prepare_accordion_styles()
	_apply_accordion_visual_state()
	_apply_split_button_visual_state()
	_style_input_line_edit(flip_chance_value)
	_style_input_line_edit(seed_bias_value)
	_style_input_line_edit(blend_value)
	_style_input_line_edit(decay_value)
	_style_input_line_edit(ruleset_name_edit)
	set_ruleset_name_context(-1, "", true)

	_rebuild_tree()


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
	candidate_neighborhood_counts: PackedInt32Array,
	enabled: PackedInt32Array,
	seed_bias: float,
	blend_k: float,
	decay_rate: float
) -> void:
	_thresholds = thresholds.duplicate()
	_neighborhoods = neighborhoods.duplicate()
	_weights = weights.duplicate()
	_channels = channels.duplicate()
	_candidate_neighborhood_counts = _normalize_candidate_neighborhood_counts(candidate_neighborhood_counts)
	_enabled = enabled.duplicate()
	if _neighborhoods.size() != NEIGHBORHOOD_INT_COUNT:
		_neighborhoods.resize(NEIGHBORHOOD_INT_COUNT)
		for i in range(NEIGHBORHOOD_INT_COUNT):
			_neighborhoods[i] = 0
	if _thresholds.size() != THRESHOLD_FLOAT_COUNT:
		var normalized_t := PackedFloat32Array()
		normalized_t.resize(THRESHOLD_FLOAT_COUNT)
		for i in range(min(_thresholds.size(), THRESHOLD_FLOAT_COUNT)):
			normalized_t[i] = _thresholds[i]
		_thresholds = normalized_t
	if _enabled.size() != CANDIDATE_COUNT:
		_enabled.resize(CANDIDATE_COUNT)
		for i in range(CANDIDATE_COUNT):
			_enabled[i] = 1
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
	_display_thresholds = _thresholds.duplicate()
	_display_weights = _weights.duplicate()
	_display_channels = _channels.duplicate()

	var bias := clampf(seed_bias, SEED_BIAS_MIN, SEED_BIAS_MAX)
	seed_bias_slider.set_value_no_signal(bias)
	seed_bias_value.text = "%.2f" % bias
	var blend := clampf(blend_k, BLEND_MIN, BLEND_MAX)
	blend_slider.set_value_no_signal(blend)
	blend_value.text = "%.2f" % blend
	var decay := clampf(decay_rate, DECAY_RATE_MIN, DECAY_RATE_MAX)
	decay_slider.set_value_no_signal(decay)
	decay_value.text = "%.3f" % decay
	if advanced_panel != null:
		advanced_panel.set_data(_thresholds, _neighborhoods, _weights, _channels, _candidate_neighborhood_counts)
	_rebuild_tree()

func set_display_runtime_values(
	display_thresholds: PackedFloat32Array,
	display_weights: PackedFloat32Array,
	display_channels: PackedFloat32Array
) -> void:
	if display_thresholds.size() != THRESHOLD_FLOAT_COUNT:
		_display_thresholds = _thresholds.duplicate()
	else:
		_display_thresholds = display_thresholds.duplicate()
	if display_weights.size() != WEIGHT_COUNT:
		_display_weights = _weights.duplicate()
	else:
		_display_weights = display_weights.duplicate()
	if display_channels.size() != CHANNEL_FLOAT_COUNT:
		_display_channels = _channels.duplicate()
	else:
		_display_channels = display_channels.duplicate()
	_update_runtime_value_rows()

func _update_runtime_value_rows() -> void:
	if (
		_threshold_value_rows.size() != _display_thresholds.size()
		or _weight_value_rows.size() != _display_weights.size()
		or _channel_value_rows.size() != _display_channels.size()
	):
		_rebuild_tree()
		return
	for i in range(_threshold_value_rows.size()):
		var row := _threshold_value_rows[i] as TreeItem
		if row == null:
			_rebuild_tree()
			return
		var label := _threshold_value_labels[i] if i < _threshold_value_labels.size() else ""
		row.set_text(0, " %s = %.4f" % [label, _display_thresholds[i]])
	for i in range(_weight_value_rows.size()):
		var row := _weight_value_rows[i] as TreeItem
		if row == null:
			_rebuild_tree()
			return
		var label := _weight_value_labels[i] if i < _weight_value_labels.size() else ""
		row.set_text(0, " w%s = %.4f" % [label, _display_weights[i]])
	for i in range(_channel_value_rows.size()):
		var row := _channel_value_rows[i] as TreeItem
		if row == null:
			_rebuild_tree()
			return
		var label := _channel_value_labels[i] if i < _channel_value_labels.size() else ""
		row.set_text(0, " %s = %.4f" % [label, _display_channels[i]])

func collapse_sections_for_open() -> void:
	for c in range(CANDIDATE_COUNT):
		_section_collapsed_by_key[_section_key("neighborhoods", c)] = true
		_section_collapsed_by_key[_section_key("thresholds", c)] = true
		_section_collapsed_by_key[_section_key("weights", c)] = true
		_section_collapsed_by_key[_section_key("channels", c)] = true
	_rebuild_tree()

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

func _candidate_has_neighborhoods(candidate_index: int) -> bool:
	if candidate_index < 0 or candidate_index >= _candidate_neighborhood_counts.size():
		return false
	return int(_candidate_neighborhood_counts[candidate_index]) > 0

func _candidate_ui_enabled(candidate_index: int) -> bool:
	if not _candidate_has_neighborhoods(candidate_index):
		return false
	if candidate_index < 0 or candidate_index >= _enabled.size():
		return false
	return _enabled[candidate_index] != 0

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

func _channel_label(local_channel_index: int) -> String:
	var local_rule_index := int(local_channel_index / CHANNEL_VALUES_PER_RULE)
	var within_rule := local_channel_index % CHANNEL_VALUES_PER_RULE
	var local_neighborhood_index := int(local_rule_index / 2)
	var rule_in_neighborhood := (local_rule_index % 2) + 1
	var channel_name := str(CHANNEL_NAMES[within_rule % 3])
	var rw := "R" if within_rule < 3 else "W"
	return "%s_%s%s%d" % [channel_name, rw, _neighborhood_label(local_neighborhood_index), rule_in_neighborhood]


func _rebuild_tree() -> void:
	_capture_section_collapsed_state()
	_threshold_value_rows.clear()
	_threshold_value_labels = PackedStringArray()
	_weight_value_rows.clear()
	_weight_value_labels = PackedStringArray()
	_channel_value_rows.clear()
	_channel_value_labels = PackedStringArray()
	tree.clear()
	var root := tree.create_item()

	for c in range(CANDIDATE_COUNT):
		var nh_start := _candidate_neighborhood_start(c)
		var nh_count := int(_candidate_neighborhood_counts[c])
		var thr_range := _candidate_threshold_range(c)
		var w_range := _candidate_weight_range(c)
		var ch_range := _candidate_channel_range(c)
		var candidate_has_nh := _candidate_has_neighborhoods(c)
		var parent := tree.create_item(root)

		parent.set_text(0, " Candidate %d" % (c))
		parent.set_custom_minimum_height(60)
		parent.set_metadata(0, {"kind": "candidate", "candidate_index": c})
		parent.collapsed = bool(_section_collapsed_by_key.get(_section_key("candidate", c), false))
		parent.set_selectable(0, candidate_has_nh)

		_setup_action_cell(parent)
		_setup_candidate_delta_cell(parent)
		parent.set_cell_mode(CHECK_COL, TreeItem.CELL_MODE_CHECK)
		parent.set_editable(CHECK_COL, candidate_has_nh)
		parent.set_checked(CHECK_COL, _enabled[c] != 0)
		parent.set_text(CHECK_COL, "")

		var neighborhoods_node := tree.create_item(parent)
		neighborhoods_node.set_text(0, " Neighborhoods")
		neighborhoods_node.set_selectable(0, false)
		neighborhoods_node.collapsed = bool(_section_collapsed_by_key.get(_section_key("neighborhoods", c), true))
		neighborhoods_node.set_metadata(0, {"kind": "neighborhoods", "candidate_index": c})
		_setup_action_cell(neighborhoods_node)
		for n in range(nh_count):
			var nh_row := tree.create_item(neighborhoods_node)
			nh_row.set_selectable(0, false)
			var idx := nh_start + n
			var mask := 0
			if idx < _neighborhoods.size():
				mask = _sanitize_neighborhood_mask(_neighborhoods[idx])
			var label := _neighborhood_label(n)
			nh_row.set_text(0, " %s = %s" % [label, _neighborhood_mask_to_bits(mask)])
			nh_row.set_custom_font_size(0, 35)
			nh_row.set_custom_minimum_height(1)

		var thresholds_node := tree.create_item(parent)
		thresholds_node.set_text(0, " Thresholds")
		thresholds_node.set_selectable(0, false)
		thresholds_node.collapsed = bool(_section_collapsed_by_key.get(_section_key("thresholds", c), true))
		thresholds_node.set_metadata(0, {"kind": "thresholds", "candidate_index": c})
		_setup_action_cell(thresholds_node)
		for t in range(thr_range.y):
			var idx_t := thr_range.x + t
			var t_row := tree.create_item(thresholds_node)
			t_row.set_selectable(0, false)
			var tv := 0.0
			if idx_t < _display_thresholds.size():
				tv = _display_thresholds[idx_t]
			var threshold_label := _threshold_label(t)
			t_row.set_text(0, " %s = %.4f" % [threshold_label, tv])
			t_row.set_custom_font_size(0, 35)
			t_row.set_custom_minimum_height(1)
			_threshold_value_rows.append(t_row)
			_threshold_value_labels.append(threshold_label)

		var weights_node := tree.create_item(parent)
		weights_node.set_text(0, " Weights")
		weights_node.set_selectable(0, false)
		weights_node.collapsed = bool(_section_collapsed_by_key.get(_section_key("weights", c), true))
		weights_node.set_metadata(0, {"kind": "weights", "candidate_index": c})
		_setup_action_cell(weights_node)
		for w_i in range(w_range.y):
			var idx_w := w_range.x + w_i
			var w_row := tree.create_item(weights_node)
			w_row.set_selectable(0, false)
			var wv := 0.0
			if idx_w < _display_weights.size():
				wv = _display_weights[idx_w]
			var weight_label := _weight_label(w_i)
			w_row.set_text(0, " w%s = %.4f" % [weight_label, wv])
			w_row.set_custom_font_size(0, 35)
			w_row.set_custom_minimum_height(1)
			_weight_value_rows.append(w_row)
			_weight_value_labels.append(weight_label)

		var channels_node := tree.create_item(parent)
		channels_node.set_text(0, " Channels")
		channels_node.set_selectable(0, false)
		channels_node.collapsed = bool(_section_collapsed_by_key.get(_section_key("channels", c), true))
		channels_node.set_metadata(0, {"kind": "channels", "candidate_index": c})
		_setup_action_cell(channels_node)
		for ch_i in range(ch_range.y):
			var idx_ch := ch_range.x + ch_i
			var ch_row := tree.create_item(channels_node)
			ch_row.set_selectable(0, false)
			var chv := 0.0
			if idx_ch < _display_channels.size():
				chv = _display_channels[idx_ch]
			var channel_label := _channel_label(ch_i)
			ch_row.set_text(0, " %s = %.4f" % [channel_label, chv])
			ch_row.set_custom_font_size(0, 35)
			ch_row.set_custom_minimum_height(1)
			_channel_value_rows.append(ch_row)
			_channel_value_labels.append(channel_label)

		parent.set_custom_font(0, bold_font)
		neighborhoods_node.set_custom_font(0, font)
		neighborhoods_node.set_custom_font_size(0, 40)
		thresholds_node.set_custom_font(0, font)
		thresholds_node.set_custom_font_size(0, 40)
		weights_node.set_custom_font(0, font)
		weights_node.set_custom_font_size(0, 40)
		channels_node.set_custom_font(0, font)
		channels_node.set_custom_font_size(0, 40)
		_apply_candidate_visual_state(parent, _candidate_ui_enabled(c))

func _capture_section_collapsed_state() -> void:
	var root := tree.get_root()
	if root == null:
		return
	var candidate := root.get_first_child()
	while candidate != null:
		var candidate_meta: Variant = candidate.get_metadata(0)
		var c := -1
		if typeof(candidate_meta) == TYPE_DICTIONARY:
			c = int(candidate_meta.get("candidate_index", -1))
		if c >= 0 and c < CANDIDATE_COUNT:
			_section_collapsed_by_key[_section_key("candidate", c)] = candidate.collapsed
			var child := candidate.get_first_child()
			while child != null:
				var meta: Variant = child.get_metadata(0)
				if typeof(meta) == TYPE_DICTIONARY:
					var kind := str(meta.get("kind", ""))
					if kind == "neighborhoods" or kind == "thresholds" or kind == "weights" or kind == "channels":
						_section_collapsed_by_key[_section_key(kind, c)] = child.collapsed
				child = child.get_next()
		candidate = candidate.get_next()

func _section_key(kind: String, candidate_index: int) -> String:
	return kind + ":" + str(candidate_index)


func _on_tree_item_edited() -> void:
	var item := tree.get_edited()
	if item == null:
		return
	if item.get_parent() != tree.get_root():
		return
	var col := tree.get_edited_column()
	if col != CHECK_COL:
		return
	var meta: Variant = item.get_metadata(0)
	var idx := -1
	if typeof(meta) == TYPE_DICTIONARY:
		idx = int(meta.get("candidate_index", -1))
	else:
		idx = int(meta)
	if idx < 0 or idx >= CANDIDATE_COUNT:
		return
	if not _candidate_has_neighborhoods(idx):
		item.set_checked(CHECK_COL, _enabled[idx] != 0)
		return
	var on := item.is_checked(CHECK_COL)
	_enabled[idx] = 1 if on else 0
	_apply_candidate_visual_state(item, on)
	_hover_action_key = ""
	_pressed_action_key = ""
	tree.queue_redraw()
	candidate_toggled.emit(idx, on)


func _on_tree_gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseMotion:
		var pos_motion: Vector2 = ev.position
		var motion_item := tree.get_item_at_position(pos_motion)
		var motion_col := tree.get_column_at_position(pos_motion)
		var new_hover_key := ""
		if motion_item != null:
			var motion_meta: Variant = motion_item.get_metadata(0)
			if typeof(motion_meta) == TYPE_DICTIONARY:
				var motion_kind := str(motion_meta.get("kind", ""))
				var action_enabled := _is_action_item_enabled(motion_item)
				if motion_kind == "candidate":
					action_enabled = _is_adv_item_enabled(motion_item)
				if motion_col == ACTION_COL and (motion_kind == "candidate" or motion_kind == "neighborhoods" or motion_kind == "thresholds" or motion_kind == "weights" or motion_kind == "channels") and action_enabled:
					new_hover_key = _action_key_for_item(motion_item)
				elif motion_col == CANDIDATE_DELTA_COL and motion_kind == "candidate" and _is_action_item_enabled(motion_item):
					new_hover_key = _candidate_delta_key_for_item(motion_item)
		if new_hover_key != _hover_action_key:
			_hover_action_key = new_hover_key
			tree.queue_redraw()
		return

	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = ev.position
		var item := tree.get_item_at_position(pos)
		var col := tree.get_column_at_position(pos)

		if ev.pressed:
			if item != null and (col == ACTION_COL or col == CANDIDATE_DELTA_COL):
				if not _is_action_item_enabled(item):
					accept_event()
					return
				var meta: Variant = item.get_metadata(0)
				if typeof(meta) == TYPE_DICTIONARY:
					var kind := str(meta.get("kind", ""))
					var candidate_index := int(meta.get("candidate_index", -1))
					if candidate_index >= 0 and candidate_index < CANDIDATE_COUNT:
						if col == ACTION_COL and (kind == "candidate" or kind == "neighborhoods" or kind == "thresholds" or kind == "weights" or kind == "channels"):
							if kind == "candidate" and not _is_adv_item_enabled(item):
								accept_event()
								return
							_pressed_action_key = _action_key_for_item(item)
							tree.queue_redraw()
							if kind == "neighborhoods" or kind == "thresholds" or kind == "weights" or kind == "channels":
								parent_action_pressed.emit(kind, candidate_index, flip_chance_slider.value)
							elif kind == "candidate":
								if advanced_panel != null:
									advanced_panel.open_for_candidate(candidate_index)
						elif col == CANDIDATE_DELTA_COL and kind == "candidate":
							_pressed_action_key = _candidate_delta_key_for_item(item)
							tree.queue_redraw()
							parent_action_pressed.emit("all", candidate_index, flip_chance_slider.value)
				accept_event()
				return

			if item == null or item.get_parent() != tree.get_root():
				return
			if col == 0:
				item.collapsed = not item.collapsed
				accept_event()
				return
		else:
			if _pressed_action_key != "":
				_pressed_action_key = ""
				tree.queue_redraw()

func _on_seed_bias_slider_value_changed(v: float) -> void:
	seed_bias_value.text = "%.2f" % v
	seed_bias_changed.emit(v)

func _on_seed_bias_slider_drag_ended(value_changed: bool) -> void:
	if not value_changed:
		return
	seed_bias_committed.emit(seed_bias_slider.value)

func _on_blend_slider_value_changed(v: float) -> void:
	blend_value.text = "%.2f" % v
	blend_value_changed.emit(v)

func _on_blend_slider_drag_ended(value_changed: bool) -> void:
	if not value_changed:
		return
	blend_value_committed.emit(blend_slider.value)

func _on_decay_slider_value_changed(v: float) -> void:
	decay_value.text = "%.3f" % v
	decay_rate_changed.emit(v)

func _on_decay_slider_drag_ended(value_changed: bool) -> void:
	if not value_changed:
		return
	decay_rate_committed.emit(decay_slider.value)

func _on_flip_chance_slider_value_changed(v: float) -> void:
	flip_chance_value.text = "%.3f" % v

func _on_flip_chance_value_submitted(_text: String) -> void:
	_commit_flip_chance_value()

func _on_flip_chance_value_focus_exited() -> void:
	_commit_flip_chance_value()

func _commit_flip_chance_value() -> void:
	var v := clampf(flip_chance_value.text.to_float(), FLIP_CHANCE_MIN, FLIP_CHANCE_MAX)
	flip_chance_slider.value = v
	flip_chance_value.text = "%.3f" % v

func _on_all_button_pressed() -> void:
	random_delta_requested.emit("all", flip_chance_slider.value)

func _on_thresh_button_pressed() -> void:
	random_delta_requested.emit("thresholds", flip_chance_slider.value)

func _on_nbrhd_button_pressed() -> void:
	random_delta_requested.emit("neighborhoods", flip_chance_slider.value)

func _on_weights_button_pressed() -> void:
	random_delta_requested.emit("weights", flip_chance_slider.value)

func _on_channel_button_pressed() -> void:
	random_delta_requested.emit("channels", flip_chance_slider.value)

func _on_split_button_pressed() -> void:
	set_split_mode(not _split_mode, true)

func _on_shuffle_button_pressed() -> void:
	shuffle_channels_requested.emit()

func set_split_mode(enabled: bool, emit_signal := false) -> void:
	if _split_mode == enabled:
		return
	_split_mode = enabled
	if _split_mode:
		_collapsed_before_split = _collapsed
		_set_collapsed(true)
		if accordion_button != null:
			accordion_button.disabled = true
	else:
		if accordion_button != null:
			accordion_button.disabled = false
		_set_collapsed(_collapsed_before_split)
	_apply_split_button_visual_state()
	if emit_signal:
		split_toggled.emit(_split_mode)

func is_split_mode() -> bool:
	return _split_mode

func get_flip_chance() -> float:
	return clampf(flip_chance_slider.value, FLIP_CHANCE_MIN, FLIP_CHANCE_MAX)

func _apply_split_button_visual_state() -> void:
	if split_button == null:
		return
	split_button.toggle_mode = false
	split_button.set_pressed_no_signal(false)
	split_button.icon = icon_split_single if _split_mode else icon_split_grid

func _on_accordion_button_pressed() -> void:
	_set_collapsed(not _collapsed)

func _set_collapsed(collapsed: bool) -> void:
	if _collapsed == collapsed:
		return
	if collapsed:
		_cache_expanded_geometry()
		_capture_row_visibility_before_collapse()
		_apply_rows_collapsed_visibility(true)
		_collapsed = true
		_apply_collapsed_geometry()
	else:
		_apply_rows_collapsed_visibility(false)
		_restore_expanded_geometry()
		_collapsed = false
	_apply_accordion_visual_state()

func _cache_expanded_geometry() -> void:
	_expanded_size = size
	_expanded_custom_minimum_size = custom_minimum_size

func _restore_expanded_geometry() -> void:
	custom_minimum_size = _expanded_custom_minimum_size
	if _expanded_size != Vector2.ZERO:
		size = _expanded_size

func _apply_collapsed_geometry() -> void:
	custom_minimum_size.y = COLLAPSED_PANEL_HEIGHT
	size.y = COLLAPSED_PANEL_HEIGHT

func _capture_row_visibility_before_collapse() -> void:
	_row_visibility_before_collapse.clear()
	if rows_container == null:
		return
	for child_v in rows_container.get_children():
		var child := child_v as CanvasItem
		if child == null:
			continue
		_row_visibility_before_collapse[child.get_instance_id()] = child.visible

func _ensure_collapsed_top_spacer() -> void:
	if rows_container == null or delta_container == null:
		return
	if _collapsed_top_spacer != null and is_instance_valid(_collapsed_top_spacer):
		var existing_delta_index := delta_container.get_index()
		rows_container.move_child(_collapsed_top_spacer, existing_delta_index)
		return
	_collapsed_top_spacer = Control.new()
	_collapsed_top_spacer.name = "CollapsedTopSpacer"
	_collapsed_top_spacer.custom_minimum_size = Vector2(0, COLLAPSED_BUTTON_TOP_PADDING)
	_collapsed_top_spacer.visible = false
	var undo_index := delta_container.get_index()
	rows_container.add_child(_collapsed_top_spacer)
	rows_container.move_child(_collapsed_top_spacer, undo_index)

func _apply_rows_collapsed_visibility(collapsed: bool) -> void:
	if rows_container == null:
		return
	for child_v in rows_container.get_children():
		var child := child_v as CanvasItem
		if child == null:
			continue
		if collapsed:
			child.visible = (
				child_v == _collapsed_top_spacer
				or child_v == delta_container
				or child_v == padding2
				or child_v == misc_container
			)
		else:
			var key := child.get_instance_id()
			if _row_visibility_before_collapse.has(key):
				child.visible = bool(_row_visibility_before_collapse[key])
			else:
				child.visible = true
	if not collapsed:
		_row_visibility_before_collapse.clear()

func _prepare_accordion_styles() -> void:
	if accordion_button == null:
		return
	var hover_src := accordion_button.get_theme_stylebox("hover")
	var pressed_src := accordion_button.get_theme_stylebox("pressed")
	if hover_src != null:
		_accordion_hover_style_expanded = _make_gray_stylebox(hover_src, COLLAPSED_HOVER_COLOR)
		_accordion_hover_style_collapsed = _accordion_hover_style_expanded.duplicate(true)
	if pressed_src != null:
		_accordion_pressed_style_expanded = _make_gray_stylebox(pressed_src, COLLAPSED_PRESSED_COLOR)
		_accordion_pressed_style_collapsed = _accordion_pressed_style_expanded.duplicate(true)

func _make_gray_stylebox(base_style: StyleBox, bg: Color) -> StyleBox:
	var flat := base_style.duplicate(true) as StyleBoxFlat
	if flat == null:
		flat = StyleBoxFlat.new()
	flat.bg_color = bg
	flat.border_color = COLLAPSED_BORDER_COLOR
	return flat

func _apply_accordion_visual_state() -> void:
	if accordion_button == null:
		return
	accordion_button.icon = icon_accordion_plus if _collapsed else icon_accordion_minus
	if _collapsed:
		if _accordion_hover_style_collapsed != null:
			accordion_button.add_theme_stylebox_override("hover", _accordion_hover_style_collapsed)
		if _accordion_pressed_style_collapsed != null:
			accordion_button.add_theme_stylebox_override("pressed", _accordion_pressed_style_collapsed)
	else:
		if _accordion_hover_style_expanded != null:
			accordion_button.add_theme_stylebox_override("hover", _accordion_hover_style_expanded)
		if _accordion_pressed_style_expanded != null:
			accordion_button.add_theme_stylebox_override("pressed", _accordion_pressed_style_expanded)

func _on_seed_bias_value_submitted(_text: String) -> void:
	_commit_seed_bias_value()

func _on_seed_bias_value_focus_exited() -> void:
	_commit_seed_bias_value()

func _on_blend_value_submitted(_text: String) -> void:
	_commit_blend_value()

func _on_blend_value_focus_exited() -> void:
	_commit_blend_value()

func _on_decay_value_submitted(_text: String) -> void:
	_commit_decay_value()

func _on_decay_value_focus_exited() -> void:
	_commit_decay_value()

func _commit_seed_bias_value() -> void:
	var v := clampf(seed_bias_value.text.to_float(), SEED_BIAS_MIN, SEED_BIAS_MAX)
	seed_bias_slider.value = v
	seed_bias_value.text = "%.2f" % v
	seed_bias_committed.emit(v)

func _commit_blend_value() -> void:
	var v := clampf(blend_value.text.to_float(), BLEND_MIN, BLEND_MAX)
	blend_slider.value = v
	blend_value.text = "%.2f" % v
	blend_value_committed.emit(v)

func _commit_decay_value() -> void:
	var v := clampf(decay_value.text.to_float(), DECAY_RATE_MIN, DECAY_RATE_MAX)
	decay_slider.value = v
	decay_value.text = "%.3f" % v
	decay_rate_committed.emit(v)

func _on_ruleset_name_text_submitted(_text: String) -> void:
	if ruleset_name_edit == null:
		return
	ruleset_name_edit.release_focus()

func _on_ruleset_name_text_changed(text: String) -> void:
	ruleset_name_changed.emit(text)

func set_ruleset_name_context(ruleset_index: int, ruleset_name: String, force_text := false) -> void:
	if ruleset_name_edit == null:
		return
	var show := ruleset_index >= 0
	ruleset_name_edit.visible = show
	if not show:
		if not ruleset_name_edit.text.is_empty():
			ruleset_name_edit.text = ""
		_ruleset_name_context_index = -1
		return
	var resolved_name := ruleset_name.strip_edges()
	if (force_text or _ruleset_name_context_index != ruleset_index) and ruleset_name_edit.text != resolved_name:
		ruleset_name_edit.text = resolved_name
	_ruleset_name_context_index = ruleset_index

func get_ruleset_name_input_text() -> String:
	if ruleset_name_edit == null:
		return ""
	return ruleset_name_edit.text

func show_ruleset_name_duplicate_error() -> void:
	if ruleset_name_edit == null:
		return
	ruleset_name_edit.text = "Already exists!"
	ruleset_name_edit.grab_focus()
	ruleset_name_edit.select_all()

func _style_input_line_edit(edit: LineEdit) -> void:
	if edit == null:
		return
	var normal_style := edit.get_theme_stylebox("normal")
	if normal_style != null:
		edit.add_theme_stylebox_override("focus", normal_style.duplicate(true))

func _setup_action_cell(item: TreeItem) -> void:
	item.set_cell_mode(ACTION_COL, TreeItem.CELL_MODE_CUSTOM)
	item.set_editable(ACTION_COL, false)
	item.set_selectable(ACTION_COL, false)
	item.set_text(ACTION_COL, "")
	item.set_custom_draw_callback(ACTION_COL, Callable(self, "_draw_action_cell"))

func _setup_candidate_delta_cell(item: TreeItem) -> void:
	item.set_cell_mode(CANDIDATE_DELTA_COL, TreeItem.CELL_MODE_CUSTOM)
	item.set_editable(CANDIDATE_DELTA_COL, false)
	item.set_selectable(CANDIDATE_DELTA_COL, false)
	item.set_text(CANDIDATE_DELTA_COL, "")
	item.set_custom_draw_callback(CANDIDATE_DELTA_COL, Callable(self, "_draw_candidate_delta_cell"))

func _draw_action_cell(_item: TreeItem, rect: Rect2) -> void:
	var canvas := tree.get_canvas_item()
	var meta: Variant = _item.get_metadata(0)
	var kind := ""
	if typeof(meta) == TYPE_DICTIONARY:
		kind = str(meta.get("kind", ""))
	if kind == "candidate":
		var adv_key := _action_key_for_item(_item)
		var adv_enabled := _is_adv_item_enabled(_item)
		var text_color_adv := ACTION_TEXT_IDLE if adv_enabled else ACTION_TEXT_DISABLED
		if adv_key != "" and adv_enabled:
			if adv_key == _pressed_action_key:
				text_color_adv = ACTION_TEXT_PRESSED
			elif adv_key == _hover_action_key:
				text_color_adv = ACTION_TEXT_HOVER
		var adv_text := "Adv."
		var adv_size := 25
		var adv_y := rect.position.y + (rect.size.y + float(adv_size)) * 0.5 - 2.0
		var adv_w := font.get_string_size(adv_text, HORIZONTAL_ALIGNMENT_CENTER, -1, adv_size).x
		font.draw_string(
			canvas,
			Vector2(rect.position.x, adv_y),
			adv_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x,
			adv_size,
			text_color_adv
		)
		var cx := rect.position.x + rect.size.x * 0.5
		var underline_y := adv_y + 2.0
		var x0 := cx - adv_w * 0.5
		var x1 := cx + adv_w * 0.5
		tree.draw_line(Vector2(x0, underline_y), Vector2(x1, underline_y), text_color_adv, 1.0)
		return

	var key := _action_key_for_item(_item)
	var style_name := "custom_button"
	var enabled := _is_action_item_enabled(_item)
	var text_color := ACTION_TEXT_IDLE if enabled else ACTION_TEXT_DISABLED
	if key != "" and enabled:
		if key == _pressed_action_key:
			style_name = "custom_button_pressed"
			text_color = ACTION_TEXT_PRESSED
		elif key == _hover_action_key:
			style_name = "custom_button_hover"
			text_color = ACTION_TEXT_HOVER
	var bg := tree.get_theme_stylebox(style_name)
	if bg != null:
		bg.draw(canvas, rect.grow(-2.0))
	var text := "∆"
	var font_size := 26
	var baseline_y := rect.position.y + (rect.size.y + float(font_size)) * 0.5 - 3.0
	bold_font.draw_string(
		canvas,
		Vector2(rect.position.x, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		font_size,
		text_color
	)

func _draw_candidate_delta_cell(_item: TreeItem, rect: Rect2) -> void:
	var canvas := tree.get_canvas_item()
	var meta: Variant = _item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var kind := str(meta.get("kind", ""))
	if kind != "candidate":
		return

	var key := _candidate_delta_key_for_item(_item)
	var style_name := "custom_button"
	var enabled := _is_action_item_enabled(_item)
	var text_color := ACTION_TEXT_IDLE if enabled else ACTION_TEXT_DISABLED
	if key != "" and enabled:
		if key == _pressed_action_key:
			style_name = "custom_button_pressed"
			text_color = ACTION_TEXT_PRESSED
		elif key == _hover_action_key:
			style_name = "custom_button_hover"
			text_color = ACTION_TEXT_HOVER

	var button_h := 45.0
	var button_rect := Rect2(
		rect.position.x,
		rect.position.y + (rect.size.y - button_h) * 0.5,
		rect.size.x,
		button_h
	)

	var bg := tree.get_theme_stylebox(style_name)
	if bg != null:
		bg.draw(canvas, button_rect.grow(-2.0))

	var text := "∆"
	var font_size := 26
	var baseline_y := button_rect.position.y + (button_rect.size.y + float(font_size)) * 0.5 - 3.0
	bold_font.draw_string(
		canvas,
		Vector2(button_rect.position.x, baseline_y),
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		button_rect.size.x,
		font_size,
		text_color
	)

func _is_action_item_enabled(item: TreeItem) -> bool:
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return true
	var candidate_index := int(meta.get("candidate_index", -1))
	if candidate_index < 0 or candidate_index >= _enabled.size():
		return true
	return _candidate_ui_enabled(candidate_index)

func _is_adv_item_enabled(item: TreeItem) -> bool:
	if advanced_panel != null and advanced_panel.is_open():
		return false
	return _is_action_item_enabled(item)

func _action_key_for_item(item: TreeItem) -> String:
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return ""
	var kind := str(meta.get("kind", ""))
	if kind != "candidate" and kind != "neighborhoods" and kind != "thresholds" and kind != "weights" and kind != "channels":
		return ""
	var candidate_index := int(meta.get("candidate_index", -1))
	if candidate_index < 0 or candidate_index >= CANDIDATE_COUNT:
		return ""
	return kind + ":" + str(candidate_index)

func _candidate_delta_key_for_item(item: TreeItem) -> String:
	var meta: Variant = item.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return ""
	var kind := str(meta.get("kind", ""))
	if kind != "candidate":
		return ""
	var candidate_index := int(meta.get("candidate_index", -1))
	if candidate_index < 0 or candidate_index >= CANDIDATE_COUNT:
		return ""
	return "candidate_delta:" + str(candidate_index)

func _apply_candidate_visual_state(parent: TreeItem, enabled: bool) -> void:
	var c := ACTIVE_COLOR if enabled else DISABLED_COLOR
	parent.set_custom_color(0, c)
	# Child rows text
	var child := parent.get_first_child()
	while child != null:
		child.set_custom_color(0, c)
		var grandchild := child.get_first_child()
		while grandchild != null:
			grandchild.set_custom_color(0, c)
			var great_grandchild := grandchild.get_first_child()
			while great_grandchild != null:
				great_grandchild.set_custom_color(0, c)
				great_grandchild = great_grandchild.get_next()
			grandchild = grandchild.get_next()
		child = child.get_next()

func hide_advanced_panel() -> void:
	if advanced_panel != null:
		advanced_panel.hide_panel()
	_hover_action_key = ""
	_pressed_action_key = ""
	tree.queue_redraw()

func _on_advanced_panel_values_changed(
	thresholds: PackedFloat32Array,
	neighborhoods: PackedInt32Array,
	weights: PackedFloat32Array,
	channels: PackedFloat32Array,
	committed: bool
) -> void:
	_thresholds = thresholds.duplicate()
	_neighborhoods = neighborhoods.duplicate()
	_weights = weights.duplicate()
	_channels = channels.duplicate()
	_rebuild_tree()
	advanced_values_changed.emit(_thresholds, _neighborhoods, _weights, _channels, committed)

func _on_advanced_open_state_changed(_is_open: bool) -> void:
	_hover_action_key = ""
	_pressed_action_key = ""
	tree.queue_redraw()
