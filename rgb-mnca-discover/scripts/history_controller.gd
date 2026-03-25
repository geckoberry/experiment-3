class_name HistoryController
extends RefCounted

var sim: SimGPU

var threshold_float_count := 32
var neighborhood_int_count := 8
var weight_count := 16
var channel_float_count := 96
var ruleset_history_max := 64
var generated_pattern_history_max := 64
const RULE_WEIGHT_COUNT := 16
const CHANNEL_VALUES_PER_RULE := 6

var ruleset_history: Array[Dictionary] = []
var ruleset_history_index := -1
var generated_pattern_history: Array[Dictionary] = []
var generated_pattern_history_index := -1
var _applying_history_state := false


func init(
	p_sim: SimGPU,
	p_threshold_float_count: int,
	p_neighborhood_int_count: int,
	p_weight_count: int,
	p_ruleset_history_max: int,
	p_generated_pattern_history_max: int
) -> void:
	sim = p_sim
	threshold_float_count = p_threshold_float_count
	neighborhood_int_count = p_neighborhood_int_count
	weight_count = p_weight_count
	ruleset_history_max = p_ruleset_history_max
	generated_pattern_history_max = p_generated_pattern_history_max


func reset_ruleset_history(save_target_ruleset_index: int = -1) -> void:
	ruleset_history.clear()
	ruleset_history_index = -1
	record_current_ruleset_state(save_target_ruleset_index)


func record_current_ruleset_state(save_target_ruleset_index: int = -1) -> bool:
	if _applying_history_state:
		return false
	var snap := _make_ruleset_snapshot(save_target_ruleset_index)
	var snap_key := _snapshot_key(snap)
	if ruleset_history_index >= 0 and ruleset_history_index < ruleset_history.size():
		if _snapshot_key(ruleset_history[ruleset_history_index]) == snap_key:
			return false

	while ruleset_history.size() - 1 > ruleset_history_index:
		ruleset_history.remove_at(ruleset_history.size() - 1)

	ruleset_history.append(snap)
	ruleset_history_index = ruleset_history.size() - 1

	if ruleset_history.size() > ruleset_history_max:
		ruleset_history.remove_at(0)
		ruleset_history_index -= 1
	return true


func can_undo() -> bool:
	return ruleset_history_index > 0


func can_redo() -> bool:
	return ruleset_history_index >= 0 and ruleset_history_index < (ruleset_history.size() - 1)


func undo() -> bool:
	if not can_undo():
		return false
	ruleset_history_index -= 1
	return _apply_history_snapshot(ruleset_history[ruleset_history_index])


func redo() -> bool:
	if not can_redo():
		return false
	ruleset_history_index += 1
	return _apply_history_snapshot(ruleset_history[ruleset_history_index])

func retarget_current_ruleset_history(save_target_ruleset_index: int) -> bool:
	if _applying_history_state:
		return false
	if ruleset_history.is_empty():
		return record_current_ruleset_state(save_target_ruleset_index)
	if ruleset_history_index < 0 or ruleset_history_index >= ruleset_history.size():
		ruleset_history_index = ruleset_history.size() - 1
		if ruleset_history_index < 0:
			return record_current_ruleset_state(save_target_ruleset_index)

	while ruleset_history.size() - 1 > ruleset_history_index:
		ruleset_history.remove_at(ruleset_history.size() - 1)

	var snap_var: Variant = ruleset_history[ruleset_history_index]
	if typeof(snap_var) != TYPE_DICTIONARY:
		return false
	var snap: Dictionary = snap_var
	snap["save_target_ruleset_index"] = save_target_ruleset_index
	ruleset_history[ruleset_history_index] = snap

	if ruleset_history_index > 0:
		var prev_var: Variant = ruleset_history[ruleset_history_index - 1]
		var curr_var: Variant = ruleset_history[ruleset_history_index]
		if typeof(prev_var) == TYPE_DICTIONARY and typeof(curr_var) == TYPE_DICTIONARY:
			var prev: Dictionary = prev_var
			var curr: Dictionary = curr_var
			if _snapshot_key(prev) == _snapshot_key(curr):
				ruleset_history.remove_at(ruleset_history_index)
				ruleset_history_index -= 1
	return true


func get_current_ruleset_history_save_target() -> int:
	if ruleset_history_index < 0 or ruleset_history_index >= ruleset_history.size():
		return -1
	var snap_var: Variant = ruleset_history[ruleset_history_index]
	if typeof(snap_var) != TYPE_DICTIONARY:
		return -1
	var snap: Dictionary = snap_var
	return int(snap.get("save_target_ruleset_index", -1))


