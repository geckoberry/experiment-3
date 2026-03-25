# res://scripts/SimGPU.gd
class_name SimGPU
extends RefCounted

# ---- Config ----
var W: int
var H: int
var LOCAL_X: int
var LOCAL_Y: int
var MAX_RADIUS: int
var shader_path: String
var sim_scale := 2.0

# ---- GPU objects ----
var rd: RenderingDevice
var shader_rid: RID
var pipeline_rid: RID

var tex_a: RID
var tex_b: RID
var set_a_to_b: RID
var set_b_to_a: RID

var offsets_buf: RID
var ring_params_buf: RID
var thresholds_buf: RID
var neighborhoods_buf: RID
var weights_buf: RID
var neighborhood_distribution_buf: RID
var channels_buf: RID
var candidates_buf: RID
var brush_buf: RID
var blend_buf: RID
var seed_shader_rid: RID
var seed_pipeline_rid: RID
var seed_params_buf: RID
var seed_luts_buf: RID
var seed_set_a: RID
var seed_set_b: RID
var _seed_gpu_ready := false
var _seed_params_f := PackedFloat32Array()

var current_thresholds: PackedFloat32Array
var current_neighborhoods: PackedInt32Array
var current_weights: PackedFloat32Array
var current_channels := PackedFloat32Array()
var current_candidate_neighborhood_counts := PackedInt32Array([2, 2, 2, 2])
var current_threshold_words := PackedInt32Array()
var current_runtime_threshold_words := PackedInt32Array()
var current_neighborhood_words := PackedInt32Array()
var current_weight_words := PackedInt32Array()
var seed_noise_bias := 1.24
var blend_k := 0.5
var decay_rate := 0.0
var threshold_adjust := 0.0
var weight_adjust := 0.0
var channel_adjust := 0.0

var candidate_enabled_i := PackedInt32Array([1, 1, 1, 1])
var brush_i := PackedInt32Array([0, 1, 0, 0])           # active, mode(1=paint,2=erase,3=expel,4=vacuum,5=dead-shape), cx, cy
var brush_f := PackedFloat32Array([20.0, 0.6, 0.0, 0.0]) # radius, strength, flash_hue, _
var _brush_flash_rng := RandomNumberGenerator.new()
var _one_shot_brush_pending := false
var _one_shot_brush_mode := 1
var _one_shot_brush_cx := 0
var _one_shot_brush_cy := 0
var _one_shot_brush_rotation := 0.0
var _one_shot_brush_shape := 0 # 0 = rounded square, 1 = rounded triangle

# Ping-pong state
var show_a := true

# Display texture wrapper
var display_tex: Texture2DRD
var _seed_bytes := PackedByteArray()
var _lut_energy_curve := PackedFloat32Array()
var _lut_overlap_power := PackedFloat32Array()
var _lut_tonemap := PackedFloat32Array()
var _seed_luts_ready := false

const SEED_LUT_SIZE := 2048
const SEED_ENERGY_IN_MAX := 2.16
const SEED_POWER_IN_MAX := 3.0
const SEED_TONEMAP_IN_MAX := 8.0
const SEED_SHADER_PATH := "res://shaders/seed_init.glsl"
const SEED_LOCAL_X := 8
const SEED_LOCAL_Y := 8
const SEED_LAYER_COUNT := 9
const SEED_LAYERS_PER_CHANNEL := 3
const SEED_PRIMARY_SCALE_NUM := 24.0
const SEED_SECONDARY_SCALE_NUM := 12.0
const SEED_TERTIARY_SCALE_NUM := 6.0
const SEED_PARAM_FLOAT_COUNT := SEED_LAYER_COUNT * 8 + 4
const THRESHOLD_PAIR_COUNT := 16
const THRESHOLD_FLOAT_COUNT := THRESHOLD_PAIR_COUNT * 2
const RULE_WEIGHT_COUNT := 16
const NEIGHBORHOOD_INT_COUNT := 8
const CHANNEL_VALUES_PER_RULE := 6
const CHANNEL_FLOAT_COUNT := RULE_WEIGHT_COUNT * CHANNEL_VALUES_PER_RULE
const CANDIDATE_COUNT := 4
const NEIGHBORHOOD_RING_COUNT := 12
const NEIGHBORHOOD_RING_MASK := 0xFFF
const THRESHOLD_ADJUST_AMP_MIN := 0.01
const THRESHOLD_ADJUST_AMP_MAX := 0.12
const WEIGHT_ADJUST_AMP_MIN := 0.02
const WEIGHT_ADJUST_AMP_MAX := 0.52
const THRESHOLD_ADJUST_FREQ_MIN := 0.03
const THRESHOLD_ADJUST_FREQ_MAX := 0.2
const NEIGHBORHOOD_INCLUDE_PROB_MIN := 0.0
const NEIGHBORHOOD_INCLUDE_PROB_MAX := 0.7
const CHANNEL_COMPONENT_RANDOM_MIN := -0.5
const CHANNEL_COMPONENT_RANDOM_MAX := 1.0
const ENABLE_BRUSH_MODE_5 := false


func init(
	p_rd: RenderingDevice,
	p_shader_path: String,
	p_w: int,
	p_h: int,
	p_local_x: int,
	p_local_y: int,
	p_max_radius: int,
	p_scale: float = 2.0
) -> void:
	rd = p_rd
	shader_path = p_shader_path
	W = p_w
	H = p_h
	LOCAL_X = p_local_x
	LOCAL_Y = p_local_y
	MAX_RADIUS = p_max_radius
	sim_scale = maxf(0.0001, p_scale)
	_brush_flash_rng.randomize()

	_create_textures()
	_create_params()
	_create_thresholds_buffer()
	_create_neighborhoods_buffer()
	_create_weights_buffer()
	_create_neighborhood_distribution_buffer()
	_create_channels_buffer()
	_create_candidates_buffer()
	_create_blend_buffer()

	var shader_file: RDShaderFile = load(shader_path)
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader_rid = rd.shader_create_from_spirv(spirv)
	pipeline_rid = rd.compute_pipeline_create(shader_rid)

	_create_brush_buffer()
	_create_uniform_sets()
	_init_seed_gpu()

	display_tex = Texture2DRD.new()
	display_tex.texture_rd_rid = tex_a


