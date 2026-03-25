extends Control

@onready var tex_rect: TextureRect = $TextureRect
@onready var ui_root: Control = $UIControl
@onready var top_bar: Control = $UIControl/TopBar
@onready var clear_btn: Button = $UIControl/TopBar/MarginContainer/HBoxContainer/ClearButton
@onready var reset_btn: Button = $UIControl/TopBar/MarginContainer/HBoxContainer/ResetButton
@onready var next_btn: Button = $UIControl/TopBar/MarginContainer/HBoxContainer/NextButton
@onready var previous_btn: Button = $UIControl/TopBar/MarginContainer/HBoxContainer/PreviousButton
@onready var rulesets_btn: Button = $UIControl/TopBar/MarginContainer/HBoxContainer/RulesetsButton
@onready var modify_btn: Button = $UIControl/TopBar/MarginContainer/HBoxContainer/ModifyButton
@onready var confirm_btn: Button = $UIControl/SavePanel/MarginContainer/VBoxContainer/HBoxContainer/ConfirmButton
@onready var cancel_btn: Button = $UIControl/SavePanel/MarginContainer/VBoxContainer/HBoxContainer/CancelButton
@onready var save_as_btn: Button = $UIControl/TopBar/MarginContainer/HBoxContainer/SaveAsButton
@onready var save_btn: Button = $UIControl/TopBar/MarginContainer/HBoxContainer/SaveButton
@onready var save_panel: Control = $UIControl/SavePanel
@onready var modify_panel: ModifyPanel = $UIControl/ModifyPanel
@onready var advanced_panel: AdvancedPanel = $UIControl/AdvancedPanel
@onready var modify_close_btn: Button = $UIControl/ModifyPanel/CloseButton
@onready var undo_btn: Button = $UIControl/ModifyPanel/MarginContainer/VBoxContainer/MiscContainer/UndoButton
@onready var redo_btn: Button = $UIControl/ModifyPanel/MarginContainer/VBoxContainer/MiscContainer/RedoButton
@onready var fps_label: Label = $UIControl/FPSLabel
@onready var name_edit: LineEdit = $UIControl/SavePanel/MarginContainer/VBoxContainer/MarginContainer/NameEdit
@onready var ruleset_popup: RulesetPopup = $UIControl/RulesetPopup

var W: int = 1
var H: int = 1
var SCALE: int = 3
const LOCAL_X := 16
const LOCAL_Y := 16
const MAX_RADIUS := 12
const TRACKPAD_SCROLL_SENSITIVITY := 0.06
const RULESET_HISTORY_MAX := 64
const GENERATED_PATTERN_HISTORY_MAX := 64
const FPS_LABEL_MARGIN_X := 20.0
const FPS_LABEL_MARGIN_Y := 20.0
const THRESHOLD_FLOAT_COUNT := 32
const THRESHOLD_PAIRS_PER_CANDIDATE := 4
const WEIGHT_COUNT := 16
const NEIGHBORHOOD_INT_COUNT := 8
const CHANNEL_FLOAT_COUNT := WEIGHT_COUNT * 6
const CHANNEL_TRIPLET_SIZE := 3
const SAVE_PANEL_DIM_ALPHA := 0.75
const STEP_SHADER_PATH := "res://shaders/ca_step.glsl"
const SPLIT_REGION_COUNT := 12
const SPLIT_VARIANT_COUNT := SPLIT_REGION_COUNT - 1
const SPLIT_COL_COUNT := 4
const SPLIT_ROW_COUNT := 3
const SPLIT_HISTORY_MAX := 64
const SIM_ZOOM_MIN := 1.0
const SIM_ZOOM_MAX := 16.0
const SIM_ZOOM_STEP := 1.12
const BRUSH_PREVIEW_Z_INDEX := 0

var store: DiskStore
var sim: SimGPU
var ruleset_controller: RulesetController
var history_controller: HistoryController
var input_controller: InputController
var midi_controller: MidiController
var modify_fade_tween: Tween
var save_fade_tween: Tween
var modify_input_blocker: ColorRect
var advanced_input_blocker: ColorRect
var opened_saved_ruleset_index := -1
var save_target_ruleset_index := -1
var sim_paused := false
var line_edit_font: Font = preload("res://fonts/PixelOperator.ttf")
var line_edit_normal_style: StyleBoxFlat
var split_view: SplitView
var split_mode := false
var split_base_sim: SimGPU
var split_variant_sims: Array[SimGPU] = []
var split_ruleset_history: Array[Dictionary] = []
var split_ruleset_history_index := -1
var split_tile_w := 0
var split_tile_h := 0
var split_shared_seed := 0
var ui_chrome_hidden := false
var _ui_child_visibility_before_hide: Dictionary = {}
var sim_zoom := 1.0
var sim_origin := Vector2.ZERO
var sim_default_cursor: Texture2D
var sim_hover_cursor_plus: Texture2D
var sim_hover_cursor_square: Texture2D
var sim_hover_cursor_expand: Texture2D
var sim_hover_cursor_shrink: Texture2D
var sim_hover_cursor_active := false
var sim_hover_cursor_kind := -1
var sim_hover_cursor_bound := false
var brush_preview_overlay: BrushPreviewOverlay
var _midi_adjusts_dirty := false
var _midi_threshold_adjust_dirty := false
var _midi_weight_adjust_dirty := false
var _midi_channel_adjust_dirty := false
var _midi_threshold_adjust_pending := 0.0
var _midi_weight_adjust_pending := 0.0
var _midi_channel_adjust_pending := 0.0


