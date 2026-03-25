# res://scripts/RulesetStore.gd
class_name DiskStore
extends RefCounted

var rulesets: Array = []
var file_path: String = "user://rulesets.json"
var default_file_path: String = "res://defaults/rulesets.json"
var recently_deleted_rulesets: Array = []
var recently_deleted_file_path: String = "user://recently_deleted_rulesets.json"
const NEIGHBORHOODS_FORMAT_RING_MASK := "ring_mask_u12_v1"
const CHANNELS_FORMAT_RAW_TRIPLET := "raw_triplet_nonnegative_v1"
const RECENTLY_DELETED_MAX := 256

func load_from_disk() -> void:
	if FileAccess.file_exists(file_path):
		rulesets = _load_rulesets_array_from_path(file_path)
	else:
		rulesets = _load_rulesets_array_from_path(default_file_path)
		# Bootstrap a writable copy on first launch.
		save_to_disk()
	_load_recently_deleted_from_disk()


func _load_rulesets_array_from_path(path: String) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Failed to open rulesets file for reading: " + path)
		return []
	var text := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(text)
	if typeof(data) == TYPE_ARRAY:
		return data
	push_error("Rulesets JSON is not an array: " + path)
	return []


func save_to_disk() -> void:
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open rulesets file for writing: " + file_path)
		return
	f.store_string(JSON.stringify(rulesets, "\t"))
	f.close()


func add_ruleset(
	name: String,
	thresholds: PackedFloat32Array,
	neighborhoods: PackedInt32Array,
	weights: PackedFloat32Array,
	channels: PackedFloat32Array,
	candidate_neighborhood_counts: PackedInt32Array,
	disabled_candidates: PackedInt32Array,
	seed_bias: float,
	blend_k: float,
	decay_rate: float
) -> void:
	var rs := {
		"name": name,
		"thresholds": Array(thresholds),
		"neighborhoods": Array(neighborhoods),
		"neighborhoods_format": NEIGHBORHOODS_FORMAT_RING_MASK,
		"weights": Array(weights),
		"channels": Array(channels),
		"channels_format": CHANNELS_FORMAT_RAW_TRIPLET,
		"candidate_neighborhood_counts": Array(candidate_neighborhood_counts),
		"disabled_candidates": Array(disabled_candidates),
		"seed_bias": seed_bias,
		"blend_k": blend_k,
		"decay_rate": decay_rate,
		"favorite": false
	}
	rulesets.append(rs)

func update_ruleset(
	index: int,
	thresholds: PackedFloat32Array,
	neighborhoods: PackedInt32Array,
	weights: PackedFloat32Array,
	channels: PackedFloat32Array,
	candidate_neighborhood_counts: PackedInt32Array,
	disabled_candidates: PackedInt32Array,
	seed_bias: float,
	blend_k: float,
	decay_rate: float
) -> void:
	if index < 0 or index >= rulesets.size():
		return
	var rs_var: Variant = rulesets[index]
	if typeof(rs_var) != TYPE_DICTIONARY:
		return
	var rs: Dictionary = rs_var
	rs["thresholds"] = Array(thresholds)
	rs["neighborhoods"] = Array(neighborhoods)
	rs["neighborhoods_format"] = NEIGHBORHOODS_FORMAT_RING_MASK
	rs["weights"] = Array(weights)
	rs["channels"] = Array(channels)
	rs["channels_format"] = CHANNELS_FORMAT_RAW_TRIPLET
	rs["candidate_neighborhood_counts"] = Array(candidate_neighborhood_counts)
	rs["disabled_candidates"] = Array(disabled_candidates)
	rs["seed_bias"] = seed_bias
	rs["blend_k"] = blend_k
	rs["decay_rate"] = decay_rate
	rulesets[index] = rs


func remove_ruleset(index: int) -> void:
	if index < 0 or index >= rulesets.size():
		return
	var removed_var: Variant = rulesets[index]
	if typeof(removed_var) == TYPE_DICTIONARY:
		var removed_ruleset: Dictionary = removed_var
		removed_ruleset = removed_ruleset.duplicate(true)
		_append_recently_deleted(index, removed_ruleset)
	rulesets.remove_at(index)


func _load_recently_deleted_from_disk() -> void:
	if not FileAccess.file_exists(recently_deleted_file_path):
		recently_deleted_rulesets = []
		_save_recently_deleted_to_disk()
		return
	var f := FileAccess.open(recently_deleted_file_path, FileAccess.READ)
	if f == null:
		recently_deleted_rulesets = []
		return
	var text := f.get_as_text()
	f.close()
	var data = JSON.parse_string(text)
	recently_deleted_rulesets = data if typeof(data) == TYPE_ARRAY else []
	_trim_recently_deleted_to_max()


func _save_recently_deleted_to_disk() -> void:
	var f := FileAccess.open(recently_deleted_file_path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open recently deleted rulesets file for writing: " + recently_deleted_file_path)
		return
	f.store_string(JSON.stringify(recently_deleted_rulesets, "\t"))
	f.close()


func _append_recently_deleted(source_index: int, ruleset: Dictionary) -> void:
	var entry := {
		"deleted_at_unix": int(Time.get_unix_time_from_system()),
		"source_index": source_index,
		"ruleset": ruleset
	}
	recently_deleted_rulesets.append(entry)
	_trim_recently_deleted_to_max()
	_save_recently_deleted_to_disk()


func _trim_recently_deleted_to_max() -> void:
	while recently_deleted_rulesets.size() > RECENTLY_DELETED_MAX:
		recently_deleted_rulesets.remove_at(0)