func free_all() -> void:
	if set_a_to_b.is_valid(): rd.free_rid(set_a_to_b)
	if set_b_to_a.is_valid(): rd.free_rid(set_b_to_a)
	if offsets_buf.is_valid(): rd.free_rid(offsets_buf)
	if ring_params_buf.is_valid(): rd.free_rid(ring_params_buf)
	if thresholds_buf.is_valid(): rd.free_rid(thresholds_buf)
	if neighborhoods_buf.is_valid(): rd.free_rid(neighborhoods_buf)
	if weights_buf.is_valid(): rd.free_rid(weights_buf)
	if neighborhood_distribution_buf.is_valid(): rd.free_rid(neighborhood_distribution_buf)
	if channels_buf.is_valid(): rd.free_rid(channels_buf)
	if candidates_buf.is_valid(): rd.free_rid(candidates_buf)
	if brush_buf.is_valid(): rd.free_rid(brush_buf)
	if blend_buf.is_valid(): rd.free_rid(blend_buf)
	if seed_set_a.is_valid(): rd.free_rid(seed_set_a)
	if seed_set_b.is_valid(): rd.free_rid(seed_set_b)
	if seed_params_buf.is_valid(): rd.free_rid(seed_params_buf)
	if seed_luts_buf.is_valid(): rd.free_rid(seed_luts_buf)
	if seed_pipeline_rid.is_valid(): rd.free_rid(seed_pipeline_rid)
	if seed_shader_rid.is_valid(): rd.free_rid(seed_shader_rid)
	if tex_a.is_valid(): rd.free_rid(tex_a)
	if tex_b.is_valid(): rd.free_rid(tex_b)

	# Pipeline / shader
	if pipeline_rid.is_valid(): rd.free_rid(pipeline_rid)
	if shader_rid.is_valid(): rd.free_rid(shader_rid)


func get_display_texture() -> Texture2DRD:
	return display_tex

func capture_pixels() -> PackedByteArray:
	var src_tex := tex_a if show_a else tex_b
	if not src_tex.is_valid():
		return PackedByteArray()
	return rd.texture_get_data(src_tex, 0)

func restore_pixels(pixels: PackedByteArray) -> bool:
	var expected_bytes := W * H * 4
	if pixels.size() != expected_bytes:
		return false
	rd.texture_update(tex_a, 0, pixels)
	show_a = true
	display_tex.texture_rd_rid = tex_a
	return true

func get_width() -> int:
	return W

func get_height() -> int:
	return H


func step() -> void:
	# One compute step + swap display
	var restore_brush_after_step := false
	var prev_brush_i := PackedInt32Array()
	var prev_brush_f := PackedFloat32Array()
	if _one_shot_brush_pending:
		prev_brush_i = brush_i.duplicate()
		prev_brush_f = brush_f.duplicate()
		brush_i[0] = 1
		brush_i[1] = _one_shot_brush_mode
		brush_i[2] = _one_shot_brush_cx
		brush_i[3] = _one_shot_brush_cy
		brush_f[2] = float(_one_shot_brush_shape)
		brush_f[3] = _one_shot_brush_rotation
		_update_brush_gpu()
		_one_shot_brush_pending = false
		restore_brush_after_step = true

	_update_brush_flash_color_if_needed()
	if show_a:
		_dispatch(set_a_to_b)
		show_a = false
		display_tex.texture_rd_rid = tex_b
	else:
		_dispatch(set_b_to_a)
		show_a = true
		display_tex.texture_rd_rid = tex_a

	if restore_brush_after_step:
		brush_i = prev_brush_i
		brush_f = prev_brush_f
		_update_brush_gpu()


# ---------------- Public sim controls ----------------

func seed_random() -> void:
	_seed_random(tex_a)
	show_a = true
	display_tex.texture_rd_rid = tex_a

func seed_random_with_seed(seed_value: int) -> void:
	_seed_random(tex_a, seed_value, true)
	show_a = true
	display_tex.texture_rd_rid = tex_a

func seed_random_with_seed_global(seed_value: int, origin_x: int, origin_y: int, world_height: int) -> void:
	var origin := Vector2(float(origin_x), float(origin_y))
	var wh := float(maxi(1, world_height))
	_seed_random(tex_a, seed_value, true, origin, wh)
	show_a = true
	display_tex.texture_rd_rid = tex_a

func seed_empty() -> void:
	_seed_empty(tex_a)
	show_a = true
	display_tex.texture_rd_rid = tex_a

func reset_state() -> void:
	# Just re-seed random with existing params
	seed_random()

func randomize_params_and_reset() -> void:
	# Stop using old sets (they reference old buffers)
	if set_a_to_b.is_valid(): rd.free_rid(set_a_to_b)
	if set_b_to_a.is_valid(): rd.free_rid(set_b_to_a)

	# Free old parameter buffers
	if thresholds_buf.is_valid(): rd.free_rid(thresholds_buf)
	if neighborhoods_buf.is_valid(): rd.free_rid(neighborhoods_buf)
	if weights_buf.is_valid(): rd.free_rid(weights_buf)
	if neighborhood_distribution_buf.is_valid(): rd.free_rid(neighborhood_distribution_buf)
	if channels_buf.is_valid(): rd.free_rid(channels_buf)

	# Recreate random params
	_create_thresholds_buffer()
	_create_neighborhoods_buffer()
	_create_weights_buffer()
	_create_neighborhood_distribution_buffer()
	_create_channels_buffer()

	# Recreate sets
	_create_uniform_sets()

	# Reset sim
	seed_random()

func capture_state_snapshot() -> Dictionary:
	var src_tex := tex_a if show_a else tex_b
	if not src_tex.is_valid():
		return {}
	return {
		"pixels": rd.texture_get_data(src_tex, 0),
		"thresholds": current_thresholds.duplicate(),
		"neighborhoods": current_neighborhoods.duplicate(),
		"weights": current_weights.duplicate(),
		"channels": current_channels.duplicate(),
		"candidate_neighborhood_counts": current_candidate_neighborhood_counts.duplicate(),
		"enabled": candidate_enabled_i.duplicate(),
		"seed_bias": seed_noise_bias,
		"blend_k": blend_k,
		"decay_rate": decay_rate
	}