func _ready() -> void:
	Engine.max_fps = 5000
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

	var proj_w := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var proj_h := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	if proj_w <= 0 or proj_h <= 0:
		var win_size: Vector2i = get_window().size
		proj_w = win_size.x
		proj_h = win_size.y
	W = maxi(1, int(floor(float(proj_w) / float(SCALE))))
	H = maxi(1, int(floor(float(proj_h) / float(SCALE))))
	_reset_sim_view_transform()
	_layout_top_bars()
	_layout_save_panel_centered()
	_create_split_view()
	_setup_sim_hover_cursor()
	_create_brush_preview_overlay()

	# Modules
	store = DiskStore.new()
	store.load_from_disk()

	var rd := RenderingServer.get_rendering_device()
	sim = SimGPU.new()
	sim.init(rd, STEP_SHADER_PATH, W, H, LOCAL_X, LOCAL_Y, MAX_RADIUS, float(SCALE))
	ruleset_controller = RulesetController.new()
	ruleset_controller.init(store, sim, THRESHOLD_FLOAT_COUNT, NEIGHBORHOOD_INT_COUNT, WEIGHT_COUNT)
	history_controller = HistoryController.new()
	history_controller.init(
		sim,
		THRESHOLD_FLOAT_COUNT,
		NEIGHBORHOOD_INT_COUNT,
		WEIGHT_COUNT,
		RULESET_HISTORY_MAX,
		GENERATED_PATTERN_HISTORY_MAX
	)

	# Display
	tex_rect.texture = sim.get_display_texture()
	if not _apply_random_favorite_on_startup():
		sim.seed_random()

	modify_panel.set_data(
		sim.get_current_thresholds(),
		sim.get_current_neighborhoods(),
		sim.get_current_weights(),
		sim.get_current_channels(),
		sim.get_current_candidate_neighborhood_counts(),
		sim.get_candidate_enableds(),
		sim.get_seed_noise_bias(),
		sim.get_blend_k(),
		sim.get_decay_rate()
	)
	_refresh_modify_panel_runtime_displays()
	if not modify_panel.candidate_toggled.is_connected(_on_modify_candidate_toggled):
		modify_panel.candidate_toggled.connect(_on_modify_candidate_toggled)
	if not modify_panel.seed_bias_changed.is_connected(_on_modify_seed_bias_changed):
		modify_panel.seed_bias_changed.connect(_on_modify_seed_bias_changed)
	if not modify_panel.seed_bias_committed.is_connected(_on_modify_seed_bias_committed):
		modify_panel.seed_bias_committed.connect(_on_modify_seed_bias_committed)
	if not modify_panel.blend_value_changed.is_connected(_on_modify_blend_value_changed):
		modify_panel.blend_value_changed.connect(_on_modify_blend_value_changed)
	if not modify_panel.blend_value_committed.is_connected(_on_modify_blend_value_committed):
		modify_panel.blend_value_committed.connect(_on_modify_blend_value_committed)
	if not modify_panel.decay_rate_changed.is_connected(_on_modify_decay_rate_changed):
		modify_panel.decay_rate_changed.connect(_on_modify_decay_rate_changed)
	if not modify_panel.decay_rate_committed.is_connected(_on_modify_decay_rate_committed):
		modify_panel.decay_rate_committed.connect(_on_modify_decay_rate_committed)
	if not modify_panel.random_delta_requested.is_connected(_on_modify_random_delta_requested):
		modify_panel.random_delta_requested.connect(_on_modify_random_delta_requested)
	if not modify_panel.parent_action_pressed.is_connected(_on_modify_parent_action_pressed):
		modify_panel.parent_action_pressed.connect(_on_modify_parent_action_pressed)
	if not modify_panel.split_toggled.is_connected(_on_modify_split_toggled):
		modify_panel.split_toggled.connect(_on_modify_split_toggled)
	if not modify_panel.shuffle_channels_requested.is_connected(_on_modify_shuffle_channels_requested):
		modify_panel.shuffle_channels_requested.connect(_on_modify_shuffle_channels_requested)
	if not modify_panel.ruleset_name_changed.is_connected(_on_modify_ruleset_name_changed):
		modify_panel.ruleset_name_changed.connect(_on_modify_ruleset_name_changed)
	if not modify_panel.advanced_values_changed.is_connected(_on_modify_advanced_values_changed):
		modify_panel.advanced_values_changed.connect(_on_modify_advanced_values_changed)

	# UI
	modify_input_blocker = ColorRect.new()
	modify_input_blocker.name = "InputBlocker"
	modify_input_blocker.color = Color(0, 0, 0, 0) # invisible
	modify_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	modify_input_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	modify_input_blocker.visible = false
	modify_input_blocker.z_index = 1000
	modify_panel.add_child(modify_input_blocker)
	advanced_input_blocker = ColorRect.new()
	advanced_input_blocker.name = "InputBlocker"
	advanced_input_blocker.color = Color(0, 0, 0, 0) # invisible
	advanced_input_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	advanced_input_blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	advanced_input_blocker.visible = false
	advanced_input_blocker.z_index = 1000
	advanced_panel.add_child(advanced_input_blocker)
	modify_panel.visible = false
	ruleset_popup.ruleset_selected.connect(_on_ruleset_selected)
	ruleset_popup.ruleset_delete_pressed.connect(_on_ruleset_delete_from_popup)
	ruleset_popup.ruleset_favorite_toggled.connect(_on_ruleset_favorite_toggled)
	_rebuild_ruleset_menu()
	_disable_button_keyboard_focus(ui_root)
	_disable_button_keyboard_focus(ruleset_popup)
	line_edit_normal_style = _make_line_edit_normal_style()
	_apply_line_edit_font(ui_root)
	_apply_line_edit_font(ruleset_popup)
	_history_reset_to_current_state()
	_update_button_states()

	input_controller = InputController.new()
	input_controller.init(
		self,
		tex_rect,
		ui_root,
		top_bar,
		modify_panel,
		advanced_panel,
		ruleset_popup,
		save_panel,
		undo_btn,
		redo_btn,
		clear_btn,
		reset_btn,
		next_btn,
		previous_btn,
		save_as_btn,
		save_btn,
		confirm_btn,
		W,
		H,
		TRACKPAD_SCROLL_SENSITIVITY,
		Callable(self, "_toggle_pause"),
		Callable(self, "_toggle_ui_chrome_visibility"),
		Callable(self, "_on_clear_button_pressed"),
		Callable(self, "_on_reset_button_pressed"),
		Callable(self, "_on_randomize_button_pressed"),
		Callable(self, "_on_previous_button_pressed"),
		Callable(self, "_on_view_switch_shortcut_pressed"),
		Callable(self, "_on_undo_button_pressed"),
		Callable(self, "_on_redo_button_pressed"),
		Callable(self, "_can_undo"),
		Callable(self, "_can_redo"),
		Callable(self, "_set_brush_active_from_input"),
		Callable(self, "_adjust_brush_radius_from_input"),
		Callable(self, "_set_brush_center_from_input"),
		Callable(self, "_zoom_sim_view_from_input"),
		Callable(self, "_pan_sim_view_from_input"),
		Callable(self, "_on_save_as_button_pressed"),
		Callable(self, "_on_save_ruleset_button_pressed"),
		Callable(self, "_on_save_as_confirm_pressed"),
		Callable(self, "_stamp_brush_once_from_input")
	)
	midi_controller = MidiController.new()
	midi_controller.init(
		Callable(self, "_on_clear_button_pressed"),
		Callable(self, "_on_reset_button_pressed"),
		Callable(self, "_on_randomize_button_pressed"),
		Callable(self, "_on_previous_button_pressed"),
		Callable(self, "_on_view_switch_shortcut_pressed"),
		Callable(self, "_on_midi_blend_changed"),
		Callable(self, "_on_midi_threshold_adjust_changed"),
		Callable(self, "_on_midi_weight_adjust_changed"),
		Callable(self, "_on_midi_channel_adjust_changed"),
		Callable(self, "_on_midi_seed_bias_changed"),
		Callable(self, "_on_midi_decay_changed")
	)
	call_deferred("_open_midi_inputs_deferred")

	# (Optional) connect signals in code if not connected in editor
	if not clear_btn.pressed.is_connected(_on_clear_button_pressed):
		clear_btn.pressed.connect(_on_clear_button_pressed)
	if not reset_btn.pressed.is_connected(_on_reset_button_pressed):
		reset_btn.pressed.connect(_on_reset_button_pressed)
	if next_btn != null and not next_btn.pressed.is_connected(_on_randomize_button_pressed):
		next_btn.pressed.connect(_on_randomize_button_pressed)
	if previous_btn != null and not previous_btn.pressed.is_connected(_on_previous_button_pressed):
		previous_btn.pressed.connect(_on_previous_button_pressed)
	if not modify_btn.pressed.is_connected(_on_modify_button_pressed):
		modify_btn.pressed.connect(_on_modify_button_pressed)
	if not save_as_btn.pressed.is_connected(_on_save_as_button_pressed):
		save_as_btn.pressed.connect(_on_save_as_button_pressed)
	if not save_btn.pressed.is_connected(_on_save_ruleset_button_pressed):
		save_btn.pressed.connect(_on_save_ruleset_button_pressed)
	if not confirm_btn.pressed.is_connected(_on_save_as_confirm_pressed):
		confirm_btn.pressed.connect(_on_save_as_confirm_pressed)
	if not cancel_btn.pressed.is_connected(_on_save_cancel_pressed):
		cancel_btn.pressed.connect(_on_save_cancel_pressed)
	if modify_close_btn != null and not modify_close_btn.pressed.is_connected(_on_modify_close_pressed):
		modify_close_btn.pressed.connect(_on_modify_close_pressed)
	if undo_btn != null and not undo_btn.pressed.is_connected(_on_undo_button_pressed):
		undo_btn.pressed.connect(_on_undo_button_pressed)
	if redo_btn != null and not redo_btn.pressed.is_connected(_on_redo_button_pressed):
		redo_btn.pressed.connect(_on_redo_button_pressed)

	_update_fps_label()

func _apply_random_favorite_on_startup() -> bool:
	if store == null or ruleset_controller == null:
		return false
	var favorite_indices := PackedInt32Array()
	for i in range(store.rulesets.size()):
		var rs_var: Variant = store.rulesets[i]
		if typeof(rs_var) != TYPE_DICTIONARY:
			continue
		var rs: Dictionary = rs_var
		if bool(rs.get("favorite", false)):
			favorite_indices.append(i)
	if favorite_indices.is_empty():
		return false
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var pick_pos := rng.randi_range(0, favorite_indices.size() - 1)
	var picked_idx := int(favorite_indices[pick_pos])
	if not ruleset_controller.apply_ruleset_by_index(picked_idx):
		return false
	opened_saved_ruleset_index = picked_idx
	save_target_ruleset_index = picked_idx
	return true


func _exit_tree() -> void:
	# Important: release GPU resources
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if midi_controller != null:
		midi_controller.close_inputs()
	if split_base_sim != null:
		split_base_sim.free_all()
		split_base_sim = null
	for variant in split_variant_sims:
		if variant != null:
			variant.free_all()
	split_variant_sims.clear()
	if sim != null:
		sim.free_all()


func _process(dt: float) -> void:
	_flush_pending_midi_adjusts()
	if not sim_paused:
		if split_mode:
			if split_base_sim != null:
				split_base_sim.step()
			for variant in split_variant_sims:
				if variant != null:
					variant.step()
		else:
			sim.step()
	_update_sim_hover_cursor_state()
	_update_brush_size_preview()
	_update_fps_label()

func _queue_midi_threshold_adjust(v: float) -> void:
	_midi_threshold_adjust_pending = v
	_midi_threshold_adjust_dirty = true
	_midi_adjusts_dirty = true

func _queue_midi_weight_adjust(v: float) -> void:
	_midi_weight_adjust_pending = v
	_midi_weight_adjust_dirty = true
	_midi_adjusts_dirty = true

func _queue_midi_channel_adjust(v: float) -> void:
	_midi_channel_adjust_pending = v
	_midi_channel_adjust_dirty = true
	_midi_adjusts_dirty = true

func _flush_pending_midi_adjusts() -> void:
	if not _midi_adjusts_dirty or sim == null:
		return
	var apply_threshold := _midi_threshold_adjust_dirty
	var apply_weight := _midi_weight_adjust_dirty
	var apply_channel := _midi_channel_adjust_dirty
	if apply_threshold:
		sim.set_threshold_adjust(_midi_threshold_adjust_pending)
	if apply_weight:
		sim.set_weight_adjust(_midi_weight_adjust_pending)
	if apply_channel:
		sim.set_channel_adjust(_midi_channel_adjust_pending)
	if split_base_sim != null:
		if apply_threshold:
			split_base_sim.set_threshold_adjust(_midi_threshold_adjust_pending)
		if apply_weight:
			split_base_sim.set_weight_adjust(_midi_weight_adjust_pending)
		if apply_channel:
			split_base_sim.set_channel_adjust(_midi_channel_adjust_pending)
	for variant in split_variant_sims:
		if variant == null:
			continue
		if apply_threshold:
			variant.set_threshold_adjust(_midi_threshold_adjust_pending)
		if apply_weight:
			variant.set_weight_adjust(_midi_weight_adjust_pending)
		if apply_channel:
			variant.set_channel_adjust(_midi_channel_adjust_pending)
	_refresh_modify_panel_runtime_displays()
	_midi_threshold_adjust_dirty = false
	_midi_weight_adjust_dirty = false
	_midi_channel_adjust_dirty = false
	_midi_adjusts_dirty = false


# ---------------- RULESETS MENU / STORE ----------------

func _rebuild_ruleset_menu() -> void:
	if ruleset_controller != null:
		ruleset_controller.rebuild_ruleset_menu(ruleset_popup, _current_save_target_ruleset_index())
	_disable_button_keyboard_focus(ruleset_popup)


func _on_ruleset_selected(id: int) -> void:
	if ruleset_controller == null:
		return
	_ensure_single_view()
	if modify_panel != null:
		modify_panel.hide_advanced_panel()
	if history_controller != null:
		history_controller.push_generated_pattern_snapshot(opened_saved_ruleset_index)
	if not ruleset_controller.apply_ruleset_by_index(id):
		return
	_split_history_clear()

	modify_panel.set_data(
		sim.get_current_thresholds(),
		sim.get_current_neighborhoods(),
		sim.get_current_weights(),
		sim.get_current_channels(),
		sim.get_current_candidate_neighborhood_counts(),
		sim.get_candidate_enableds(),
		sim.get_seed_noise_bias(),
		sim.get_blend_k(),
		sim.get_decay_rate()
	)
	_refresh_modify_panel_runtime_displays()
	opened_saved_ruleset_index = id
	save_target_ruleset_index = id
	if history_controller != null:
		history_controller.push_generated_pattern_snapshot(opened_saved_ruleset_index)
	_sync_selected_ruleset_index_from_current_state()
	_history_reset_to_current_state()


