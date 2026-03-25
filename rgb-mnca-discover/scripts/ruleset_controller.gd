class_name RulesetController
extends RefCounted

var store: DiskStore
var sim: SimGPU

var threshold_float_count := 32
var neighborhood_int_count := 8
var weight_count := 16
var channel_float_count := 96
const RULE_WEIGHT_COUNT := 16
const CHANNEL_VALUES_PER_RULE := 6

var selected_ruleset_index := -1
var ruleset_index_by_key: Dictionary = {} # key:String -> index:int
var ruleset_name_set: Dictionary = {} # lowercase_name:String -> true


func init(
	p_store: DiskStore,
	p_sim: SimGPU,
	p_threshold_float_count: int,
	p_neighborhood_int_count: int,
	p_weight_count: int
) -> void:
	store = p_store
	sim = p_sim
	threshold_float_count = p_threshold_float_count
	neighborhood_int_count = p_neighborhood_int_count
	weight_count = p_weight_count
	rebuild_ruleset_index_map()
	sync_selected_ruleset_index_from_current_state()


func get_selected_ruleset_index() -> int:
	return selected_ruleset_index


func ruleset_count() -> int:
	if store == null:
		return 0
	return store.rulesets.size()


func rebuild_ruleset_menu(popup: RulesetPopup, disabled_ruleset_index: int = -2) -> void:
	if popup == null or store == null:
		return
	var index_to_disable := selected_ruleset_index if disabled_ruleset_index == -2 else disabled_ruleset_index
	popup.rebuild(store.rulesets, index_to_disable)


func rebuild_ruleset_index_map() -> void:
	ruleset_index_by_key.clear()
	ruleset_name_set.clear()
	if store == null:
		return

	for i in range(store.rulesets.size()):
		var key := _ruleset_key_from_saved(store.rulesets[i])
		if not ruleset_index_by_key.has(key):
			ruleset_index_by_key[key] = i

		var rs_var: Variant = store.rulesets[i]
		if typeof(rs_var) != TYPE_DICTIONARY:
			continue
		var rs: Dictionary = rs_var
		var name_lc := str(rs.get("name", "")).strip_edges().to_lower()
		if not name_lc.is_empty():
			ruleset_name_set[name_lc] = true


func sync_selected_ruleset_index_from_current_state() -> int:
	var key := _current_ruleset_key()
	selected_ruleset_index = int(ruleset_index_by_key.get(key, -1))
	return selected_ruleset_index


func ruleset_name_exists(rs_name: String) -> bool:
	var needle := rs_name.strip_edges().to_lower()
	if needle.is_empty():
		return false
	return ruleset_name_set.has(needle)


func ruleset_name_exists_except(rs_name: String, exclude_index: int) -> bool:
	if store == null:
		return false
	var needle := rs_name.strip_edges().to_lower()
	if needle.is_empty():
		return false
	for i in range(store.rulesets.size()):
		if i == exclude_index:
			continue
		var rs_var: Variant = store.rulesets[i]
		if typeof(rs_var) != TYPE_DICTIONARY:
			continue
		var rs: Dictionary = rs_var
		var name_lc := str(rs.get("name", "")).strip_edges().to_lower()
		if not name_lc.is_empty() and name_lc == needle:
			return true
	return false


func get_ruleset_name(index: int) -> String:
	if store == null:
		return ""
	if index < 0 or index >= store.rulesets.size():
		return ""
	var rs_var: Variant = store.rulesets[index]
	if typeof(rs_var) != TYPE_DICTIONARY:
		return ""
	var rs: Dictionary = rs_var
	return str(rs.get("name", ""))


func rename_ruleset(index: int, new_name: String) -> bool:
	if store == null:
		return false
	if index < 0 or index >= store.rulesets.size():
		return false
	var trimmed := new_name.strip_edges()
	if trimmed.is_empty():
		return false
	var rs_var: Variant = store.rulesets[index]
	if typeof(rs_var) != TYPE_DICTIONARY:
		return false
	var rs: Dictionary = rs_var
	rs["name"] = trimmed
	store.rulesets[index] = rs
	store.save_to_disk()
	rebuild_ruleset_index_map()
	sync_selected_ruleset_index_from_current_state()
	return true


