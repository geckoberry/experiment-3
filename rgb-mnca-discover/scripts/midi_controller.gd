class_name MidiController
extends RefCounted

# Default mapping (can be changed here):
# CC 77 -> blend_k
# CC 78 -> linked adjust (threshold + weight + channel)
# CC 79 -> threshold_adjust
# CC 80 -> weight_adjust
# CC 81 -> channel_adjust
# CC 2 -> seed bias
# CC 3 -> decay rate
# Note 36 -> clear
# Note 37 -> reset
# Note 105 -> reset
# Note 38 -> randomize / next
# Note 39 -> previous
# Note 40 -> view switch
const CC_BLEND := 77
const CC_LINKED_ADJUST := 78
const CC_THRESHOLD_ADJUST := 79
const CC_WEIGHT_ADJUST := 80
const CC_CHANNEL_ADJUST := 81
const CC_SEED_BIAS := 2
const CC_DECAY := 3

const NOTE_CLEAR := 36
const NOTE_RESET := 37
const NOTE_RESET_ALT := 105
const NOTE_RANDOMIZE := 38
const NOTE_PREVIOUS := 39
const NOTE_VIEW_SWITCH := 40

const SEED_BIAS_MIN := 0.5
const SEED_BIAS_MAX := 2.5
const DECAY_RATE_MIN := 0.0
const DECAY_RATE_MAX := 0.010

var _opened := false
var _connected_devices := PackedStringArray()
static var _global_midi_open := false
var log_inputs := true

var on_clear: Callable
var on_reset: Callable
var on_randomize: Callable
var on_previous: Callable
var on_view_switch: Callable
var on_blend_changed: Callable
var on_threshold_adjust_changed: Callable
var on_weight_adjust_changed: Callable
var on_channel_adjust_changed: Callable
var on_seed_bias_changed: Callable
var on_decay_changed: Callable


func init(
	p_on_clear: Callable,
	p_on_reset: Callable,
	p_on_randomize: Callable,
	p_on_previous: Callable,
	p_on_view_switch: Callable,
	p_on_blend_changed: Callable,
	p_on_threshold_adjust_changed: Callable,
	p_on_weight_adjust_changed: Callable,
	p_on_channel_adjust_changed: Callable,
	p_on_seed_bias_changed: Callable,
	p_on_decay_changed: Callable
) -> void:
	on_clear = p_on_clear
	on_reset = p_on_reset
	on_randomize = p_on_randomize
	on_previous = p_on_previous
	on_view_switch = p_on_view_switch
	on_blend_changed = p_on_blend_changed
	on_threshold_adjust_changed = p_on_threshold_adjust_changed
	on_weight_adjust_changed = p_on_weight_adjust_changed
	on_channel_adjust_changed = p_on_channel_adjust_changed
	on_seed_bias_changed = p_on_seed_bias_changed
	on_decay_changed = p_on_decay_changed


func open_inputs() -> void:
	if _opened:
		return
	if _global_midi_open:
		_connected_devices = OS.get_connected_midi_inputs()
		_opened = true
		return
	OS.open_midi_inputs()
	_connected_devices = OS.get_connected_midi_inputs()
	_opened = true
	_global_midi_open = true


func close_inputs() -> void:
	if not _opened:
		return
	OS.close_midi_inputs()
	_opened = false
	_connected_devices = PackedStringArray()
	_global_midi_open = false


func get_connected_devices() -> PackedStringArray:
	return _connected_devices


func handle_input(event: InputEvent) -> bool:
	var midi: InputEventMIDI = event as InputEventMIDI
	if midi == null:
		return false
	if log_inputs:
		_print_midi_event(midi)
	_dispatch_midi(midi)
	return true


func _dispatch_midi(midi: InputEventMIDI) -> void:
	match midi.message:
		MIDI_MESSAGE_CONTROL_CHANGE:
			_dispatch_cc(midi.controller_number, midi.controller_value)
		MIDI_MESSAGE_NOTE_ON:
			if midi.velocity > 0:
				_dispatch_note_on(midi.pitch)
		MIDI_MESSAGE_NOTE_OFF:
			pass