# ---------------- BUTTONS ----------------

func _on_reset_button_pressed() -> void:
	if split_mode:
		_reseed_split_sims_shared()
		return
	sim.reset_state()
	# selection stays the same

func _on_randomize_button_pressed() -> void:
	_ensure_single_view()
	if modify_panel != null:
		modify_panel.hide_advanced_panel()
	if history_controller == null:
		return
	history_controller.ensure_generated_current_state(opened_saved_ruleset_index)
	var result := history_controller.restore_next_generated_pattern()
	if bool(result.get("ok", false)):
		_split_history_clear()
		_apply_generated_pattern_restore_result(result)
		_sync_selected_ruleset_index_from_current_state()
		_history_reset_to_current_state()
		return
	if bool(result.get("failed_restore", false)):
		push_warning("Next restore failed; dropping snapshot.")

	# No forward entry left: branch by capturing current state, then generate/apply a new one.
	history_controller.push_generated_pattern_snapshot(opened_saved_ruleset_index)
	sim.randomize_params_and_reset()
	_split_history_clear()
	opened_saved_ruleset_index = -1
	save_target_ruleset_index = -1
	history_controller.push_generated_pattern_snapshot(opened_saved_ruleset_index)
	_refresh_ui_after_sim_state_change()
	_sync_selected_ruleset_index_from_current_state()
	_history_reset_to_current_state()

func _on_previous_button_pressed() -> void:
	_ensure_single_view()
	if history_controller == null:
		return
	history_controller.ensure_generated_current_state(opened_saved_ruleset_index)
	var result := history_controller.restore_previous_generated_pattern()
	if not bool(result.get("ok", false)):
		if bool(result.get("failed_restore", false)):
			push_warning("Previous restore failed; dropping snapshot.")
		_update_button_states()
		return
	_apply_generated_pattern_restore_result(result)
	_sync_selected_ruleset_index_from_current_state()
	_history_reset_to_current_state()

func _on_view_switch_shortcut_pressed() -> void:
	if modify_panel != null:
		modify_panel.set_split_mode(not split_mode, true)
	else:
		_set_split_mode(not split_mode)

func _on_modify_shuffle_channels_requested() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var permutation := _random_non_identity_rgb_permutation(rng)
	if split_mode:
		if not _apply_rgb_shuffle_to_sim(sim, permutation):
			return
		if split_base_sim != null and not _apply_rgb_shuffle_to_sim(split_base_sim, permutation):
			return
		for variant in split_variant_sims:
			if variant == null:
				continue
			if not _apply_rgb_shuffle_to_sim(variant, permutation):
				return
		_update_split_view_textures()
	else:
		if not _apply_rgb_shuffle_to_sim(sim, permutation):
			return
	_refresh_ui_after_sim_state_change()
	_sync_selected_ruleset_index_from_current_state()
	_record_current_ruleset_state()

func _apply_generated_pattern_restore_result(result: Dictionary) -> void:
	var restored_opened := int(result.get("opened_saved_ruleset_index", -1))
	var ruleset_count := ruleset_controller.ruleset_count() if ruleset_controller != null else 0
	if restored_opened >= 0 and restored_opened < ruleset_count:
		opened_saved_ruleset_index = restored_opened
	else:
		opened_saved_ruleset_index = -1
	save_target_ruleset_index = opened_saved_ruleset_index
	# Next/Previous should always start from a fresh canvas for the restored params.
	sim.reset_state()
	_refresh_ui_after_sim_state_change()

func _refresh_ui_after_sim_state_change() -> void:
	modify_panel.set_data(
		sim.get_current_thresholds(),
		sim.get_current_neighborhoods(),
		sim.get_current_weights(),
		sim.get_current_channels(),
		sim.get_current_candidate_neighborhood_counts(),
		sim.get_candidate_enableds(),
		sim.get_seed_noise_bias(),
		sim.get_blend_k(),
		sim.get_decay_rate()
	)
	_refresh_modify_panel_runtime_displays()

func _refresh_modify_panel_runtime_displays() -> void:
	if modify_panel == null or sim == null:
		return
	modify_panel.set_display_runtime_values(
		sim.get_runtime_thresholds(),
		sim.get_runtime_weights(),
		sim.get_runtime_channels()
	)

func _on_clear_button_pressed() -> void:
	if split_mode:
		if split_base_sim != null:
			split_base_sim.seed_empty()
		for variant in split_variant_sims:
			if variant != null:
				variant.seed_empty()
		_update_split_view_textures()
		return
	sim.seed_empty()

func _can_go_to_previous_generated_pattern() -> bool:
	return history_controller != null and history_controller.can_restore_previous_generated_pattern()

func _on_save_as_button_pressed() -> void:
	_layout_save_panel_centered()
	save_fade_tween = _fade_in_panel(save_panel, save_fade_tween)
	name_edit.grab_focus()
	name_edit.text = ""
	_set_modify_interaction_enabled(false)
	_set_save_panel_dim(true)
	_update_button_states()

func _on_modify_button_pressed() -> void:
	modify_panel.collapse_sections_for_open()
	modify_fade_tween = _fade_in_panel(modify_panel, modify_fade_tween)
	_update_button_states()

func _on_modify_close_pressed() -> void:
	modify_panel.hide_advanced_panel()
	modify_fade_tween = _fade_out_panel(modify_panel, modify_fade_tween)

func _on_save_cancel_pressed() -> void:
	save_fade_tween = _fade_out_panel(save_panel, save_fade_tween)
	save_fade_tween.finished.connect(func():
		_set_modify_interaction_enabled(true)
		_set_save_panel_dim(false)
		_update_button_states()
	)

func _on_save_as_confirm_pressed() -> void:
	if ruleset_controller == null:
		return
	var ruleset_name := _resolve_ruleset_name_for_save(name_edit.text, -1)
	if _ruleset_name_exists(ruleset_name):
		push_warning("Ruleset name already exists: " + ruleset_name)
		name_edit.text = "Already exists!"
		name_edit.grab_focus()
		name_edit.select_all()
		return
	var new_idx := ruleset_controller.save_current_as(ruleset_name)
	if new_idx < 0:
		return
	opened_saved_ruleset_index = new_idx
	save_target_ruleset_index = new_idx
	_retarget_current_ruleset_state_to_current_save_target()
	_rebuild_ruleset_menu()
	save_fade_tween = _fade_out_panel(save_panel, save_fade_tween)
	save_fade_tween.finished.connect(func():
		_set_modify_interaction_enabled(true)
		_set_save_panel_dim(false)
		_update_button_states()
	)
	_sync_selected_ruleset_index_from_current_state()

func _on_save_ruleset_button_pressed() -> void:
	if not _can_save_over_original_ruleset():
		return
	if ruleset_controller == null:
		return
	var idx := _current_save_target_ruleset_index()
	if idx < 0 or idx >= ruleset_controller.ruleset_count():
		return
	var current_name := ruleset_controller.get_ruleset_name(idx).strip_edges()
	var requested_name := current_name
	if modify_panel != null:
		requested_name = _resolve_ruleset_name_for_save(modify_panel.get_ruleset_name_input_text(), idx)
	var did_rename := false
	if requested_name != current_name:
		if ruleset_controller.ruleset_name_exists_except(requested_name, idx):
			push_warning("Ruleset name already exists: " + requested_name)
			if modify_panel != null:
				modify_panel.show_ruleset_name_duplicate_error()
			return
		if not ruleset_controller.rename_ruleset(idx, requested_name):
			return
		did_rename = true
	var can_save_params := ruleset_controller.can_save_over_original_ruleset(idx)
	if can_save_params:
		if not ruleset_controller.update_current_into_ruleset(idx):
			return
	elif not did_rename:
		return
	opened_saved_ruleset_index = idx
	save_target_ruleset_index = idx
	_retarget_current_ruleset_state_to_current_save_target()
	_rebuild_ruleset_menu()
	_update_modify_ruleset_name_context(true)
	_sync_selected_ruleset_index_from_current_state()


func _update_button_states() -> void:
	var blocked := save_panel.visible
	clear_btn.disabled = blocked
	reset_btn.disabled = blocked
	if next_btn != null:
		next_btn.disabled = blocked
	if previous_btn != null:
		if split_mode:
			previous_btn.disabled = blocked
		else:
			previous_btn.disabled = blocked or not _can_go_to_previous_generated_pattern()
	var selected_idx := ruleset_controller.get_selected_ruleset_index() if ruleset_controller != null else -1
	var matches_saved_ruleset := selected_idx != -1
	save_as_btn.disabled = (matches_saved_ruleset or blocked)
	save_btn.disabled = blocked or not _can_save_over_original_ruleset()
	rulesets_btn.disabled = blocked
	modify_btn.disabled = save_panel.visible or modify_panel.visible
	if undo_btn != null:
		undo_btn.disabled = blocked or not modify_panel.visible or not _can_undo()
	if redo_btn != null:
		redo_btn.disabled = blocked or not modify_panel.visible or not _can_redo()
	_update_modify_ruleset_name_context()

func _set_save_panel_dim(dimmed: bool) -> void:
	var dim_alpha := SAVE_PANEL_DIM_ALPHA if dimmed else 1.0
	if modify_panel != null:
		modify_panel.modulate.a = dim_alpha
	if advanced_panel != null:
		advanced_panel.modulate.a = dim_alpha

func _on_rulesets_button_pressed() -> void:
	_rebuild_ruleset_menu()
	var r := rulesets_btn.get_global_rect()
	ruleset_popup.position = Vector2i(r.position.x, r.position.y + r.size.y)
	ruleset_popup.popup()

func _on_ruleset_delete_from_popup(id: int) -> void:
	if ruleset_controller == null:
		return
	opened_saved_ruleset_index = ruleset_controller.delete_ruleset(id, opened_saved_ruleset_index)
	save_target_ruleset_index = opened_saved_ruleset_index
	_rebuild_ruleset_menu()
	_sync_selected_ruleset_index_from_current_state()