func can_save_over_original_ruleset(opened_saved_ruleset_index: int) -> bool:
	if store == null:
		return false
	if opened_saved_ruleset_index < 0 or opened_saved_ruleset_index >= store.rulesets.size():
		return false
	# Save is only valid when current params are not already represented by any saved ruleset.
	# This prevents creating duplicate behavior snapshots under different names/indices.
	var matched_idx := sync_selected_ruleset_index_from_current_state()
	return matched_idx == -1


func apply_ruleset_by_index(id: int) -> bool:
	if store == null or sim == null:
		return false
	if id < 0 or id >= store.rulesets.size():
		return false

	var rs_var: Variant = store.rulesets[id]
	if typeof(rs_var) != TYPE_DICTIONARY:
		return false
	var rs: Dictionary = rs_var
	var thr := _thresholds_from_saved(rs)
	var nh := PackedInt32Array(rs.get("neighborhoods", []))
	var weights := _weights_from_saved(rs)
	var channels := _channels_from_saved(rs)
	var candidate_neighborhood_counts := _candidate_neighborhood_counts_from_saved(rs)
	var enabled := _disabled_candidates_to_enabled(rs.get("disabled_candidates", []))
	var seed_bias := float(rs.get("seed_bias", 1.24))
	var blend_k := float(rs.get("blend_k", 0.5))
	var decay_rate := float(rs.get("decay_rate", 0.0))

	if not sim.apply_ruleset(thr, nh, weights, channels, candidate_neighborhood_counts, enabled, seed_bias, blend_k, decay_rate):
		return false

	sync_selected_ruleset_index_from_current_state()
	return true


func save_current_as(ruleset_name: String) -> int:
	if store == null or sim == null:
		return -1
	var thr := sim.get_current_thresholds()
	var nh := sim.get_current_neighborhoods()
	var weights := sim.get_current_weights()
	var channels := sim.get_current_channels()
	var candidate_neighborhood_counts := sim.get_current_candidate_neighborhood_counts()
	var enabled := _normalize_candidate_enableds(sim.get_candidate_enableds())
	var disabled := _enabled_to_disabled_candidates(enabled)
	var seed_bias := sim.get_seed_noise_bias()
	var blend_k := sim.get_blend_k()
	var decay_rate := sim.get_decay_rate()

	if thr.size() != threshold_float_count or nh.size() != neighborhood_int_count or weights.size() != weight_count or channels.size() != channel_float_count:
		push_error("Nothing valid to save yet (thresholds/neighborhoods/weights/channels not ready).")
		return -1

	store.add_ruleset(ruleset_name, thr, nh, weights, channels, candidate_neighborhood_counts, disabled, seed_bias, blend_k, decay_rate)
	var new_idx := store.rulesets.size() - 1
	store.save_to_disk()
	rebuild_ruleset_index_map()
	sync_selected_ruleset_index_from_current_state()
	return new_idx


func update_current_into_ruleset(index: int) -> bool:
	if store == null or sim == null:
		return false
	if index < 0 or index >= store.rulesets.size():
		return false
	# Hard guard: never allow Save when behavior already exists in the library.
	if sync_selected_ruleset_index_from_current_state() != -1:
		return false

	var thr := sim.get_current_thresholds()
	var nh := sim.get_current_neighborhoods()
	var weights := sim.get_current_weights()
	var channels := sim.get_current_channels()
	var candidate_neighborhood_counts := sim.get_current_candidate_neighborhood_counts()
	var enabled := _normalize_candidate_enableds(sim.get_candidate_enableds())
	var disabled := _enabled_to_disabled_candidates(enabled)
	var seed_bias := sim.get_seed_noise_bias()
	var blend_k := sim.get_blend_k()
	var decay_rate := sim.get_decay_rate()

	if thr.size() != threshold_float_count or nh.size() != neighborhood_int_count or weights.size() != weight_count or channels.size() != channel_float_count:
		push_error("Nothing valid to save yet (thresholds/neighborhoods/weights/channels not ready).")
		return false

	store.update_ruleset(index, thr, nh, weights, channels, candidate_neighborhood_counts, disabled, seed_bias, blend_k, decay_rate)
	store.save_to_disk()
	rebuild_ruleset_index_map()
	sync_selected_ruleset_index_from_current_state()
	return true