func restore_state_snapshot(snapshot: Dictionary) -> bool:
	var pixels := PackedByteArray(snapshot.get("pixels", PackedByteArray()))
	var thr := PackedFloat32Array(snapshot.get("thresholds", PackedFloat32Array()))
	var nh := PackedInt32Array(snapshot.get("neighborhoods", PackedInt32Array()))
	var weights := PackedFloat32Array(snapshot.get("weights", PackedFloat32Array()))
	var channels := PackedFloat32Array(snapshot.get("channels", _default_channels()))
	var candidate_neighborhood_counts := PackedInt32Array(snapshot.get("candidate_neighborhood_counts", PackedInt32Array([2, 2, 2, 2])))
	var enabled := PackedInt32Array(snapshot.get("enabled", PackedInt32Array([1, 1, 1, 1])))
	var p_seed_noise_bias := float(snapshot.get("seed_bias", 1.24))
	var p_blend_k := float(snapshot.get("blend_k", 0.5))
	var p_decay_rate := float(snapshot.get("decay_rate", 0.0))

	if pixels.is_empty():
		return false
	if channels.size() != CHANNEL_FLOAT_COUNT:
		channels = _default_channels()
	if thr.size() != THRESHOLD_FLOAT_COUNT or nh.size() != NEIGHBORHOOD_INT_COUNT or weights.size() != RULE_WEIGHT_COUNT or channels.is_empty() or candidate_neighborhood_counts.size() != CANDIDATE_COUNT:
		return false

	var ok := set_thresholds(thr)
	ok = ok and set_neighborhoods(nh)
	ok = ok and set_weights(weights)
	ok = ok and set_channels(channels)
	ok = ok and set_candidate_neighborhood_counts(candidate_neighborhood_counts)
	set_candidate_enableds(enabled)
	set_seed_noise_bias(p_seed_noise_bias)
	set_blend_k(p_blend_k)
	set_decay_rate(p_decay_rate)
	if not ok:
		return false

	rd.texture_update(tex_a, 0, pixels)
	show_a = true
	display_tex.texture_rd_rid = tex_a
	return true

func apply_ruleset(
	thr: PackedFloat32Array,
	nh: PackedInt32Array,
	weights: PackedFloat32Array = PackedFloat32Array(),
	channels: PackedFloat32Array = PackedFloat32Array(),
	candidate_neighborhood_counts: PackedInt32Array = PackedInt32Array([2, 2, 2, 2]),
	candidate_enableds: PackedInt32Array = PackedInt32Array([1, 1, 1, 1]),
	p_seed_noise_bias: float = 1.24,
	p_blend_k: float = 0.5,
	p_decay_rate: float = 0.0
	) -> bool:
	if channels.is_empty():
		channels = _default_channels()
	if thr.size() != THRESHOLD_FLOAT_COUNT or nh.size() != NEIGHBORHOOD_INT_COUNT or weights.size() != RULE_WEIGHT_COUNT or channels.is_empty() or candidate_neighborhood_counts.size() != CANDIDATE_COUNT:
		push_error("Bad ruleset format (expected thresholds=32 floats, neighborhoods=8 ints, weights=16 floats, channels=96 floats, candidate_neighborhood_counts=4 ints).")
		return false

	var ok := set_thresholds(thr)
	ok = ok and set_neighborhoods(nh)
	ok = ok and set_weights(weights)
	ok = ok and set_channels(channels)
	ok = ok and set_candidate_neighborhood_counts(candidate_neighborhood_counts)
	if not ok:
		return false
	set_candidate_enableds(candidate_enableds)
	set_seed_noise_bias(p_seed_noise_bias)
	set_blend_k(p_blend_k)
	set_decay_rate(p_decay_rate)

	seed_random()
	return true

func get_current_thresholds() -> PackedFloat32Array:
	return current_thresholds

func get_runtime_thresholds() -> PackedFloat32Array:
	var words := _build_runtime_threshold_words()
	var out := PackedFloat32Array()
	out.resize(words.size())
	for i in range(words.size()):
		out[i] = _decode_unit_word(words[i])
	return out

func get_runtime_weights() -> PackedFloat32Array:
	var words := _build_runtime_weight_words()
	var out := PackedFloat32Array()
	out.resize(words.size())
	for i in range(words.size()):
		out[i] = _decode_weight_word(words[i])
	return out

func get_runtime_channels() -> PackedFloat32Array:
	return _build_runtime_channels()

func get_current_neighborhoods() -> PackedInt32Array:
	return current_neighborhoods

func get_current_weights() -> PackedFloat32Array:
	return current_weights

func get_current_channels() -> PackedFloat32Array:
	return current_channels.duplicate()

func get_current_candidate_neighborhood_counts() -> PackedInt32Array:
	return current_candidate_neighborhood_counts.duplicate()

func set_thresholds(thr: PackedFloat32Array) -> bool:
	if thr.size() != THRESHOLD_FLOAT_COUNT:
		push_error("Bad thresholds format (expected 32 floats).")
		return false
	current_thresholds = thr.duplicate()
	current_threshold_words.resize(current_thresholds.size())
	for i in range(current_thresholds.size()):
		current_threshold_words[i] = _encode_unit_word(current_thresholds[i])
	_upload_threshold_words()
	return true

func set_neighborhoods(nh: PackedInt32Array) -> bool:
	if nh.size() != NEIGHBORHOOD_INT_COUNT:
		push_error("Bad neighborhoods format (expected 8 ints).")
		return false
	current_neighborhoods = nh.duplicate()
	current_neighborhood_words.resize(current_neighborhoods.size())
	for i in range(current_neighborhoods.size()):
		var encoded := _encode_neighborhood_word(current_neighborhoods[i])
		current_neighborhood_words[i] = encoded
		current_neighborhoods[i] = _decode_neighborhood_word(encoded)
	_upload_neighborhood_words()
	return true

func set_weights(weights: PackedFloat32Array) -> bool:
	if weights.size() != RULE_WEIGHT_COUNT:
		push_error("Bad weights format (expected 16 floats).")
		return false
	current_weights = weights.duplicate()
	current_weight_words.resize(current_weights.size())
	for i in range(current_weights.size()):
		current_weight_words[i] = _encode_weight_word(current_weights[i])
	_upload_weight_words()
	return true

func set_channels(channels: PackedFloat32Array) -> bool:
	var sanitized := _normalize_rule_channels(channels)
	if sanitized.is_empty():
		push_error("Bad channels format (expected 96 floats).")
		return false
	current_channels = sanitized
	_upload_channels()
	return true

func set_candidate_neighborhood_counts(counts: PackedInt32Array) -> bool:
	if counts.size() != CANDIDATE_COUNT:
		push_error("Bad candidate neighborhood counts format (expected 4 ints).")
		return false
	current_candidate_neighborhood_counts = _normalize_candidate_neighborhood_counts(counts)
	_update_neighborhood_distribution_gpu()
	return true

func flip_threshold_bits(indices: PackedInt32Array, rng: RandomNumberGenerator, bit_flip_chance: float) -> bool:
	if current_threshold_words.size() != THRESHOLD_FLOAT_COUNT:
		return false
	_flip_words_in_indices(current_threshold_words, indices, rng, bit_flip_chance)
	_decode_threshold_indices_into_current(indices)
	_upload_threshold_words()
	return true

func flip_neighborhood_bits(indices: PackedInt32Array, rng: RandomNumberGenerator, bit_flip_chance: float) -> bool:
	if current_neighborhood_words.size() != NEIGHBORHOOD_INT_COUNT:
		return false
	_flip_words_in_indices(current_neighborhood_words, indices, rng, bit_flip_chance)
	_decode_neighborhood_indices_into_current(indices)
	_upload_neighborhood_words()
	return true