func _on_ruleset_favorite_toggled(index: int, is_favorite: bool) -> void:
	if ruleset_controller == null:
		return
	if not ruleset_controller.set_favorite(index, is_favorite):
		return
	_rebuild_ruleset_menu()

func _on_modify_candidate_toggled(candidate_index: int, enabled: bool) -> void:
	sim.set_candidate_enabled(candidate_index, enabled)
	if split_mode:
		_regenerate_split_variants_from_base()
	_sync_selected_ruleset_index_from_current_state()
	_record_current_ruleset_state()

func _on_modify_seed_bias_changed(value: float) -> void:
	sim.set_seed_noise_bias(value)
	_sync_selected_ruleset_index_from_current_state()

func _on_modify_seed_bias_committed(_value: float) -> void:
	if split_mode:
		_regenerate_split_variants_from_base()
	_record_current_ruleset_state()

func _on_modify_blend_value_changed(value: float) -> void:
	sim.set_blend_k(value)
	_sync_selected_ruleset_index_from_current_state()

func _on_modify_blend_value_committed(_value: float) -> void:
	if split_mode:
		_regenerate_split_variants_from_base()
	_record_current_ruleset_state()

func _on_modify_decay_rate_changed(value: float) -> void:
	sim.set_decay_rate(value)
	_sync_selected_ruleset_index_from_current_state()

func _on_modify_decay_rate_committed(_value: float) -> void:
	if split_mode:
		_regenerate_split_variants_from_base()
	_record_current_ruleset_state()

func _on_modify_ruleset_name_changed(_text: String) -> void:
	_update_button_states()

func _on_modify_random_delta_requested(target: String, flip_chance: float) -> void:
	var bit_flip_chance := _normalize_flip_chance(flip_chance)
	if bit_flip_chance <= 0.0:
		return

	var apply_thr := (target == "all" or target == "thresholds")
	var apply_nh := (target == "all" or target == "neighborhoods")
	var apply_w := (target == "all" or target == "weights")
	var apply_ch := (target == "all" or target == "channels")
	if not apply_thr and not apply_nh and not apply_w and not apply_ch:
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()

	if apply_thr:
		if not sim.flip_threshold_bits(_make_index_range(0, THRESHOLD_FLOAT_COUNT), rng, bit_flip_chance):
			return

	if apply_nh:
		if not sim.flip_neighborhood_bits(_make_index_range(0, NEIGHBORHOOD_INT_COUNT), rng, bit_flip_chance):
			return

	if apply_w:
		if not sim.flip_weight_bits(_make_index_range(0, WEIGHT_COUNT), rng, bit_flip_chance):
			return

	if apply_ch:
		if not sim.flip_channel_bits(_make_index_range(0, CHANNEL_FLOAT_COUNT), rng, bit_flip_chance):
			return

	modify_panel.set_data(
		sim.get_current_thresholds(),
		sim.get_current_neighborhoods(),
		sim.get_current_weights(),
		sim.get_current_channels(),
		sim.get_current_candidate_neighborhood_counts(),
		sim.get_candidate_enableds(),
		sim.get_seed_noise_bias(),
		sim.get_blend_k(),
		sim.get_decay_rate()
	)
	_refresh_modify_panel_runtime_displays()
	if split_mode:
		_regenerate_split_variants_from_base()
	_sync_selected_ruleset_index_from_current_state()
	_record_current_ruleset_state()

func _on_modify_parent_action_pressed(kind: String, candidate_index: int, flip_chance: float) -> void:
	if candidate_index < 0 or candidate_index >= 4:
		return
	var bit_flip_chance := _normalize_flip_chance(flip_chance)
	if bit_flip_chance <= 0.0:
		return

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var counts := sim.get_current_candidate_neighborhood_counts()
	var nh_range := _candidate_neighborhood_range(candidate_index, counts)
	var thr_range := _candidate_threshold_range(candidate_index, counts)
	var w_range := _candidate_weight_range(candidate_index, counts)
	var ch_range := _candidate_channel_range(candidate_index, counts)

	if kind == "all":
		if not sim.flip_threshold_bits(_make_index_range(thr_range.x, thr_range.y), rng, bit_flip_chance):
			return
		if not sim.flip_neighborhood_bits(_make_index_range(nh_range.x, nh_range.y), rng, bit_flip_chance):
			return
		if not sim.flip_weight_bits(_make_index_range(w_range.x, w_range.y), rng, bit_flip_chance):
			return
		if not sim.flip_channel_bits(_make_index_range(ch_range.x, ch_range.y), rng, bit_flip_chance):
			return
	elif kind == "thresholds":
		if not sim.flip_threshold_bits(_make_index_range(thr_range.x, thr_range.y), rng, bit_flip_chance):
			return
	elif kind == "neighborhoods":
		if not sim.flip_neighborhood_bits(_make_index_range(nh_range.x, nh_range.y), rng, bit_flip_chance):
			return
	elif kind == "weights":
		if not sim.flip_weight_bits(_make_index_range(w_range.x, w_range.y), rng, bit_flip_chance):
			return
	elif kind == "channels":
		if not sim.flip_channel_bits(_make_index_range(ch_range.x, ch_range.y), rng, bit_flip_chance):
			return
	else:
		return

	modify_panel.set_data(
		sim.get_current_thresholds(),
		sim.get_current_neighborhoods(),
		sim.get_current_weights(),
		sim.get_current_channels(),
		sim.get_current_candidate_neighborhood_counts(),
		sim.get_candidate_enableds(),
		sim.get_seed_noise_bias(),
		sim.get_blend_k(),
		sim.get_decay_rate()
	)
	_refresh_modify_panel_runtime_displays()
	if split_mode:
		_regenerate_split_variants_from_base()
	_sync_selected_ruleset_index_from_current_state()
	_record_current_ruleset_state()

func _on_modify_advanced_values_changed(
	thresholds: PackedFloat32Array,
	neighborhoods: PackedInt32Array,
	weights: PackedFloat32Array,
	channels: PackedFloat32Array,
	committed: bool
) -> void:
	var ok := sim.set_thresholds(thresholds)
	ok = ok and sim.set_neighborhoods(neighborhoods)
	ok = ok and sim.set_weights(weights)
	ok = ok and sim.set_channels(channels)
	if not ok:
		return
	if split_mode and committed:
		_regenerate_split_variants_from_base()
	_sync_selected_ruleset_index_from_current_state()
	if committed:
		_record_current_ruleset_state()

func _on_undo_button_pressed() -> void:
	if split_mode:
		if not _split_undo():
			return
		_refresh_ui_after_sim_state_change()
		_sync_selected_ruleset_index_from_current_state()
		_update_button_states()
		return
	if history_controller == null:
		return
	if not history_controller.undo():
		return
	_restore_working_save_target(history_controller.get_current_ruleset_history_save_target())
	modify_panel.set_data(
		sim.get_current_thresholds(),
		sim.get_current_neighborhoods(),
		sim.get_current_weights(),
		sim.get_current_channels(),
		sim.get_current_candidate_neighborhood_counts(),
		sim.get_candidate_enableds(),
		sim.get_seed_noise_bias(),
		sim.get_blend_k(),
		sim.get_decay_rate()
	)
	_refresh_modify_panel_runtime_displays()
	_sync_selected_ruleset_index_from_current_state()
	_update_button_states()

func _on_redo_button_pressed() -> void:
	if split_mode:
		if not _split_redo():
			return
		_refresh_ui_after_sim_state_change()
		_sync_selected_ruleset_index_from_current_state()
		_update_button_states()
		return
	if history_controller == null:
		return
	if not history_controller.redo():
		return
	_restore_working_save_target(history_controller.get_current_ruleset_history_save_target())
	modify_panel.set_data(
		sim.get_current_thresholds(),
		sim.get_current_neighborhoods(),
		sim.get_current_weights(),
		sim.get_current_channels(),
		sim.get_current_candidate_neighborhood_counts(),
		sim.get_candidate_enableds(),
		sim.get_seed_noise_bias(),
		sim.get_blend_k(),
		sim.get_decay_rate()
	)
	_refresh_modify_panel_runtime_displays()
	_sync_selected_ruleset_index_from_current_state()
	_update_button_states()

func _set_modify_interaction_enabled(enabled: bool) -> void:
	if modify_input_blocker != null:
		modify_input_blocker.visible = not enabled
	if advanced_input_blocker != null:
		advanced_input_blocker.visible = not enabled


# ---------------- SPLIT VIEW ----------------

func _create_split_view() -> void:
	if split_view != null:
		return
	split_view = SplitView.new()
	split_view.name = "SplitView"
	split_view.visible = false
	if ui_root != null:
		ui_root.add_child(split_view)
		ui_root.move_child(split_view, 0)
	else:
		add_child(split_view)
	_layout_split_view_to_texture_rect()
	if not split_view.region_clicked.is_connected(_on_split_region_clicked):
		split_view.region_clicked.connect(_on_split_region_clicked)


func _layout_split_view_to_texture_rect() -> void:
	if split_view == null or tex_rect == null:
		return
	_apply_sim_view_transform()


func _create_brush_preview_overlay() -> void:
	if brush_preview_overlay != null:
		return
	brush_preview_overlay = BrushPreviewOverlay.new()
	brush_preview_overlay.name = "BrushPreviewOverlay"
	brush_preview_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brush_preview_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	brush_preview_overlay.z_index = BRUSH_PREVIEW_Z_INDEX
	add_child(brush_preview_overlay)
	# Keep preview above simulation but below the UI tree.
	if ui_root != null and ui_root.get_parent() == self:
		move_child(brush_preview_overlay, ui_root.get_index())


