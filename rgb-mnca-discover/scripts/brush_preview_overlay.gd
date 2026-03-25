extends Control
class_name BrushPreviewOverlay

const PREVIEW_COLOR := Color(1, 1, 1, 0.15)

var _preview_visible := false
var _preview_pos := Vector2.ZERO
var _preview_radius := 0.0


func set_preview_state(is_visible: bool, pos: Vector2, radius: float) -> void:
	var clamped_radius := maxf(0.0, radius)
	var changed := (
		_preview_visible != is_visible
		or _preview_pos != pos
		or not is_equal_approx(_preview_radius, clamped_radius)
	)
	_preview_visible = is_visible
	_preview_pos = pos
	_preview_radius = clamped_radius
	if changed:
		queue_redraw()


func _draw() -> void:
	if not _preview_visible or _preview_radius <= 0.0:
		return
	draw_circle(_preview_pos, _preview_radius, PREVIEW_COLOR)
