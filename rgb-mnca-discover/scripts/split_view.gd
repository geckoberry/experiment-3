extends Control
class_name SplitView

signal region_clicked(index: int)

const REGION_COUNT := 12
const REGION_COLS := 4
const REGION_ROWS := 3
const HOVER_TINT := Color(1, 1, 1, 0.1)
const CLEAR_TINT := Color(1, 1, 1, 0.0)
const REGION_BG := Color(0, 0, 0, 1)
const REGION_BORDER := Color(1, 1, 1, 0.12)

var _regions: Array[Panel] = []
var _textures: Array[TextureRect] = []
var _tints: Array[ColorRect] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	_build_regions()
	set_cursor_shape(Control.CURSOR_ARROW)
	_layout_regions()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout_regions()


func set_region_texture(index: int, tex: Texture2D) -> void:
	if index < 0 or index >= _textures.size():
		return
	_textures[index].texture = tex


func clear_textures() -> void:
	for tex_rect in _textures:
		tex_rect.texture = null
	for tint in _tints:
		tint.color = CLEAR_TINT


func get_region_global_rect(index: int) -> Rect2:
	if index < 0 or index >= _regions.size():
		return Rect2()
	return _regions[index].get_global_rect()


func set_cursor_shape(shape: Control.CursorShape) -> void:
	mouse_default_cursor_shape = shape
	for region in _regions:
		if region != null:
			region.mouse_default_cursor_shape = shape


func _build_regions() -> void:
	for child_v in get_children():
		var child := child_v as Node
		if child != null:
			child.queue_free()
	_regions.clear()
	_textures.clear()
	_tints.clear()

	for i in range(REGION_COUNT):
		var region := Panel.new()
		region.name = "Region%d" % i
		region.mouse_filter = Control.MOUSE_FILTER_STOP
		region.focus_mode = Control.FOCUS_NONE
		region.mouse_default_cursor_shape = Control.CURSOR_ARROW
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = REGION_BG
		panel_style.border_width_left = 1
		panel_style.border_width_top = 1
		panel_style.border_width_right = 1
		panel_style.border_width_bottom = 1
		panel_style.border_color = REGION_BORDER
		region.add_theme_stylebox_override("panel", panel_style)
		add_child(region)

		var tex := TextureRect.new()
		tex.name = "Texture"
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 0.0
		tex.offset_top = 0.0
		tex.offset_right = 0.0
		tex.offset_bottom = 0.0
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_SCALE
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		region.add_child(tex)

		var tint := ColorRect.new()
		tint.name = "Tint"
		tint.set_anchors_preset(Control.PRESET_FULL_RECT)
		tint.offset_left = 0.0
		tint.offset_top = 0.0
		tint.offset_right = 0.0
		tint.offset_bottom = 0.0
		tint.color = CLEAR_TINT
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		region.add_child(tint)

		region.gui_input.connect(_on_region_gui_input.bind(i))
		region.mouse_entered.connect(_on_region_mouse_entered.bind(i))
		region.mouse_exited.connect(_on_region_mouse_exited.bind(i))

		_regions.append(region)
		_textures.append(tex)
		_tints.append(tint)


func _layout_regions() -> void:
	if _regions.is_empty():
		return
	var cell_w := size.x / float(REGION_COLS)
	var cell_h := size.y / float(REGION_ROWS)
	for i in range(_regions.size()):
		var col := i % REGION_COLS
		var row := int(i / REGION_COLS)
		var region := _regions[i]
		region.position = Vector2(float(col) * cell_w, float(row) * cell_h)
		region.size = Vector2(cell_w, cell_h)


func _on_region_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			region_clicked.emit(index)
			accept_event()


func _on_region_mouse_entered(index: int) -> void:
	if index < 0 or index >= _tints.size():
		return
	_tints[index].color = HOVER_TINT


func _on_region_mouse_exited(index: int) -> void:
	if index < 0 or index >= _tints.size():
		return
	_tints[index].color = CLEAR_TINT