func _setup_sim_hover_cursor() -> void:
	if sim_default_cursor == null:
		sim_default_cursor = _make_cursor_texture_from_png("res://icons/cursor.png")
	if sim_hover_cursor_plus == null:
		sim_hover_cursor_plus = _make_cursor_texture_from_png("res://icons/cursor_plus.png")
	if sim_hover_cursor_square == null:
		sim_hover_cursor_square = _make_cursor_texture_from_png("res://icons/cursor_square.png")
	if sim_hover_cursor_expand == null:
		sim_hover_cursor_expand = _make_cursor_texture_from_png("res://icons/cursor_expand.png")
	if sim_hover_cursor_shrink == null:
		sim_hover_cursor_shrink = _make_cursor_texture_from_png("res://icons/cursor_shrink.png")
	if sim_default_cursor != null:
		Input.set_custom_mouse_cursor(sim_default_cursor, Input.CURSOR_ARROW, Vector2.ZERO)
	else:
		push_warning("Failed to initialize default cursor from res://icons/cursor.png")
	if sim_hover_cursor_plus == null:
		push_warning("Failed to initialize sim hover cursor from res://icons/cursor_plus.png")
	_apply_sim_cross_cursor_texture(1)
	sim_hover_cursor_active = false
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if ui_root != null:
		ui_root.mouse_default_cursor_shape = Control.CURSOR_ARROW
	_sync_sim_cursor_target_shapes()


func _make_cursor_texture_from_png(path: String) -> Texture2D:
	var tex: Texture2D = load(path) as Texture2D
	return tex


func _apply_sim_cross_cursor_texture(brush_mode: int) -> void:
	var target_kind := 0 # 0=plus, 1=square, 2=expand, 3=shrink
	if brush_mode == 4:
		target_kind = 3
	elif brush_mode == 2:
		target_kind = 1
	elif brush_mode == 3:
		target_kind = 2
	var tex: Texture2D = sim_hover_cursor_plus
	if target_kind == 1:
		tex = sim_hover_cursor_square
	elif target_kind == 2:
		tex = sim_hover_cursor_expand
	elif target_kind == 3:
		tex = sim_hover_cursor_shrink
	if tex == null:
		tex = sim_hover_cursor_plus
		target_kind = 0
	if tex == null:
		return
	if sim_hover_cursor_bound and sim_hover_cursor_kind == target_kind:
		return
	sim_hover_cursor_kind = target_kind
	sim_hover_cursor_bound = true
	var hotspot := Vector2(
		float(tex.get_width()) * 0.5,
		float(tex.get_height()) * 0.5
	)
	Input.set_custom_mouse_cursor(tex, Input.CURSOR_CROSS, hotspot)


func _sync_sim_cursor_target_shapes() -> void:
	var sim_shape: Control.CursorShape = Control.CURSOR_CROSS
	var split_shape: Control.CursorShape = Control.CURSOR_ARROW
	if split_mode:
		sim_shape = Control.CURSOR_ARROW
	if tex_rect != null:
		tex_rect.mouse_default_cursor_shape = sim_shape
	if split_view != null:
		split_view.set_cursor_shape(split_shape)


func _update_sim_hover_cursor_state() -> void:
	if input_controller == null:
		return
	var brush_mode := input_controller.get_brush_mode()
	_apply_sim_cross_cursor_texture(brush_mode)
	if split_mode:
		if sim_hover_cursor_active:
			sim_hover_cursor_active = false
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)
		if ui_root != null:
			ui_root.mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	var mouse_pos := get_viewport().get_mouse_position()
	var over_sim := input_controller.is_mouse_over_sim(mouse_pos)
	if over_sim == sim_hover_cursor_active:
		return
	sim_hover_cursor_active = over_sim
	var input_shape: Input.CursorShape = Input.CURSOR_CROSS if over_sim else Input.CURSOR_ARROW
	var control_shape: Control.CursorShape = Control.CURSOR_CROSS if over_sim else Control.CURSOR_ARROW
	Input.set_default_cursor_shape(input_shape)
	if ui_root != null:
		ui_root.mouse_default_cursor_shape = control_shape


func _update_brush_size_preview() -> void:
	if brush_preview_overlay == null:
		return
	if sim == null or tex_rect == null or input_controller == null:
		brush_preview_overlay.set_preview_state(false, Vector2.ZERO, 0.0)
		return
	if split_mode:
		brush_preview_overlay.set_preview_state(false, Vector2.ZERO, 0.0)
		return
	var show_preview := (
		Input.is_key_pressed(KEY_UP)
		or Input.is_key_pressed(KEY_DOWN)
	)
	if not show_preview:
		brush_preview_overlay.set_preview_state(false, Vector2.ZERO, 0.0)
		return
	var mouse_pos := get_viewport().get_mouse_position()
	if not input_controller.is_mouse_over_sim(mouse_pos):
		brush_preview_overlay.set_preview_state(false, Vector2.ZERO, 0.0)
		return
	var pixel_scale_x := tex_rect.size.x / float(maxi(1, W))
	var pixel_scale_y := tex_rect.size.y / float(maxi(1, H))
	var pixel_scale := (pixel_scale_x + pixel_scale_y) * 0.5
	var radius_px := maxf(1.0, sim.get_brush_radius() * pixel_scale)
	brush_preview_overlay.set_preview_state(true, mouse_pos, radius_px)


func _sim_base_size() -> Vector2:
	return Vector2(float(W * SCALE), float(H * SCALE))


func _reset_sim_view_transform() -> void:
	sim_zoom = 1.0
	sim_origin = Vector2.ZERO
	_clamp_sim_origin()
	_apply_sim_view_transform()


func _clamp_sim_origin() -> void:
	var base := _sim_base_size()
	var scaled := base * sim_zoom
	if scaled.x <= base.x:
		sim_origin.x = (base.x - scaled.x) * 0.5
	else:
		sim_origin.x = clampf(sim_origin.x, base.x - scaled.x, 0.0)
	if scaled.y <= base.y:
		sim_origin.y = (base.y - scaled.y) * 0.5
	else:
		sim_origin.y = clampf(sim_origin.y, base.y - scaled.y, 0.0)


func _apply_sim_view_transform() -> void:
	var base := _sim_base_size()
	var scaled := base * sim_zoom
	if tex_rect != null:
		tex_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
		tex_rect.position = sim_origin
		tex_rect.size = scaled
	if split_view != null:
		split_view.set_anchors_preset(Control.PRESET_TOP_LEFT)
		split_view.position = sim_origin
		split_view.size = scaled


func _zoom_sim_view_from_input(screen_pos: Vector2, steps: float) -> void:
	if is_zero_approx(steps):
		return
	var old_zoom := sim_zoom
	var factor := pow(SIM_ZOOM_STEP, steps)
	sim_zoom = clampf(sim_zoom * factor, SIM_ZOOM_MIN, SIM_ZOOM_MAX)
	if is_equal_approx(sim_zoom, old_zoom):
		return
	var local_before := (screen_pos - sim_origin) / old_zoom
	sim_origin = screen_pos - (local_before * sim_zoom)
	_clamp_sim_origin()
	_apply_sim_view_transform()


func _pan_sim_view_from_input(delta: Vector2) -> void:
	if is_zero_approx(delta.x) and is_zero_approx(delta.y):
		return
	if sim_zoom <= SIM_ZOOM_MIN + 0.0001:
		return
	sim_origin += delta
	_clamp_sim_origin()
	_apply_sim_view_transform()


func _on_modify_split_toggled(enabled: bool) -> void:
	if enabled and modify_panel != null:
		modify_panel.hide_advanced_panel()
	_set_split_mode(enabled)


func _ensure_single_view() -> void:
	if not split_mode:
		return
	if modify_panel != null and modify_panel.is_split_mode():
		modify_panel.set_split_mode(false, false)
	_set_split_mode(false)


func _set_split_mode(enabled: bool) -> void:
	if split_mode == enabled:
		return
	if enabled:
		_enter_split_mode()
	else:
		_exit_split_mode()
	_update_button_states()


func _enter_split_mode() -> void:
	_ensure_split_variant_sims()
	split_mode = true
	_sync_sim_cursor_target_shapes()
	tex_rect.visible = false
	if split_view != null:
		split_view.visible = true
	_layout_split_view_to_texture_rect()
	if _latest_split_parent_matches_current_parent():
		if not _restore_split_state_on_enter():
			# Parent matches latest split snapshot; do not regenerate variants.
			_update_split_view_textures()
			if split_ruleset_history.size() > 0:
				split_ruleset_history_index = split_ruleset_history.size() - 1
	else:
		# Sync split parent/top-left from current single-view state when needed.
		_regenerate_split_variants_from_base()
		_split_record_current_state()
	_refresh_ui_after_sim_state_change()
	_sync_selected_ruleset_index_from_current_state()
	_update_sim_hover_cursor_state()


func _exit_split_mode() -> void:
	split_mode = false
	_sync_sim_cursor_target_shapes()
	tex_rect.visible = true
	if split_view != null:
		split_view.visible = false
		split_view.clear_textures()
	if split_base_sim != null:
		var base_ruleset := _capture_ruleset_from_sim(split_base_sim)
		if not base_ruleset.is_empty():
			if _apply_ruleset_to_sim(sim, base_ruleset):
				_record_current_ruleset_state()
	_refresh_ui_after_sim_state_change()
	_sync_selected_ruleset_index_from_current_state()
	_update_sim_hover_cursor_state()


func _ensure_split_variant_sims() -> void:
	var target_w := maxi(1, int(floor(float(W) / float(SPLIT_COL_COUNT))))
	var target_h := maxi(1, int(floor(float(H) / float(SPLIT_ROW_COUNT))))
	var ready := (
		split_base_sim != null
		and split_variant_sims.size() == SPLIT_VARIANT_COUNT
		and split_tile_w == target_w
		and split_tile_h == target_h
	)
	if ready:
		return
	if split_base_sim != null:
		split_base_sim.free_all()
		split_base_sim = null
	for variant in split_variant_sims:
		if variant != null:
			variant.free_all()
	split_variant_sims.clear()
	split_tile_w = target_w
	split_tile_h = target_h
	var rd := RenderingServer.get_rendering_device()
	split_base_sim = SimGPU.new()
	split_base_sim.init(rd, STEP_SHADER_PATH, split_tile_w, split_tile_h, LOCAL_X, LOCAL_Y, MAX_RADIUS, float(SCALE))
	for _i in range(SPLIT_VARIANT_COUNT):
		var variant := SimGPU.new()
		variant.init(rd, STEP_SHADER_PATH, split_tile_w, split_tile_h, LOCAL_X, LOCAL_Y, MAX_RADIUS, float(SCALE))
		split_variant_sims.append(variant)