func delete_ruleset(index: int, opened_saved_ruleset_index: int) -> int:
	if store == null:
		return opened_saved_ruleset_index
	if index < 0 or index >= store.rulesets.size():
		return opened_saved_ruleset_index

	var next_opened := opened_saved_ruleset_index
	if next_opened == index:
		next_opened = -1
	elif index < next_opened:
		next_opened -= 1

	store.remove_ruleset(index)
	store.save_to_disk()
	rebuild_ruleset_index_map()
	sync_selected_ruleset_index_from_current_state()
	return next_opened


func set_favorite(index: int, is_favorite: bool) -> bool:
	if store == null:
		return false
	if index < 0 or index >= store.rulesets.size():
		return false
	store.rulesets[index]["favorite"] = is_favorite
	store.save_to_disk()
	return true


func _ruleset_key_from_parts(
	thr: PackedFloat32Array,
	nh: PackedInt32Array,
	weights: PackedFloat32Array,
	channels: PackedFloat32Array,
	candidate_neighborhood_counts: PackedInt32Array,
	disabled_candidates: PackedInt32Array,
	seed_bias: float,
	blend_k: float,
	decay_rate: float
) -> String:
	var parts := PackedStringArray()
	parts.append("t")
	for v in thr:
		parts.append(str(int(round(v * 1000000.0))))
	parts.append("n")
	for v in nh:
		parts.append(str(v))
	parts.append("w")
	for v in weights:
		parts.append(str(int(round(v * 1000000.0))))
	parts.append("c")
	for v in channels:
		parts.append(str(int(round(v * 1000000.0))))
	parts.append("cn")
	for v in candidate_neighborhood_counts:
		parts.append(str(int(v)))
	parts.append("d")
	var d_arr: Array = Array(disabled_candidates)
	d_arr.sort()
	for v in d_arr:
		parts.append(str(int(v)))
	parts.append("s")
	parts.append(str(int(round(seed_bias * 1000000.0))))
	parts.append("b")
	parts.append(str(int(round(blend_k * 1000000.0))))
	parts.append("dr")
	parts.append(str(int(round(decay_rate * 1000000.0))))
	return "|".join(parts)


func _ruleset_key_from_saved(rs: Dictionary) -> String:
	var thr := _thresholds_from_saved(rs)
	var nh := PackedInt32Array(rs.get("neighborhoods", []))
	var weights := _weights_from_saved(rs)
	var channels := _channels_from_saved(rs)
	var candidate_neighborhood_counts := _candidate_neighborhood_counts_from_saved(rs)
	var disabled := PackedInt32Array(rs.get("disabled_candidates", []))
	var seed_bias := float(rs.get("seed_bias", 1.24))
	var blend_k := float(rs.get("blend_k", 0.5))
	var decay_rate := float(rs.get("decay_rate", 0.0))
	return _ruleset_key_from_parts(thr, nh, weights, channels, candidate_neighborhood_counts, disabled, seed_bias, blend_k, decay_rate)


func _current_ruleset_key() -> String:
	if sim == null:
		return ""
	var thr := sim.get_current_thresholds()
	var nh := sim.get_current_neighborhoods()
	var weights := sim.get_current_weights()
	var channels := sim.get_current_channels()
	var candidate_neighborhood_counts := sim.get_current_candidate_neighborhood_counts()
	var enabled := _normalize_candidate_enableds(sim.get_candidate_enableds())
	var disabled := _enabled_to_disabled_candidates(enabled)
	return _ruleset_key_from_parts(thr, nh, weights, channels, candidate_neighborhood_counts, disabled, sim.get_seed_noise_bias(), sim.get_blend_k(), sim.get_decay_rate())