func _dispatch_cc(controller_number: int, controller_value: int) -> void:
	var n := _norm_u7(controller_value)
	match controller_number:
		CC_BLEND:
			if on_blend_changed.is_valid():
				on_blend_changed.call(n)
		CC_LINKED_ADJUST:
			_dispatch_all_adjusts(n)
		CC_THRESHOLD_ADJUST:
			if on_threshold_adjust_changed.is_valid():
				on_threshold_adjust_changed.call(n)
		CC_WEIGHT_ADJUST:
			if on_weight_adjust_changed.is_valid():
				on_weight_adjust_changed.call(n)
		CC_CHANNEL_ADJUST:
			if on_channel_adjust_changed.is_valid():
				on_channel_adjust_changed.call(n)
		CC_SEED_BIAS:
			if on_seed_bias_changed.is_valid():
				on_seed_bias_changed.call(lerpf(SEED_BIAS_MIN, SEED_BIAS_MAX, n))
		CC_DECAY:
			if on_decay_changed.is_valid():
				on_decay_changed.call(lerpf(DECAY_RATE_MIN, DECAY_RATE_MAX, n))

func _dispatch_all_adjusts(n: float) -> void:
	if on_threshold_adjust_changed.is_valid():
		on_threshold_adjust_changed.call(n)
	if on_weight_adjust_changed.is_valid():
		on_weight_adjust_changed.call(n)
	if on_channel_adjust_changed.is_valid():
		on_channel_adjust_changed.call(n)


func _dispatch_note_on(pitch: int) -> void:
	match pitch:
		NOTE_CLEAR:
			if on_clear.is_valid():
				on_clear.call()
		NOTE_RESET:
			if on_reset.is_valid():
				on_reset.call()
		NOTE_RESET_ALT:
			if on_reset.is_valid():
				on_reset.call()
		NOTE_RANDOMIZE:
			if on_randomize.is_valid():
				on_randomize.call()
		NOTE_PREVIOUS:
			if on_previous.is_valid():
				on_previous.call()
		NOTE_VIEW_SWITCH:
			if on_view_switch.is_valid():
				on_view_switch.call()


func _norm_u7(v: int) -> float:
	return clampf(float(v) / 127.0, 0.0, 1.0)


func _print_midi_event(midi: InputEventMIDI) -> void:
	var source := _source_label(midi)
	var msg_name := _midi_message_name(int(midi.message))
	var channel := int(midi.channel)
	var details := ""
	match int(midi.message):
		MIDI_MESSAGE_CONTROL_CHANGE:
			details = "cc=%d value=%d" % [int(midi.controller_number), int(midi.controller_value)]
		MIDI_MESSAGE_NOTE_ON, MIDI_MESSAGE_NOTE_OFF:
			details = "pitch=%d velocity=%d" % [int(midi.pitch), int(midi.velocity)]
		MIDI_MESSAGE_PITCH_BEND:
			details = "pitch=%d" % int(midi.pitch)
		MIDI_MESSAGE_AFTERTOUCH:
			details = "pressure=%d" % int(midi.pressure)
		MIDI_MESSAGE_PROGRAM_CHANGE:
			details = "instrument=%d" % int(midi.instrument)
		_:
			details = "pitch=%d velocity=%d cc=%d/%d pressure=%d" % [
				int(midi.pitch),
				int(midi.velocity),
				int(midi.controller_number),
				int(midi.controller_value),
				int(midi.pressure)
			]
	print("MIDI IN | source=%s | msg=%s(%d) | ch=%d | %s" % [
		source,
		msg_name,
		int(midi.message),
		channel,
		details
	])


func _source_label(midi: InputEventMIDI) -> String:
	var device_id := int(midi.device)
	if device_id >= 0 and device_id < _connected_devices.size():
		return "%s [id=%d]" % [str(_connected_devices[device_id]), device_id]
	return "device_id=%d" % device_id


func _midi_message_name(message: int) -> String:
	match message:
		MIDI_MESSAGE_NOTE_OFF:
			return "NOTE_OFF"
		MIDI_MESSAGE_NOTE_ON:
			return "NOTE_ON"
		MIDI_MESSAGE_AFTERTOUCH:
			return "AFTERTOUCH"
		MIDI_MESSAGE_CONTROL_CHANGE:
			return "CONTROL_CHANGE"
		MIDI_MESSAGE_PROGRAM_CHANGE:
			return "PROGRAM_CHANGE"
		MIDI_MESSAGE_PITCH_BEND:
			return "PITCH_BEND"
		_:
			return "UNKNOWN"