func _split_variant_sim_at_region(region_index: int) -> SimGPU:
	if region_index <= 0:
		return split_base_sim
	var variant_index := region_index - 1
	if variant_index < 0 or variant_index >= split_variant_sims.size():
		return null
	return split_variant_sims[variant_index]


func _latest_split_parent_matches_current_parent() -> bool:
	if split_ruleset_history.is_empty():
		return false
	var latest_var: Variant = split_ruleset_history[split_ruleset_history.size() - 1]
	if typeof(latest_var) != TYPE_DICTIONARY:
		return false
	var latest: Dictionary = latest_var
	var base_var: Variant = latest.get("base", {})
	if typeof(base_var) != TYPE_DICTIONARY:
		return false
	var latest_base: Dictionary = base_var
	var current_parent := _capture_ruleset_from_sim(sim)
	if current_parent.is_empty():
		return false
	return _ruleset_signature(latest_base) == _ruleset_signature(current_parent)


func _restore_split_state_on_enter() -> bool:
	if split_ruleset_history.is_empty():
		return false
	var idx := split_ruleset_history.size() - 1
	var snap_var: Variant = split_ruleset_history[idx]
	if typeof(snap_var) != TYPE_DICTIONARY:
		return false
	var snap: Dictionary = snap_var
	if not _apply_split_snapshot(snap):
		return false
	split_ruleset_history_index = idx
	return true


func _on_split_region_clicked(region_index: int) -> void:
	if not split_mode:
		return
	if region_index < 0 or region_index >= SPLIT_REGION_COUNT:
		return
	if region_index > 0:
		var source := _split_variant_sim_at_region(region_index)
		if source == null:
			return
		var promoted := _capture_ruleset_from_sim(source)
		if promoted.is_empty():
			return
		if not _apply_ruleset_to_sim(sim, promoted):
			return
	_regenerate_split_variants_from_base()
	_refresh_ui_after_sim_state_change()
	var matched_idx := _sync_selected_ruleset_index_from_current_state()
	if matched_idx != -1:
		_restore_working_save_target(matched_idx)
		_update_modify_ruleset_name_context(true)
		if ruleset_popup.visible:
			_rebuild_ruleset_menu()
	_split_record_current_state()
	_update_button_states()


func _regenerate_split_variants_from_base() -> void:
	if not split_mode:
		return
	_ensure_split_variant_sims()
	var base_ruleset := _capture_ruleset_from_sim(sim)
	if base_ruleset.is_empty():
		return
	if split_base_sim == null:
		return
	if not _apply_ruleset_to_sim(split_base_sim, base_ruleset):
		return
	var flip_chance: float = modify_panel.get_flip_chance() if modify_panel != null else 0.015
	for variant in split_variant_sims:
		if variant == null:
			continue
		if not _apply_ruleset_to_sim(variant, base_ruleset):
			continue
		var rng := RandomNumberGenerator.new()
		rng.randomize()
		_apply_full_mutation_to_sim(variant, flip_chance, rng)
	_reseed_split_sims_shared()
	_update_split_view_textures()


func _reseed_split_sims_shared() -> void:
	if not split_mode:
		return
	if split_base_sim == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	split_shared_seed = int(rng.randi() & 0x7fffffff)
	_seed_split_sims_with_seed(split_shared_seed)


func _seed_split_sims_with_seed(seed_value: int) -> void:
	if split_base_sim == null:
		return
	split_base_sim.seed_random_with_seed_global(seed_value, 0, 0, H)
	for i in range(split_variant_sims.size()):
		var variant := split_variant_sims[i]
		if variant == null:
			continue
		var region_index := i + 1
		var col := region_index % SPLIT_COL_COUNT
		var row := int(region_index / SPLIT_COL_COUNT)
		var ox := col * split_tile_w
		var oy := row * split_tile_h
		variant.seed_random_with_seed_global(seed_value, ox, oy, H)


func _apply_full_mutation_to_sim(target_sim: SimGPU, bit_flip_chance: float, rng: RandomNumberGenerator) -> void:
	var chance := _normalize_flip_chance(bit_flip_chance)
	if chance <= 0.0:
		return
	target_sim.flip_threshold_bits(_make_index_range(0, THRESHOLD_FLOAT_COUNT), rng, chance)
	target_sim.flip_neighborhood_bits(_make_index_range(0, NEIGHBORHOOD_INT_COUNT), rng, chance)
	target_sim.flip_weight_bits(_make_index_range(0, WEIGHT_COUNT), rng, chance)
	target_sim.flip_channel_bits(_make_index_range(0, CHANNEL_FLOAT_COUNT), rng, chance)


func _capture_ruleset_from_sim(target_sim: SimGPU) -> Dictionary:
	if target_sim == null:
		return {}
	return {
		"thresholds": target_sim.get_current_thresholds().duplicate(),
		"neighborhoods": target_sim.get_current_neighborhoods().duplicate(),
		"weights": target_sim.get_current_weights().duplicate(),
		"channels": target_sim.get_current_channels().duplicate(),
		"candidate_neighborhood_counts": target_sim.get_current_candidate_neighborhood_counts().duplicate(),
		"enabled": target_sim.get_candidate_enableds().duplicate(),
		"seed_bias": target_sim.get_seed_noise_bias(),
		"blend_k": target_sim.get_blend_k(),
		"decay_rate": target_sim.get_decay_rate()
	}


func _apply_ruleset_to_sim(target_sim: SimGPU, ruleset: Dictionary) -> bool:
	if target_sim == null:
		return false
	var thr := PackedFloat32Array(ruleset.get("thresholds", PackedFloat32Array()))
	var nh := PackedInt32Array(ruleset.get("neighborhoods", PackedInt32Array()))
	var weights := PackedFloat32Array(ruleset.get("weights", PackedFloat32Array()))
	var channels := PackedFloat32Array(ruleset.get("channels", PackedFloat32Array()))
	var candidate_neighborhood_counts := PackedInt32Array(ruleset.get("candidate_neighborhood_counts", PackedInt32Array([2, 2, 2, 2])))
	var enabled := PackedInt32Array(ruleset.get("enabled", PackedInt32Array([1, 1, 1, 1])))
	var seed_bias := float(ruleset.get("seed_bias", 1.24))
	var blend_k := float(ruleset.get("blend_k", 0.5))
	var decay_rate := float(ruleset.get("decay_rate", 0.0))
	var ok := target_sim.apply_ruleset(thr, nh, weights, channels, candidate_neighborhood_counts, enabled, seed_bias, blend_k, decay_rate)
	if not ok:
		return false
	var runtime_threshold_adjust := 0.0
	var runtime_weight_adjust := 0.0
	var runtime_channel_adjust := 0.0
	if sim != null:
		runtime_threshold_adjust = sim.get_threshold_adjust()
		runtime_weight_adjust = sim.get_weight_adjust()
		runtime_channel_adjust = sim.get_channel_adjust()
	target_sim.set_threshold_adjust(runtime_threshold_adjust)
	target_sim.set_weight_adjust(runtime_weight_adjust)
	target_sim.set_channel_adjust(runtime_channel_adjust)
	return true


func _update_split_view_textures() -> void:
	if split_view == null:
		return
	split_view.clear_textures()
	if split_base_sim != null:
		split_view.set_region_texture(0, split_base_sim.get_display_texture())
	for i in range(split_variant_sims.size()):
		var variant := split_variant_sims[i]
		if variant != null:
			split_view.set_region_texture(i + 1, variant.get_display_texture())


func _split_history_clear() -> void:
	split_ruleset_history.clear()
	split_ruleset_history_index = -1
	split_shared_seed = 0


func _split_history_reset_to_current_state() -> void:
	_split_history_clear()
	_split_record_current_state()


func _split_record_current_state() -> void:
	var snap := _capture_split_snapshot()
	if snap.is_empty():
		return
	var snap_key := _split_snapshot_key(snap)
	if split_ruleset_history_index >= 0 and split_ruleset_history_index < split_ruleset_history.size():
		if _split_snapshot_key(split_ruleset_history[split_ruleset_history_index]) == snap_key:
			return

	while split_ruleset_history.size() - 1 > split_ruleset_history_index:
		split_ruleset_history.remove_at(split_ruleset_history.size() - 1)

	split_ruleset_history.append(snap)
	split_ruleset_history_index = split_ruleset_history.size() - 1

	if split_ruleset_history.size() > SPLIT_HISTORY_MAX:
		split_ruleset_history.remove_at(0)
		split_ruleset_history_index -= 1


func _split_undo() -> bool:
	if split_ruleset_history_index <= 0:
		return false
	split_ruleset_history_index -= 1
	return _apply_split_snapshot(split_ruleset_history[split_ruleset_history_index])


func _split_redo() -> bool:
	if split_ruleset_history_index < 0 or split_ruleset_history_index >= (split_ruleset_history.size() - 1):
		return false
	split_ruleset_history_index += 1
	return _apply_split_snapshot(split_ruleset_history[split_ruleset_history_index])


func _capture_split_snapshot() -> Dictionary:
	if not split_mode:
		return {}
	if split_base_sim == null:
		return {}
	if split_variant_sims.size() != SPLIT_VARIANT_COUNT:
		return {}
	var base := _capture_ruleset_from_sim(split_base_sim)
	if base.is_empty():
		return {}
	var variants: Array = []
	for variant in split_variant_sims:
		var v_ruleset := _capture_ruleset_from_sim(variant)
		if v_ruleset.is_empty():
			return {}
		variants.append(v_ruleset)
	return {
		"base": base,
		"variants": variants,
		"opened_saved_ruleset_index": opened_saved_ruleset_index,
		"save_target_ruleset_index": _current_save_target_ruleset_index(),
		"shared_seed": split_shared_seed
	}