func push_generated_pattern_snapshot(opened_saved_ruleset_index: int) -> void:
	var snap := _capture_generated_snapshot(opened_saved_ruleset_index)
	if snap.is_empty():
		return
	if generated_pattern_history.is_empty():
		generated_pattern_history.append(snap)
		generated_pattern_history_index = 0
		return

	if generated_pattern_history_index < 0 or generated_pattern_history_index >= generated_pattern_history.size():
		generated_pattern_history_index = generated_pattern_history.size() - 1

	while generated_pattern_history.size() - 1 > generated_pattern_history_index:
		generated_pattern_history.remove_at(generated_pattern_history.size() - 1)

	var current_var: Variant = generated_pattern_history[generated_pattern_history_index]
	if typeof(current_var) == TYPE_DICTIONARY:
		var current: Dictionary = current_var
		if _generated_snapshot_key(current) == _generated_snapshot_key(snap):
			generated_pattern_history[generated_pattern_history_index] = snap
			return

	generated_pattern_history.append(snap)
	generated_pattern_history_index = generated_pattern_history.size() - 1
	_trim_generated_history_to_max()


func ensure_generated_current_state(opened_saved_ruleset_index: int) -> void:
	var snap := _capture_generated_snapshot(opened_saved_ruleset_index)
	if snap.is_empty():
		return
	if generated_pattern_history.is_empty():
		generated_pattern_history.append(snap)
		generated_pattern_history_index = 0
		return

	if generated_pattern_history_index < 0 or generated_pattern_history_index >= generated_pattern_history.size():
		generated_pattern_history_index = generated_pattern_history.size() - 1

	var current_var: Variant = generated_pattern_history[generated_pattern_history_index]
	if typeof(current_var) == TYPE_DICTIONARY:
		var current: Dictionary = current_var
		if _generated_state_signature(current) == _generated_state_signature(snap):
			# Same ruleset/source context; keep cursor stable and just refresh live pixels/state.
			generated_pattern_history[generated_pattern_history_index] = snap
			return

	# Different ruleset/source context: branch timeline so Previous returns to prior generated state.
	while generated_pattern_history.size() - 1 > generated_pattern_history_index:
		generated_pattern_history.remove_at(generated_pattern_history.size() - 1)
	generated_pattern_history.append(snap)
	generated_pattern_history_index = generated_pattern_history.size() - 1
	_trim_generated_history_to_max()


func can_restore_previous_generated_pattern() -> bool:
	return generated_pattern_history_index > 0


func can_restore_next_generated_pattern() -> bool:
	return generated_pattern_history_index >= 0 and generated_pattern_history_index < (generated_pattern_history.size() - 1)


func restore_previous_generated_pattern() -> Dictionary:
	if not can_restore_previous_generated_pattern():
		return {"ok": false}
	return _restore_generated_pattern_by_index(generated_pattern_history_index - 1)


func restore_next_generated_pattern() -> Dictionary:
	if not can_restore_next_generated_pattern():
		return {"ok": false}
	return _restore_generated_pattern_by_index(generated_pattern_history_index + 1)


func _restore_generated_pattern_by_index(target_index: int) -> Dictionary:
	if target_index < 0 or target_index >= generated_pattern_history.size():
		return {"ok": false}

	var snap_var: Variant = generated_pattern_history[target_index]
	if typeof(snap_var) != TYPE_DICTIONARY:
		generated_pattern_history.remove_at(target_index)
		_normalize_generated_history_index_after_removal(target_index)
		return {"ok": false}

	var snap: Dictionary = snap_var
	if not sim.restore_state_snapshot(snap):
		generated_pattern_history.remove_at(target_index)
		_normalize_generated_history_index_after_removal(target_index)
		return {"ok": false, "failed_restore": true}

	generated_pattern_history_index = target_index
	var restored_opened := int(snap.get("opened_saved_ruleset_index", -1))
	return {"ok": true, "opened_saved_ruleset_index": restored_opened}


func _normalize_generated_history_index_after_removal(removed_index: int) -> void:
	if generated_pattern_history.is_empty():
		generated_pattern_history_index = -1
		return
	if removed_index <= generated_pattern_history_index:
		generated_pattern_history_index -= 1
	generated_pattern_history_index = clampi(generated_pattern_history_index, 0, generated_pattern_history.size() - 1)


func _trim_generated_history_to_max() -> void:
	while generated_pattern_history.size() > generated_pattern_history_max:
		generated_pattern_history.remove_at(0)
		generated_pattern_history_index -= 1
	if generated_pattern_history.is_empty():
		generated_pattern_history_index = -1
		return
	generated_pattern_history_index = clampi(generated_pattern_history_index, 0, generated_pattern_history.size() - 1)


func _capture_generated_snapshot(opened_saved_ruleset_index: int) -> Dictionary:
	var snap := sim.capture_state_snapshot()
	if snap.is_empty():
		return {}
	snap["opened_saved_ruleset_index"] = opened_saved_ruleset_index
	return snap


func _generated_snapshot_key(snapshot: Dictionary) -> String:
	var base_key := _snapshot_key(snapshot)
	var pixels := PackedByteArray(snapshot.get("pixels", PackedByteArray()))
	var opened_saved := int(snapshot.get("opened_saved_ruleset_index", -1))
	return "%s|p|%d|o|%d" % [base_key, hash(pixels), opened_saved]