func flip_weight_bits(indices: PackedInt32Array, rng: RandomNumberGenerator, bit_flip_chance: float) -> bool:
	if current_weight_words.size() != RULE_WEIGHT_COUNT:
		return false
	_flip_words_in_indices(current_weight_words, indices, rng, bit_flip_chance)
	_decode_weight_indices_into_current(indices)
	_upload_weight_words()
	return true

func flip_channel_bits(indices: PackedInt32Array, rng: RandomNumberGenerator, bit_flip_chance: float) -> bool:
	if current_channels.size() != CHANNEL_FLOAT_COUNT:
		return false
	var chance := clampf(bit_flip_chance, 0.0, 1.0)
	if chance <= 0.0:
		return true
	var bytes := current_channels.to_byte_array()
	if bytes.size() != CHANNEL_FLOAT_COUNT * 4:
		return false
	for idx in indices:
		if idx < 0 or idx >= CHANNEL_FLOAT_COUNT:
			continue
		var byte_base := idx * 4
		for bit in range(32):
			if rng.randf() < chance:
				var byte_i := byte_base + (bit >> 3)
				var mask := 1 << (bit & 7)
				bytes[byte_i] = int(bytes[byte_i]) ^ mask
	var mutated := bytes.to_float32_array()
	if mutated.size() != CHANNEL_FLOAT_COUNT:
		return false
	var sanitized := _normalize_rule_channels(mutated)
	if sanitized.is_empty():
		return false
	current_channels = sanitized
	_upload_channels()
	return true

func get_seed_noise_bias() -> float:
	return seed_noise_bias

func set_seed_noise_bias(v: float) -> void:
	seed_noise_bias = clampf(v, 0.5, 2.5)

func get_blend_k() -> float:
	return blend_k

func set_blend_k(v: float) -> void:
	blend_k = clampf(v, 0.0, 1.0)
	_update_blend_gpu()

func get_decay_rate() -> float:
	return decay_rate

func set_decay_rate(v: float) -> void:
	decay_rate = clampf(v, 0.0, 0.010)
	_update_blend_gpu()

func get_threshold_adjust() -> float:
	return threshold_adjust

func set_threshold_adjust(v: float) -> void:
	var clamped := clampf(v, 0.0, 1.0)
	if is_equal_approx(clamped, threshold_adjust):
		return
	threshold_adjust = clamped
	_upload_threshold_words()

func get_weight_adjust() -> float:
	return weight_adjust

func set_weight_adjust(v: float) -> void:
	var clamped := clampf(v, 0.0, 1.0)
	if is_equal_approx(clamped, weight_adjust):
		return
	weight_adjust = clamped
	_upload_weight_words()

func get_channel_adjust() -> float:
	return channel_adjust

func set_channel_adjust(v: float) -> void:
	var clamped := clampf(v, 0.0, 1.0)
	if is_equal_approx(clamped, channel_adjust):
		return
	channel_adjust = clamped
	_upload_channels()

# Brush controls
func set_brush_active(active: bool, mode: int) -> void:
	if mode == 5 and not ENABLE_BRUSH_MODE_5:
		brush_i[0] = 0
		brush_i[1] = 1
		_update_brush_gpu()
		return
	brush_i[0] = 1 if active else 0
	brush_i[1] = _sanitize_brush_mode(mode)
	if active and brush_i[1] == 1:
		brush_f[2] = _brush_flash_rng.randf()
	_update_brush_gpu()

func set_brush_center(cx: int, cy: int) -> void:
	brush_i[2] = cx
	brush_i[3] = cy
	_update_brush_gpu()

func stamp_brush_once(mode: int, cx: int, cy: int) -> void:
	if mode == 5 and not ENABLE_BRUSH_MODE_5:
		return
	var clamped_x := clampi(cx, 0, maxi(0, W - 1))
	var clamped_y := clampi(cy, 0, maxi(0, H - 1))
	_one_shot_brush_mode = _sanitize_brush_mode(mode)
	_one_shot_brush_cx = clamped_x
	_one_shot_brush_cy = clamped_y
	if _one_shot_brush_mode == 5:
		_one_shot_brush_shape = 1 if _brush_flash_rng.randf() < (1.0 / 3.0) else 0
		_one_shot_brush_rotation = _brush_flash_rng.randf_range(0.0, TAU)
	else:
		_one_shot_brush_shape = 0
		_one_shot_brush_rotation = 0.0
	_one_shot_brush_pending = true

func get_brush_radius() -> float:
	return brush_f[0]

func adjust_brush_radius(delta: float, min_r := 10.0, max_r := 168.0) -> void:
	brush_f[0] = clampf(brush_f[0] + delta, min_r, max_r)
	_update_brush_gpu()

func _update_brush_flash_color_if_needed() -> void:
	# Brush type 1 (paint) flashes through random hues while active.
	if brush_i[0] == 0:
		return
	if brush_i[1] != 1:
		return
	brush_f[2] = _brush_flash_rng.randf()
	_update_brush_gpu()

func _sanitize_brush_mode(mode: int) -> int:
	if mode == 5 and not ENABLE_BRUSH_MODE_5:
		return 1
	match mode:
		1, 2, 3, 4, 5:
			return mode
		_:
			return 1


# ---------------- GPU SETUP ----------------

func _create_textures() -> void:
	var fmt := RDTextureFormat.new()
	fmt.width = W
	fmt.height = H
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	var view := RDTextureView.new()
	tex_a = rd.texture_create(fmt, view, [])
	tex_b = rd.texture_create(fmt, view, [])


func _create_uniform_sets() -> void:
	set_a_to_b = _make_set(tex_a, tex_b)
	set_b_to_a = _make_set(tex_b, tex_a)


func _make_set(src_tex: RID, dst_tex: RID) -> RID:
	var u_src := RDUniform.new()
	u_src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_src.binding = 0
	u_src.add_id(src_tex)

	var u_dst := RDUniform.new()
	u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_dst.binding = 1
	u_dst.add_id(dst_tex)

	var u_offsets := RDUniform.new()
	u_offsets.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_offsets.binding = 2
	u_offsets.add_id(offsets_buf)

	var u_ring_params := RDUniform.new()
	u_ring_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_ring_params.binding = 3
	u_ring_params.add_id(ring_params_buf)

	var u_thr := RDUniform.new()
	u_thr.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_thr.binding = 4
	u_thr.add_id(thresholds_buf)

	var u_nh := RDUniform.new()
	u_nh.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_nh.binding = 5
	u_nh.add_id(neighborhoods_buf)

	var u_weights := RDUniform.new()
	u_weights.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_weights.binding = 9
	u_weights.add_id(weights_buf)

	var u_nh_dist := RDUniform.new()
	u_nh_dist.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_nh_dist.binding = 10
	u_nh_dist.add_id(neighborhood_distribution_buf)

	var u_channels := RDUniform.new()
	u_channels.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_channels.binding = 11
	u_channels.add_id(channels_buf)

	var u_brush := RDUniform.new()
	u_brush.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_brush.binding = 6
	u_brush.add_id(brush_buf)

	var u_candidates := RDUniform.new()
	u_candidates.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_candidates.binding = 7
	u_candidates.add_id(candidates_buf)

	var u_blend := RDUniform.new()
	u_blend.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_blend.binding = 8
	u_blend.add_id(blend_buf)

	return rd.uniform_set_create(
		[u_src, u_dst, u_offsets, u_ring_params, u_thr, u_nh, u_brush, u_candidates, u_blend, u_weights, u_nh_dist, u_channels],
		shader_rid,
		0
	)