func _apply_split_snapshot(snapshot: Dictionary) -> bool:
	if not split_mode:
		return false
	_ensure_split_variant_sims()
	if split_base_sim == null:
		return false
	var base_var: Variant = snapshot.get("base", {})
	if typeof(base_var) != TYPE_DICTIONARY:
		return false
	var base: Dictionary = base_var
	if not _apply_ruleset_to_sim(sim, base):
		return false
	if not _apply_ruleset_to_sim(split_base_sim, base):
		return false

	var variants_var: Variant = snapshot.get("variants", [])
	if typeof(variants_var) != TYPE_ARRAY:
		return false
	var variants: Array = variants_var
	if variants.size() != SPLIT_VARIANT_COUNT:
		return false
	for i in range(SPLIT_VARIANT_COUNT):
		var rs_var: Variant = variants[i]
		if typeof(rs_var) != TYPE_DICTIONARY:
			return false
		var rs: Dictionary = rs_var
		if not _apply_ruleset_to_sim(split_variant_sims[i], rs):
			return false

	var restored_opened := int(snapshot.get("opened_saved_ruleset_index", -1))
	var restored_save_target := int(snapshot.get("save_target_ruleset_index", restored_opened))
	var ruleset_count := ruleset_controller.ruleset_count() if ruleset_controller != null else 0
	if ruleset_count <= 0:
		restored_opened = -1
		restored_save_target = -1
	else:
		if restored_opened < 0 or restored_opened >= ruleset_count:
			restored_opened = -1
		if restored_save_target < 0 or restored_save_target >= ruleset_count:
			restored_save_target = restored_opened
	opened_saved_ruleset_index = restored_opened
	save_target_ruleset_index = restored_save_target
	split_shared_seed = int(snapshot.get("shared_seed", 0))
	_seed_split_sims_with_seed(split_shared_seed)
	_update_split_view_textures()
	return true


func _split_snapshot_key(snapshot: Dictionary) -> String:
	var parts := PackedStringArray()
	var base_var: Variant = snapshot.get("base", {})
	if typeof(base_var) == TYPE_DICTIONARY:
		var base: Dictionary = base_var
		parts.append(_ruleset_signature(base))
	var variants_var: Variant = snapshot.get("variants", [])
	if typeof(variants_var) == TYPE_ARRAY:
		var variants: Array = variants_var
		for rs_var in variants:
			if typeof(rs_var) == TYPE_DICTIONARY:
				var rs: Dictionary = rs_var
				parts.append(_ruleset_signature(rs))
	parts.append(str(int(snapshot.get("opened_saved_ruleset_index", -1))))
	parts.append(str(int(snapshot.get("save_target_ruleset_index", -1))))
	parts.append(str(int(snapshot.get("shared_seed", 0))))
	return "|".join(parts)


func _ruleset_signature(ruleset: Dictionary) -> String:
	var parts := PackedStringArray()
	var thr := PackedFloat32Array(ruleset.get("thresholds", PackedFloat32Array()))
	var nh := PackedInt32Array(ruleset.get("neighborhoods", PackedInt32Array()))
	var weights := PackedFloat32Array(ruleset.get("weights", PackedFloat32Array()))
	var channels := PackedFloat32Array(ruleset.get("channels", PackedFloat32Array()))
	var counts := PackedInt32Array(ruleset.get("candidate_neighborhood_counts", PackedInt32Array()))
	var enabled := PackedInt32Array(ruleset.get("enabled", PackedInt32Array()))
	var seed_bias := float(ruleset.get("seed_bias", 1.24))
	var blend_k := float(ruleset.get("blend_k", 0.5))
	var decay_rate := float(ruleset.get("decay_rate", 0.0))
	for v in thr:
		parts.append(str(int(round(v * 1000000.0))))
	for v in nh:
		parts.append(str(int(v)))
	for v in weights:
		parts.append(str(int(round(v * 1000000.0))))
	for v in channels:
		parts.append(str(int(round(v * 1000000.0))))
	for v in counts:
		parts.append(str(int(v)))
	for v in enabled:
		parts.append(str(int(v)))
	parts.append(str(int(round(seed_bias * 1000000.0))))
	parts.append(str(int(round(blend_k * 1000000.0))))
	parts.append(str(int(round(decay_rate * 1000000.0))))
	return ",".join(parts)

# ---------------- TWEEN ----------------

const PANEL_FADE_IN_SEC := 0.08
const PANEL_FADE_OUT_SEC := 0.06

func _fade_in_panel(panel: Control, tween_ref: Tween, duration := PANEL_FADE_IN_SEC) -> Tween:
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()

	panel.visible = true
	panel.move_to_front()
	panel.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_OUT)
	return tw

func _fade_out_panel(panel: Control, tween_ref: Tween, duration := PANEL_FADE_OUT_SEC) -> Tween:
	if tween_ref and tween_ref.is_valid():
		tween_ref.kill()

	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE) \
		.set_ease(Tween.EASE_IN)
	tw.finished.connect(func():
		panel.visible = false
		panel.modulate.a = 1.0
		_update_button_states()
	)
	return tw

# ---------------- HASHING RULESETS ----------------

func _sync_selected_ruleset_index_from_current_state() -> int:
	if ruleset_controller == null:
		return -1
	var idx := ruleset_controller.sync_selected_ruleset_index_from_current_state()
	_update_button_states()
	if ruleset_popup.visible:
		_rebuild_ruleset_menu()
	return idx


# ---------------- CANDIDATE TOGGLING ----------------

func _ruleset_name_exists(rs_name: String) -> bool:
	return ruleset_controller != null and ruleset_controller.ruleset_name_exists(rs_name)

func _current_save_target_ruleset_index() -> int:
	if ruleset_controller == null:
		return -1
	var count := ruleset_controller.ruleset_count()
	if save_target_ruleset_index >= 0 and save_target_ruleset_index < count:
		return save_target_ruleset_index
	if opened_saved_ruleset_index >= 0 and opened_saved_ruleset_index < count:
		return opened_saved_ruleset_index
	return -1

func _update_modify_ruleset_name_context(force_text := false) -> void:
	if modify_panel == null or ruleset_controller == null:
		return
	var idx := _current_save_target_ruleset_index()
	var count := ruleset_controller.ruleset_count()
	if idx < 0 or idx >= count:
		modify_panel.set_ruleset_name_context(-1, "", true)
		return
	var ruleset_name := ruleset_controller.get_ruleset_name(idx)
	modify_panel.set_ruleset_name_context(idx, ruleset_name, force_text)

func _restore_working_save_target(previous_target: int) -> void:
	if ruleset_controller == null:
		return
	var count := ruleset_controller.ruleset_count()
	if previous_target >= 0 and previous_target < count:
		save_target_ruleset_index = previous_target
		opened_saved_ruleset_index = previous_target
	else:
		save_target_ruleset_index = -1
		opened_saved_ruleset_index = -1

func _can_save_over_original_ruleset() -> bool:
	var idx := _current_save_target_ruleset_index()
	if ruleset_controller == null:
		return false
	if idx < 0 or idx >= ruleset_controller.ruleset_count():
		return false
	if _has_pending_ruleset_name_change():
		return true
	return ruleset_controller.can_save_over_original_ruleset(idx)

func _resolve_ruleset_name_for_save(raw_name: String, exclude_index: int = -1) -> String:
	var trimmed := raw_name.strip_edges()
	if not trimmed.is_empty():
		return trimmed
	return _next_available_unnamed_ruleset_name(exclude_index)

func _next_available_unnamed_ruleset_name(exclude_index: int = -1) -> String:
	var i := 1
	while true:
		var candidate := "unnamed-%d" % i
		var exists := false
		if ruleset_controller != null:
			if exclude_index >= 0:
				exists = ruleset_controller.ruleset_name_exists_except(candidate, exclude_index)
			else:
				exists = ruleset_controller.ruleset_name_exists(candidate)
		if not exists:
			return candidate
		i += 1
	return "unnamed-1"

func _has_pending_ruleset_name_change() -> bool:
	if ruleset_controller == null or modify_panel == null:
		return false
	var idx := _current_save_target_ruleset_index()
	var count := ruleset_controller.ruleset_count()
	if idx < 0 or idx >= count:
		return false
	var current_name := ruleset_controller.get_ruleset_name(idx).strip_edges()
	var requested_name := _resolve_ruleset_name_for_save(modify_panel.get_ruleset_name_input_text(), idx)
	return requested_name != current_name

func _history_reset_to_current_state() -> void:
	if split_mode:
		_split_history_reset_to_current_state()
		_update_button_states()
		return
	if history_controller == null:
		return
	history_controller.reset_ruleset_history(_current_save_target_ruleset_index())
	_update_button_states()

func _record_current_ruleset_state() -> void:
	if split_mode:
		_split_record_current_state()
		_update_button_states()
		return
	if history_controller == null:
		return
	history_controller.record_current_ruleset_state(_current_save_target_ruleset_index())
	_update_button_states()

func _retarget_current_ruleset_state_to_current_save_target() -> void:
	var save_target := _current_save_target_ruleset_index()
	if split_mode:
		_split_retarget_current_state(save_target, opened_saved_ruleset_index)
		_update_button_states()
		return
	if history_controller == null:
		return
	if not history_controller.retarget_current_ruleset_history(save_target):
		history_controller.record_current_ruleset_state(save_target)
	_update_button_states()

func _split_retarget_current_state(save_target: int, opened_saved: int) -> void:
	if split_ruleset_history.is_empty():
		_split_record_current_state()
		return
	if split_ruleset_history_index < 0 or split_ruleset_history_index >= split_ruleset_history.size():
		split_ruleset_history_index = split_ruleset_history.size() - 1
		if split_ruleset_history_index < 0:
			_split_record_current_state()
			return

	while split_ruleset_history.size() - 1 > split_ruleset_history_index:
		split_ruleset_history.remove_at(split_ruleset_history.size() - 1)

	var snap_var: Variant = split_ruleset_history[split_ruleset_history_index]
	if typeof(snap_var) != TYPE_DICTIONARY:
		_split_record_current_state()
		return
	var snap: Dictionary = snap_var
	snap["opened_saved_ruleset_index"] = opened_saved
	snap["save_target_ruleset_index"] = save_target
	split_ruleset_history[split_ruleset_history_index] = snap

	if split_ruleset_history_index > 0:
		var prev_var: Variant = split_ruleset_history[split_ruleset_history_index - 1]
		if typeof(prev_var) == TYPE_DICTIONARY:
			var prev: Dictionary = prev_var
			if _split_snapshot_key(prev) == _split_snapshot_key(snap):
				split_ruleset_history.remove_at(split_ruleset_history_index)
				split_ruleset_history_index -= 1