func _normalize_candidate_enableds(mask: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array([1, 1, 1, 1])
	for i in range(min(mask.size(), 4)):
		out[i] = 1 if mask[i] != 0 else 0
	return out


func _disabled_candidates_to_enabled(disabled_raw: Variant) -> PackedInt32Array:
	var enabled := PackedInt32Array([1, 1, 1, 1])
	if typeof(disabled_raw) != TYPE_ARRAY and typeof(disabled_raw) != TYPE_PACKED_INT32_ARRAY:
		return enabled
	var disabled := PackedInt32Array(disabled_raw)
	for idx in disabled:
		if idx >= 0 and idx < 4:
			enabled[idx] = 0
	return enabled


func _enabled_to_disabled_candidates(enabled: PackedInt32Array) -> PackedInt32Array:
	var e := _normalize_candidate_enableds(enabled)
	var out := PackedInt32Array()
	for i in range(4):
		if e[i] == 0:
			out.append(i)
	return out


func _weights_from_saved(rs: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array(rs.get("weights", []))
	if out.size() != weight_count:
		return PackedFloat32Array()
	return out

func _default_channels() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(channel_float_count)
	for rule_i in range(RULE_WEIGHT_COUNT):
		var base := rule_i * CHANNEL_VALUES_PER_RULE
		out[base + 0] = 1.0
		out[base + 1] = 0.0
		out[base + 2] = 0.0
		out[base + 3] = 1.0
		out[base + 4] = 0.0
		out[base + 5] = 0.0
	return out

func _normalize_triplet_slice(arr: PackedFloat32Array, base: int) -> void:
	var r := _sanitize_channel_component(arr[base + 0])
	var g := _sanitize_channel_component(arr[base + 1])
	var b := _sanitize_channel_component(arr[base + 2])
	var s := r + g + b
	if s <= 1e-6:
		arr[base + 0] = 1.0
		arr[base + 1] = 0.0
		arr[base + 2] = 0.0
		return
	arr[base + 0] = r
	arr[base + 1] = g
	arr[base + 2] = b

func _sanitize_channel_component(v: float) -> float:
	if v != v:
		return 0.0
	if absf(v) > 1.0e30:
		return 0.0
	return clampf(v, 0.0, 1.0)

func _normalize_rule_channels(raw_channels: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if raw_channels.size() == channel_float_count:
		out = raw_channels.duplicate()
	else:
		return PackedFloat32Array()
	if out.size() != channel_float_count:
		return PackedFloat32Array()
	for base in range(0, out.size(), 3):
		_normalize_triplet_slice(out, base)
	return out

func _channels_from_saved(rs: Dictionary) -> PackedFloat32Array:
	var raw: Variant = rs.get("channels", _default_channels())
	var out := PackedFloat32Array()
	if typeof(raw) == TYPE_ARRAY or typeof(raw) == TYPE_PACKED_FLOAT32_ARRAY:
		out = PackedFloat32Array(raw)
	var normalized := _normalize_rule_channels(out)
	if normalized.is_empty():
		return _default_channels()
	return normalized


func _thresholds_from_saved(rs: Dictionary) -> PackedFloat32Array:
	var out := PackedFloat32Array(rs.get("thresholds", []))
	if out.size() != threshold_float_count:
		return PackedFloat32Array()
	return out


func _candidate_neighborhood_counts_from_saved(rs: Dictionary) -> PackedInt32Array:
	var raw: Variant = rs.get("candidate_neighborhood_counts", [2, 2, 2, 2])
	var out := PackedInt32Array()
	if typeof(raw) == TYPE_ARRAY or typeof(raw) == TYPE_PACKED_INT32_ARRAY:
		out = PackedInt32Array(raw)
	if out.size() != 4:
		return PackedInt32Array([2, 2, 2, 2])
	for v in out:
		if int(v) != 2:
			return PackedInt32Array([2, 2, 2, 2])
	return out