func _dispatch(uset: RID) -> void:
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uset, 0)

	var gx := int(ceil(float(W) / float(LOCAL_X)))
	var gy := int(ceil(float(H) / float(LOCAL_Y)))
	rd.compute_list_dispatch(cl, gx, gy, 1)

	rd.compute_list_end()

func _init_seed_gpu() -> void:
	_seed_gpu_ready = false
	_ensure_seed_luts()

	var shader_file: RDShaderFile = load(SEED_SHADER_PATH)
	if shader_file == null:
		push_warning("Seed shader not found: " + SEED_SHADER_PATH)
		return
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	seed_shader_rid = rd.shader_create_from_spirv(spirv)
	if not seed_shader_rid.is_valid():
		push_warning("Failed to create seed shader RID.")
		return
	seed_pipeline_rid = rd.compute_pipeline_create(seed_shader_rid)
	if not seed_pipeline_rid.is_valid():
		push_warning("Failed to create seed compute pipeline.")
		return

	_seed_params_f.resize(SEED_PARAM_FLOAT_COUNT)
	var params_bytes := _seed_params_f.to_byte_array()
	seed_params_buf = rd.storage_buffer_create(params_bytes.size(), params_bytes)

	var lut_bytes := PackedByteArray()
	lut_bytes.append_array(_lut_energy_curve.to_byte_array())
	lut_bytes.append_array(_lut_overlap_power.to_byte_array())
	lut_bytes.append_array(_lut_tonemap.to_byte_array())
	seed_luts_buf = rd.storage_buffer_create(lut_bytes.size(), lut_bytes)

	seed_set_a = _make_seed_set(tex_a)
	seed_set_b = _make_seed_set(tex_b)
	_seed_gpu_ready = seed_set_a.is_valid() and seed_set_b.is_valid()

func _make_seed_set(dst_tex: RID) -> RID:
	if not seed_shader_rid.is_valid():
		return RID()
	var u_dst := RDUniform.new()
	u_dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_dst.binding = 0
	u_dst.add_id(dst_tex)

	var u_params := RDUniform.new()
	u_params.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_params.binding = 1
	u_params.add_id(seed_params_buf)

	var u_luts := RDUniform.new()
	u_luts.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_luts.binding = 2
	u_luts.add_id(seed_luts_buf)

	return rd.uniform_set_create([u_dst, u_params, u_luts], seed_shader_rid, 0)

func _dispatch_seed(uset: RID) -> void:
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, seed_pipeline_rid)
	rd.compute_list_bind_uniform_set(cl, uset, 0)
	var gx := int(ceil(float(W) / float(SEED_LOCAL_X)))
	var gy := int(ceil(float(H) / float(SEED_LOCAL_Y)))
	rd.compute_list_dispatch(cl, gx, gy, 1)
	rd.compute_list_end()


func _create_params() -> void:
	var bases := PackedInt32Array()
	var counts := PackedInt32Array()
	bases.resize(MAX_RADIUS)
	counts.resize(MAX_RADIUS)

	var all := PackedInt32Array() # x,y,x,y,...
	var cursor := 0

	for r in range(1, MAX_RADIUS + 1):
		var ring := _build_exact_radius_offsets(r)
		bases[r - 1] = cursor / 2
		counts[r - 1] = ring.size() / 2
		all.append_array(ring)
		cursor += ring.size()

	offsets_buf = rd.storage_buffer_create(all.size() * 4, all.to_byte_array())

	var rp := PackedInt32Array()
	rp.resize(MAX_RADIUS * 2)
	for i in range(MAX_RADIUS):
		rp[i] = bases[i]
		rp[MAX_RADIUS + i] = counts[i]

	ring_params_buf = rd.storage_buffer_create(rp.size() * 4, rp.to_byte_array())