func _can_undo() -> bool:
	if split_mode:
		return split_ruleset_history_index > 0
	return history_controller != null and history_controller.can_undo()

func _can_redo() -> bool:
	if split_mode:
		return split_ruleset_history_index >= 0 and split_ruleset_history_index < (split_ruleset_history.size() - 1)
	return history_controller != null and history_controller.can_redo()

func _normalize_flip_chance(flip_chance: float) -> float:
	return clampf(flip_chance, 0.001, 0.05)

func _random_non_identity_rgb_permutation(rng: RandomNumberGenerator) -> PackedInt32Array:
	match int(rng.randi_range(0, 4)):
		0:
			return PackedInt32Array([0, 2, 1])
		1:
			return PackedInt32Array([1, 0, 2])
		2:
			return PackedInt32Array([1, 2, 0])
		3:
			return PackedInt32Array([2, 0, 1])
		_:
			return PackedInt32Array([2, 1, 0])

func _apply_rgb_permutation_to_all_channel_triplets(channels: PackedFloat32Array, permutation: PackedInt32Array) -> PackedFloat32Array:
	var out := channels.duplicate()
	if out.size() != CHANNEL_FLOAT_COUNT or permutation.size() != CHANNEL_TRIPLET_SIZE:
		return out
	for i in range(CHANNEL_TRIPLET_SIZE):
		var p := int(permutation[i])
		if p < 0 or p >= CHANNEL_TRIPLET_SIZE:
			return out
	for base in range(0, CHANNEL_FLOAT_COUNT, CHANNEL_TRIPLET_SIZE):
		out[base + 0] = channels[base + int(permutation[0])]
		out[base + 1] = channels[base + int(permutation[1])]
		out[base + 2] = channels[base + int(permutation[2])]
	return out

func _apply_rgb_shuffle_to_sim(target_sim: SimGPU, permutation: PackedInt32Array) -> bool:
	if target_sim == null:
		return false
	var channels := target_sim.get_current_channels()
	if channels.size() != CHANNEL_FLOAT_COUNT:
		return false
	var shuffled_channels := _apply_rgb_permutation_to_all_channel_triplets(channels, permutation)
	return target_sim.set_channels(shuffled_channels)

func _make_index_range(start: int, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if count <= 0:
		return out
	out.resize(count)
	for i in range(count):
		out[i] = start + i
	return out

func _candidate_neighborhood_start(candidate_index: int, counts: PackedInt32Array) -> int:
	var start := 0
	for i in range(candidate_index):
		start += int(counts[i])
	return start

func _candidate_neighborhood_range(candidate_index: int, counts: PackedInt32Array) -> Vector2i:
	var nh_start := _candidate_neighborhood_start(candidate_index, counts)
	var nh_count := int(counts[candidate_index])
	return Vector2i(nh_start, nh_count)

func _candidate_threshold_range(candidate_index: int, counts: PackedInt32Array) -> Vector2i:
	var nh_start := _candidate_neighborhood_start(candidate_index, counts)
	var thr_count := int(counts[candidate_index]) * 4
	return Vector2i(nh_start * 4, thr_count)

func _candidate_weight_range(candidate_index: int, counts: PackedInt32Array) -> Vector2i:
	var nh_start := _candidate_neighborhood_start(candidate_index, counts)
	var w_count := int(counts[candidate_index]) * 2
	return Vector2i(nh_start * 2, w_count)

func _candidate_channel_range(candidate_index: int, counts: PackedInt32Array) -> Vector2i:
	var nh_start := _candidate_neighborhood_start(candidate_index, counts)
	var ch_count := int(counts[candidate_index]) * 2 * 6
	return Vector2i(nh_start * 2 * 6, ch_count)

# ---------------- INPUT / BRUSH (still in main) ----------------

func _input(event: InputEvent) -> void:
	if midi_controller != null and midi_controller.handle_input(event):
		accept_event()
		return
	if input_controller == null:
		return
	input_controller.handle_input(event)


func _open_midi_inputs_deferred() -> void:
	if midi_controller == null:
		return
	midi_controller.open_inputs()
	var midi_devices: PackedStringArray = midi_controller.get_connected_devices()
	if midi_devices.is_empty():
		print("MIDI: no input devices detected.")
	else:
		print("MIDI inputs: ", midi_devices)


func _on_midi_seed_bias_changed(value: float) -> void:
	var v := clampf(value, 0.5, 2.5)
	sim.set_seed_noise_bias(v)
	if modify_panel != null:
		modify_panel.seed_bias_slider.set_value_no_signal(v)
		modify_panel.seed_bias_value.text = "%.2f" % v
	if split_base_sim != null:
		split_base_sim.set_seed_noise_bias(v)
	for variant in split_variant_sims:
		if variant != null:
			variant.set_seed_noise_bias(v)
	_sync_selected_ruleset_index_from_current_state()


func _on_midi_blend_changed(value: float) -> void:
	var v := snappedf(clampf(value, 0.0, 1.0), 0.01)
	sim.set_blend_k(v)
	if modify_panel != null:
		modify_panel.blend_slider.set_value_no_signal(v)
		modify_panel.blend_value.text = "%.2f" % v
	if split_base_sim != null:
		split_base_sim.set_blend_k(v)
	for variant in split_variant_sims:
		if variant != null:
			variant.set_blend_k(v)
	_sync_selected_ruleset_index_from_current_state()


func _on_midi_threshold_adjust_changed(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	_queue_midi_threshold_adjust(v)

func _on_midi_weight_adjust_changed(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	_queue_midi_weight_adjust(v)

func _on_midi_channel_adjust_changed(value: float) -> void:
	var v := clampf(value, 0.0, 1.0)
	_queue_midi_channel_adjust(v)


func _on_midi_decay_changed(value: float) -> void:
	var v := clampf(value, 0.0, 0.010)
	sim.set_decay_rate(v)
	if modify_panel != null:
		modify_panel.decay_slider.set_value_no_signal(v)
		modify_panel.decay_value.text = "%.3f" % v
	if split_base_sim != null:
		split_base_sim.set_decay_rate(v)
	for variant in split_variant_sims:
		if variant != null:
			variant.set_decay_rate(v)
	_sync_selected_ruleset_index_from_current_state()


func _toggle_pause() -> void:
	sim_paused = not sim_paused


func _set_brush_active_from_input(active: bool, mode: int) -> void:
	sim.set_brush_active(active, mode)


func _adjust_brush_radius_from_input(delta: float) -> void:
	sim.adjust_brush_radius(delta)


func _set_brush_center_from_input(x: int, y: int) -> void:
	sim.set_brush_center(x, y)

func _stamp_brush_once_from_input(x: int, y: int, mode: int) -> void:
	sim.stamp_brush_once(mode, x, y)

func _toggle_ui_chrome_visibility() -> void:
	if ui_root == null:
		return
	if not ui_chrome_hidden:
		_ui_child_visibility_before_hide.clear()
		for child_v in ui_root.get_children():
			var child := child_v as CanvasItem
			if child == null:
				continue
			if child == split_view:
				continue
			_ui_child_visibility_before_hide[child.get_instance_id()] = child.visible
			child.visible = false
		ui_chrome_hidden = true
	else:
		for child_v in ui_root.get_children():
			var child := child_v as CanvasItem
			if child == null:
				continue
			if child == split_view:
				continue
			var key := child.get_instance_id()
			if _ui_child_visibility_before_hide.has(key):
				child.visible = bool(_ui_child_visibility_before_hide[key])
			else:
				child.visible = true
		_ui_child_visibility_before_hide.clear()
		ui_chrome_hidden = false

func _update_fps_label() -> void:
	if fps_label == null:
		return
	var fps := int(round(Engine.get_frames_per_second()))
	var text := "FPS: %03d" % fps
	fps_label.text = text
	fps_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var sz := fps_label.get_combined_minimum_size()
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = fps_label.size
	var left := FPS_LABEL_MARGIN_X
	var top := size.y - FPS_LABEL_MARGIN_Y - sz.y
	fps_label.offset_left = left
	fps_label.offset_top = top
	fps_label.offset_right = left + sz.x
	fps_label.offset_bottom = top + sz.y

func _layout_save_panel_centered() -> void:
	if save_panel == null:
		return
	save_panel.set_anchors_preset(Control.PRESET_CENTER)
	var sz := save_panel.custom_minimum_size
	if sz.x <= 0.0 or sz.y <= 0.0:
		sz = save_panel.size
	sz.y = maxf(sz.y, 225.0)
	save_panel.offset_left = -sz.x * 0.5
	save_panel.offset_top = -sz.y * 0.5
	save_panel.offset_right = sz.x * 0.5
	save_panel.offset_bottom = sz.y * 0.5

func _layout_top_bars() -> void:
	if top_bar != null:
		top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
		top_bar.offset_left = 0.0
		top_bar.offset_top = 0.0
		top_bar.offset_right = 0.0

func _disable_button_keyboard_focus(root: Node) -> void:
	if root == null:
		return
	if root is BaseButton:
		var btn := root as BaseButton
		btn.focus_mode = Control.FOCUS_NONE
	for child_v in root.get_children():
		var child_node := child_v as Node
		if child_node != null:
			_disable_button_keyboard_focus(child_node)


func _apply_line_edit_font(root: Node) -> void:
	if root == null:
		return
	var line_edit := root as LineEdit
	if line_edit != null:
		if line_edit != name_edit:
			line_edit.add_theme_font_override("font", line_edit_font)
			if line_edit_normal_style != null:
				line_edit.add_theme_stylebox_override("normal", line_edit_normal_style.duplicate())
		_apply_line_edit_focus_style(line_edit)
	for child_v in root.get_children():
		var child_node := child_v as Node
		if child_node != null:
			_apply_line_edit_font(child_node)

func _apply_line_edit_focus_style(line_edit: LineEdit) -> void:
	if line_edit == null:
		return
	var normal_style := line_edit.get_theme_stylebox("normal")
	if normal_style != null:
		line_edit.add_theme_stylebox_override("focus", normal_style.duplicate(true))

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