func _generated_state_signature(snapshot: Dictionary) -> String:
	var base_key := _snapshot_key(snapshot)
	var opened_saved := int(snapshot.get("opened_saved_ruleset_index", -1))
	return "%s|o|%d" % [base_key, opened_saved]


func _make_ruleset_snapshot(save_target_ruleset_index: int = -1) -> Dictionary:
	return {
		"thresholds": sim.get_current_thresholds().duplicate(),
		"neighborhoods": sim.get_current_neighborhoods().duplicate(),
		"weights": sim.get_current_weights().duplicate(),
		"channels": sim.get_current_channels().duplicate(),
		"candidate_neighborhood_counts": sim.get_current_candidate_neighborhood_counts().duplicate(),
		"enabled": _normalize_candidate_enableds(sim.get_candidate_enableds()),
		"seed_bias": sim.get_seed_noise_bias(),
		"blend_k": sim.get_blend_k(),
		"decay_rate": sim.get_decay_rate(),
		"save_target_ruleset_index": save_target_ruleset_index
	}


func _snapshot_key(snapshot: Dictionary) -> String:
	var thr := PackedFloat32Array(snapshot.get("thresholds", PackedFloat32Array()))
	var nh := PackedInt32Array(snapshot.get("neighborhoods", PackedInt32Array()))
	var weights := PackedFloat32Array(snapshot.get("weights", PackedFloat32Array()))
	var channels := _normalize_rule_channels(PackedFloat32Array(snapshot.get("channels", _default_channels())))
	if channels.is_empty():
		channels = _default_channels()
	var candidate_neighborhood_counts := PackedInt32Array(snapshot.get("candidate_neighborhood_counts", PackedInt32Array([2, 2, 2, 2])))
	var enabled := _normalize_candidate_enableds(PackedInt32Array(snapshot.get("enabled", PackedInt32Array([1, 1, 1, 1]))))
	var disabled := _enabled_to_disabled_candidates(enabled)
	var seed_bias := float(snapshot.get("seed_bias", 1.24))
	var blend_k := float(snapshot.get("blend_k", 0.5))
	var decay_rate := float(snapshot.get("decay_rate", 0.0))
	var save_target := int(snapshot.get("save_target_ruleset_index", -1))
	return "%s|st|%d" % [
		_ruleset_key_from_parts(thr, nh, weights, channels, candidate_neighborhood_counts, disabled, seed_bias, blend_k, decay_rate),
		save_target
	]


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


func _normalize_candidate_enableds(mask: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array([1, 1, 1, 1])
	for i in range(min(mask.size(), 4)):
		out[i] = 1 if mask[i] != 0 else 0
	return out


func _enabled_to_disabled_candidates(enabled: PackedInt32Array) -> PackedInt32Array:
	var e := _normalize_candidate_enableds(enabled)
	var out := PackedInt32Array()
	for i in range(4):
		if e[i] == 0:
			out.append(i)
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


func _apply_history_snapshot(snapshot: Dictionary) -> bool:
	var thr := PackedFloat32Array(snapshot.get("thresholds", PackedFloat32Array()))
	var nh := PackedInt32Array(snapshot.get("neighborhoods", []))
	var weights := PackedFloat32Array(snapshot.get("weights", PackedFloat32Array()))
	var channels := PackedFloat32Array(snapshot.get("channels", _default_channels()))
	var candidate_neighborhood_counts := PackedInt32Array(snapshot.get("candidate_neighborhood_counts", PackedInt32Array([2, 2, 2, 2])))
	var enabled := _normalize_candidate_enableds(PackedInt32Array(snapshot.get("enabled", [1, 1, 1, 1])))
	var seed_bias := float(snapshot.get("seed_bias", 1.24))
	var blend_k := float(snapshot.get("blend_k", 0.5))
	var decay_rate := float(snapshot.get("decay_rate", 0.0))
	var normalized_channels := _normalize_rule_channels(channels)
	if normalized_channels.is_empty():
		normalized_channels = _default_channels()
	if thr.size() != threshold_float_count or nh.size() != neighborhood_int_count or weights.size() != weight_count or normalized_channels.is_empty() or candidate_neighborhood_counts.size() != 4:
		return false

	_applying_history_state = true
	var ok := sim.set_thresholds(thr)
	ok = ok and sim.set_neighborhoods(nh)
	ok = ok and sim.set_weights(weights)
	ok = ok and sim.set_channels(normalized_channels)
	ok = ok and sim.set_candidate_neighborhood_counts(candidate_neighborhood_counts)
	sim.set_candidate_enableds(enabled)
	sim.set_seed_noise_bias(seed_bias)
	sim.set_blend_k(blend_k)
	sim.set_decay_rate(decay_rate)
	_applying_history_state = false
	return ok