func _build_exact_radius_offsets(r: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			var d := int(round(sqrt(float(x * x + y * y))))
			if d == r:
				out.append(x)
				out.append(y)
	return out


func _create_thresholds_buffer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var dvmd := PackedFloat32Array()
	dvmd.resize(THRESHOLD_FLOAT_COUNT)
	for pair_i in range(THRESHOLD_PAIR_COUNT):
		var lo := clampf(rng.randf_range(-0.15, 0.65), 0.0, 1.0)
		var hi := clampf(rng.randf_range(-0.15, 0.65), 0.0, 1.0)
		dvmd[pair_i * 2 + 0] = lo
		dvmd[pair_i * 2 + 1] = hi

	current_thresholds = dvmd
	current_threshold_words.resize(current_thresholds.size())
	for i in range(current_thresholds.size()):
		current_threshold_words[i] = _encode_unit_word(current_thresholds[i])
	current_runtime_threshold_words = _build_runtime_threshold_words()
	var thr_bytes := current_runtime_threshold_words.to_byte_array()
	thresholds_buf = rd.storage_buffer_create(thr_bytes.size(), thr_bytes)


func _create_neighborhoods_buffer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()

	var nh := PackedInt32Array()
	nh.resize(NEIGHBORHOOD_INT_COUNT)
	for i in range(NEIGHBORHOOD_INT_COUNT):
		var include_p := rng.randf_range(NEIGHBORHOOD_INCLUDE_PROB_MIN, NEIGHBORHOOD_INCLUDE_PROB_MAX)
		var include_p_after_one := sqrt(include_p)
		var mask := 0
		var prev_on := false
		for ring_i in range(NEIGHBORHOOD_RING_COUNT):
			var include_threshold := include_p
			if ring_i > 0 and prev_on:
				include_threshold = include_p_after_one
			var on := rng.randf() < include_threshold
			if on:
				mask |= (1 << ring_i)
			prev_on = on
		nh[i] = mask & NEIGHBORHOOD_RING_MASK

	current_neighborhoods = nh
	current_neighborhood_words.resize(current_neighborhoods.size())
	for i in range(current_neighborhoods.size()):
		current_neighborhood_words[i] = _encode_neighborhood_word(current_neighborhoods[i])
	var nh_bytes := current_neighborhood_words.to_byte_array()
	neighborhoods_buf = rd.storage_buffer_create(nh_bytes.size(), nh_bytes)

func _create_neighborhood_distribution_buffer() -> void:
	current_candidate_neighborhood_counts = PackedInt32Array([2, 2, 2, 2])
	neighborhood_distribution_buf = rd.storage_buffer_create(
		current_candidate_neighborhood_counts.to_byte_array().size(),
		current_candidate_neighborhood_counts.to_byte_array()
	)

func _create_channels_buffer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	current_channels.resize(CHANNEL_FLOAT_COUNT)
	for rule_i in range(RULE_WEIGHT_COUNT):
		var base := rule_i * CHANNEL_VALUES_PER_RULE
		var read_triplet := _random_channel_triplet(rng)
		var write_triplet := _random_channel_triplet(rng)
		current_channels[base + 0] = read_triplet.x
		current_channels[base + 1] = read_triplet.y
		current_channels[base + 2] = read_triplet.z
		current_channels[base + 3] = write_triplet.x
		current_channels[base + 4] = write_triplet.y
		current_channels[base + 5] = write_triplet.z
	var bytes := _normalized_channels_for_gpu(_build_runtime_channels()).to_byte_array()
	channels_buf = rd.storage_buffer_create(bytes.size(), bytes)

func _create_weights_buffer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var weights := PackedFloat32Array()
	weights.resize(RULE_WEIGHT_COUNT)
	var per_candidate := 4
	for c in range(4):
		var base := c * per_candidate
		for i in range(per_candidate):
			weights[base + i] = rng.randf_range(-1.75, 1.0)
	current_weights = weights
	current_weight_words.resize(current_weights.size())
	for i in range(current_weights.size()):
		current_weight_words[i] = _encode_weight_word(current_weights[i])
	var weight_bytes := _build_runtime_weight_words().to_byte_array()
	weights_buf = rd.storage_buffer_create(weight_bytes.size(), weight_bytes)

func _create_candidates_buffer() -> void:
	candidates_buf = rd.storage_buffer_create(
		candidate_enabled_i.to_byte_array().size(),
		candidate_enabled_i.to_byte_array()
	)

func _create_blend_buffer() -> void:
	var arr := PackedFloat32Array([blend_k, decay_rate, 0.0, 0.0])
	blend_buf = rd.storage_buffer_create(arr.to_byte_array().size(), arr.to_byte_array())

func _update_blend_gpu() -> void:
	if blend_buf.is_valid() == false:
		return
	var arr := PackedFloat32Array([blend_k, decay_rate, 0.0, 0.0])
	var bytes := arr.to_byte_array()
	rd.buffer_update(blend_buf, 0, bytes.size(), bytes)

func _update_candidates_gpu() -> void:
	rd.buffer_update(
		candidates_buf,
		0,
		candidate_enabled_i.to_byte_array().size(),
		candidate_enabled_i.to_byte_array()
	)

func _update_neighborhood_distribution_gpu() -> void:
	if not neighborhood_distribution_buf.is_valid():
		return
	var bytes := current_candidate_neighborhood_counts.to_byte_array()
	rd.buffer_update(neighborhood_distribution_buf, 0, bytes.size(), bytes)

func _upload_threshold_words() -> void:
	if not thresholds_buf.is_valid():
		return
	current_runtime_threshold_words = _build_runtime_threshold_words()
	var bytes := current_runtime_threshold_words.to_byte_array()
	rd.buffer_update(thresholds_buf, 0, bytes.size(), bytes)

func _upload_neighborhood_words() -> void:
	var bytes := current_neighborhood_words.to_byte_array()
	rd.buffer_update(neighborhoods_buf, 0, bytes.size(), bytes)

func _upload_weight_words() -> void:
	var bytes := _build_runtime_weight_words().to_byte_array()
	rd.buffer_update(weights_buf, 0, bytes.size(), bytes)

func _upload_channels() -> void:
	var bytes := _normalized_channels_for_gpu(_build_runtime_channels()).to_byte_array()
	rd.buffer_update(channels_buf, 0, bytes.size(), bytes)

func _flip_words_in_indices(words: PackedInt32Array, indices: PackedInt32Array, rng: RandomNumberGenerator, bit_flip_chance: float) -> void:
	var chance := clampf(bit_flip_chance, 0.0, 1.0)
	if chance <= 0.0:
		return
	for idx in indices:
		if idx < 0 or idx >= words.size():
			continue
		var u := _i32_to_u32(words[idx])
		for bit in range(32):
			if rng.randf() < chance:
				u = u ^ (1 << bit)
		words[idx] = _u32_to_i32(u)

func _decode_threshold_indices_into_current(indices: PackedInt32Array) -> void:
	if current_thresholds.size() != current_threshold_words.size():
		current_thresholds.resize(current_threshold_words.size())
	for idx in indices:
		if idx < 0 or idx >= current_threshold_words.size():
			continue
		current_thresholds[idx] = _decode_unit_word(current_threshold_words[idx])

func _build_runtime_threshold_words() -> PackedInt32Array:
	var out := PackedInt32Array()
	if current_threshold_words.is_empty():
		return out
	out.resize(current_threshold_words.size())
	var t := clampf(threshold_adjust, 0.0, 1.0)
	for i in range(current_threshold_words.size()):
		var base_word := current_threshold_words[i]
		var base_value := _decode_unit_word(base_word)
		var adjusted := base_value + _threshold_adjust_offset(i, base_word, t)
		out[i] = _encode_unit_word(adjusted)
	return out

func _threshold_adjust_offset(index: int, base_word: int, t: float) -> float:
	var seed := _i32_to_u32(base_word) ^ _i32_to_u32((index + 1) * 0x9E3779B9)
	var phase := TAU * _hash01_u32(seed ^ 0xA511E9B3)
	var amp := lerpf(THRESHOLD_ADJUST_AMP_MIN, THRESHOLD_ADJUST_AMP_MAX, _hash01_u32(seed ^ 0x63D83595))
	var freq := lerpf(THRESHOLD_ADJUST_FREQ_MIN, THRESHOLD_ADJUST_FREQ_MAX, _hash01_u32(seed ^ 0xB5297A4D))
	# Subtract the baseline phase so t=0.0 maps exactly to original threshold values.
	return amp * (sin(phase + TAU * freq * t) - sin(phase))

func _build_runtime_weight_words() -> PackedInt32Array:
	var out := PackedInt32Array()
	if current_weight_words.is_empty():
		return out
	out.resize(current_weight_words.size())
	var t := clampf(weight_adjust, 0.0, 1.0)
	for i in range(current_weight_words.size()):
		var base_word := current_weight_words[i]
		var base_value := _decode_weight_word(base_word)
		var adjusted := base_value + _weight_adjust_offset(i, base_word, t)
		out[i] = _encode_weight_word(adjusted)
	return out

func _weight_adjust_offset(index: int, base_word: int, t: float) -> float:
	var seed := _i32_to_u32(base_word) ^ _i32_to_u32((index + 1) * 0x85EBCA6B)
	var phase := TAU * _hash01_u32(seed ^ 0x6A09E667)
	var amp := lerpf(WEIGHT_ADJUST_AMP_MIN, WEIGHT_ADJUST_AMP_MAX, _hash01_u32(seed ^ 0xBB67AE85))
	var freq := lerpf(THRESHOLD_ADJUST_FREQ_MIN, THRESHOLD_ADJUST_FREQ_MAX, _hash01_u32(seed ^ 0x3C6EF372))
	return amp * (sin(phase + TAU * freq * t) - sin(phase))

func _build_runtime_channels() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if current_channels.size() != CHANNEL_FLOAT_COUNT:
		return out
	out = current_channels.duplicate()
	var t := clampf(channel_adjust, 0.0, 1.0)
	for i in range(out.size()):
		var base_value := current_channels[i]
		var adjusted := base_value + _channel_adjust_offset(i, base_value, t)
		out[i] = _sanitize_channel_component(adjusted)
	for base in range(0, out.size(), 3):
		_normalize_triplet_slice(out, base)
	return out

func _channel_adjust_offset(index: int, base_value: float, t: float) -> float:
	var quantized := int(round(clampf(base_value, 0.0, 1.0) * 255.0))
	var seed := _i32_to_u32(quantized) ^ _i32_to_u32((index + 1) * 0x27D4EB2D)
	var phase := TAU * _hash01_u32(seed ^ 0x510E527F)
	var amp := lerpf(THRESHOLD_ADJUST_AMP_MIN, THRESHOLD_ADJUST_AMP_MAX, _hash01_u32(seed ^ 0x9B05688C))
	var freq := lerpf(THRESHOLD_ADJUST_FREQ_MIN, THRESHOLD_ADJUST_FREQ_MAX, _hash01_u32(seed ^ 0x1F83D9AB))
	return amp * (sin(phase + TAU * freq * t) - sin(phase))

func _decode_neighborhood_indices_into_current(indices: PackedInt32Array) -> void:
	if current_neighborhoods.size() != current_neighborhood_words.size():
		current_neighborhoods.resize(current_neighborhood_words.size())
	for idx in indices:
		if idx < 0 or idx >= current_neighborhood_words.size():
			continue
		current_neighborhoods[idx] = _decode_neighborhood_word(current_neighborhood_words[idx])

func _decode_weight_indices_into_current(indices: PackedInt32Array) -> void:
	if current_weights.size() != current_weight_words.size():
		current_weights.resize(current_weight_words.size())
	for idx in indices:
		if idx < 0 or idx >= current_weight_words.size():
			continue
		current_weights[idx] = _decode_weight_word(current_weight_words[idx])

func _normalize_candidate_neighborhood_counts(_raw: PackedInt32Array) -> PackedInt32Array:
	return PackedInt32Array([2, 2, 2, 2])

func _encode_unit_word(v: float) -> int:
	var q := int(round(clampf(v, 0.0, 1.0) * 255.0))
	return _u32_to_i32(q & 0xFF)

func _decode_unit_word(word: int) -> float:
	return float(_i32_to_u32(word) & 0xFF) / 255.0

func _encode_neighborhood_word(v: int) -> int:
	var q := v & NEIGHBORHOOD_RING_MASK
	return _u32_to_i32(q)

func _decode_neighborhood_word(word: int) -> int:
	return int(_i32_to_u32(word) & NEIGHBORHOOD_RING_MASK)

func _encode_weight_word(v: float) -> int:
	var t := (clampf(v, -1.0, 1.0) + 1.0) * 0.5
	var q := int(round(t * 255.0))
	return _u32_to_i32(q & 0xFF)

func _decode_weight_word(word: int) -> float:
	return (float(_i32_to_u32(word) & 0xFF) / 255.0) * 2.0 - 1.0

func _default_channels() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(CHANNEL_FLOAT_COUNT)
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

func _normalize_rule_channels(raw_channels: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if raw_channels.size() == CHANNEL_FLOAT_COUNT:
		out = raw_channels.duplicate()
	else:
		return PackedFloat32Array()
	if out.size() != CHANNEL_FLOAT_COUNT:
		return PackedFloat32Array()
	for base in range(0, out.size(), 3):
		_normalize_triplet_slice(out, base)
	return out

func _normalize_triplet_slice_for_gpu(arr: PackedFloat32Array, base: int) -> void:
	var r := _sanitize_channel_component(arr[base + 0])
	var g := _sanitize_channel_component(arr[base + 1])
	var b := _sanitize_channel_component(arr[base + 2])
	var s := r + g + b
	if s <= 1e-6:
		arr[base + 0] = 1.0
		arr[base + 1] = 0.0
		arr[base + 2] = 0.0
		return
	var inv := 1.0 / s
	arr[base + 0] = r * inv
	arr[base + 1] = g * inv
	arr[base + 2] = b * inv

func _normalized_channels_for_gpu(raw_channels: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if raw_channels.size() != CHANNEL_FLOAT_COUNT:
		return out
	out = raw_channels.duplicate()
	for base in range(0, out.size(), 3):
		_normalize_triplet_slice_for_gpu(out, base)
	return out

func _random_channel_triplet(rng: RandomNumberGenerator) -> Vector3:
	var r := maxf(0.0, rng.randf_range(CHANNEL_COMPONENT_RANDOM_MIN, CHANNEL_COMPONENT_RANDOM_MAX))
	var g := maxf(0.0, rng.randf_range(CHANNEL_COMPONENT_RANDOM_MIN, CHANNEL_COMPONENT_RANDOM_MAX))
	var b := maxf(0.0, rng.randf_range(CHANNEL_COMPONENT_RANDOM_MIN, CHANNEL_COMPONENT_RANDOM_MAX))
	if r + g + b <= 1e-6:
		var pick := rng.randi_range(0, 2)
		if pick == 0:
			r = 1.0
		elif pick == 1:
			g = 1.0
		else:
			b = 1.0
	return Vector3(r, g, b)

func _sanitize_channel_component(v: float) -> float:
	if v != v:
		return 0.0
	if absf(v) > 1.0e30:
		return 0.0
	return clampf(v, 0.0, 1.0)

func _hash01_u32(v: int) -> float:
	var x := _i32_to_u32(v)
	x = _i32_to_u32((x ^ (x >> 16)) * 0x7FEB352D)
	x = _i32_to_u32((x ^ (x >> 15)) * 0x846CA68B)
	x = _i32_to_u32(x ^ (x >> 16))
	return float(x & 0x00FFFFFF) / 16777215.0

func _i32_to_u32(v: int) -> int:
	return v & 0xFFFFFFFF

func _u32_to_i32(v: int) -> int:
	var out := v & 0xFFFFFFFF
	if out >= 0x80000000:
		out -= 0x100000000
	return out

func get_candidate_enableds() -> PackedInt32Array:
	return candidate_enabled_i.duplicate()

func set_candidate_enabled(index: int, enabled: bool) -> void:
	if index < 0 or index >= 4:
		return
	candidate_enabled_i[index] = 1 if enabled else 0
	_update_candidates_gpu()

func _normalize_candidate_enableds(enabled: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array([1, 1, 1, 1])
	for i in range(min(enabled.size(), 4)):
		out[i] = 1 if enabled[i] != 0 else 0
	return out

func set_candidate_enableds(enabled: PackedInt32Array) -> void:
	candidate_enabled_i = _normalize_candidate_enableds(enabled)
	_update_candidates_gpu()

# ---------------- SEED ----------------

func _seed_random(
	tex: RID,
	seed_value: int = 0,
	use_fixed_seed: bool = false,
	world_origin: Vector2 = Vector2.ZERO,
	world_height: float = -1.0
) -> void:
	if not _seed_random_gpu(tex, seed_value, use_fixed_seed, world_origin, world_height):
		push_warning("Seed GPU path is not ready; seed_random skipped.")

func _seed_random_gpu(
	tex: RID,
	seed_value: int = 0,
	use_fixed_seed: bool = false,
	world_origin: Vector2 = Vector2.ZERO,
	world_height: float = -1.0
) -> bool:
	if not _seed_gpu_ready:
		return false
	var seed_set := RID()
	if tex == tex_a:
		seed_set = seed_set_a
	elif tex == tex_b:
		seed_set = seed_set_b
	if not seed_set.is_valid():
		return false

	var bias_gamma := clampf(seed_noise_bias, 0.5, 2.5)
	var rng := RandomNumberGenerator.new()
	if use_fixed_seed:
		rng.seed = int(seed_value & 0x7fffffff)
	else:
		rng.seed = int(Time.get_ticks_usec() & 0x7fffffff)

	if _seed_params_f.size() != SEED_PARAM_FLOAT_COUNT:
		_seed_params_f.resize(SEED_PARAM_FLOAT_COUNT)

	var seed_primary_scale := SEED_PRIMARY_SCALE_NUM / sim_scale
	var seed_secondary_scale := SEED_SECONDARY_SCALE_NUM / sim_scale
	var seed_tertiary_scale := SEED_TERTIARY_SCALE_NUM / sim_scale

	for i in range(SEED_LAYER_COUNT):
		var seed := int(rng.randi()) & 0x00ffffff
		var oct := int(rng.randi_range(4, 7))
		var lac := rng.randf_range(1.9, 2.5)
		var gain := rng.randf_range(0.45, 0.65)
		var ox := rng.randf_range(0.0, 1000.0)
		var oy := rng.randf_range(0.0, 1000.0)
		var w := rng.randf_range(0.75, 1.25)
		var layer_slot := i % SEED_LAYERS_PER_CHANNEL
		var scale := seed_primary_scale
		if layer_slot == 1:
			scale = seed_secondary_scale
		elif layer_slot == 2:
			scale = seed_tertiary_scale

		_seed_params_f[i] = float(seed)
		_seed_params_f[SEED_LAYER_COUNT + i] = float(oct)
		_seed_params_f[(SEED_LAYER_COUNT * 2) + i] = scale
		_seed_params_f[(SEED_LAYER_COUNT * 3) + i] = lac
		_seed_params_f[(SEED_LAYER_COUNT * 4) + i] = gain
		_seed_params_f[(SEED_LAYER_COUNT * 5) + i] = ox
		_seed_params_f[(SEED_LAYER_COUNT * 6) + i] = oy
		_seed_params_f[(SEED_LAYER_COUNT * 7) + i] = w

	_seed_params_f[SEED_LAYER_COUNT * 8] = bias_gamma
	_seed_params_f[(SEED_LAYER_COUNT * 8) + 1] = world_origin.x
	_seed_params_f[(SEED_LAYER_COUNT * 8) + 2] = world_origin.y
	_seed_params_f[(SEED_LAYER_COUNT * 8) + 3] = world_height

	var params_bytes := _seed_params_f.to_byte_array()
	rd.buffer_update(seed_params_buf, 0, params_bytes.size(), params_bytes)
	_dispatch_seed(seed_set)
	return true

func _ensure_seed_byte_buffer() -> void:
	var byte_count := W * H * 4
	if _seed_bytes.size() != byte_count:
		_seed_bytes.resize(byte_count)

func _ensure_seed_luts() -> void:
	if _seed_luts_ready:
		return
	_lut_energy_curve.resize(SEED_LUT_SIZE)
	_lut_overlap_power.resize(SEED_LUT_SIZE)
	_lut_tonemap.resize(SEED_LUT_SIZE)

	for i in range(SEED_LUT_SIZE):
		var t := float(i) / float(SEED_LUT_SIZE - 1)

		var e_in := t * SEED_ENERGY_IN_MAX
		_lut_energy_curve[i] = pow(e_in, 1.4)

		var p_in := t * SEED_POWER_IN_MAX
		_lut_overlap_power[i] = pow(p_in, 3.2)

		var tm_in := t * SEED_TONEMAP_IN_MAX
		_lut_tonemap[i] = 1.0 - exp(-2.8 * tm_in)

	_seed_luts_ready = true


func _seed_empty(tex: RID) -> void:
	_ensure_seed_byte_buffer()
	for i in range(0, _seed_bytes.size(), 4):
		_seed_bytes[i] = 0
		_seed_bytes[i + 1] = 0
		_seed_bytes[i + 2] = 0
		_seed_bytes[i + 3] = 255
	rd.texture_update(tex, 0, _seed_bytes)


# ---------------- BRUSH ----------------

func _create_brush_buffer() -> void:
	var bytes := PackedByteArray()
	bytes.append_array(brush_i.to_byte_array())
	bytes.append_array(brush_f.to_byte_array())
	brush_buf = rd.storage_buffer_create(bytes.size(), bytes)


func _update_brush_gpu() -> void:
	var bytes := PackedByteArray()
	bytes.append_array(brush_i.to_byte_array())
	bytes.append_array(brush_f.to_byte_array())
	rd.buffer_update(brush_buf, 0, bytes.size(), bytes)
