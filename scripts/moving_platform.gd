extends AnimatableBody2D

enum Pattern { HORIZONTAL, VERTICAL, DIAGONAL, CIRCULAR }

@export var pattern: Pattern = Pattern.HORIZONTAL
@export var travel_distance := 100.0
@export var speed := 70.0
@export var diagonal_dir := Vector2(1, -1).normalized()

var start_pos := Vector2.ZERO
var center := Vector2.ZERO
var offset := 0.0
var direction := 1
var time := 0.0

func _ready() -> void:
	start_pos = position
	center = start_pos - Vector2(travel_distance, 0.0)
	_update_color()
	Palette.palette_changed.connect(_update_color)

func _update_color() -> void:
	$Sprite2D.modulate = Palette.get_color("moving_platform")

func _physics_process(raw_delta: float) -> void:
	var delta := raw_delta * Game.world_speed_scale
	match pattern:
		Pattern.HORIZONTAL:
			offset = clamp(offset + direction * speed * delta, -travel_distance, travel_distance)
			if absf(offset) >= travel_distance:
				direction *= -1
			position.x = start_pos.x + offset
		Pattern.VERTICAL:
			offset = clamp(offset + direction * speed * delta, -travel_distance, travel_distance)
			if absf(offset) >= travel_distance:
				direction *= -1
			position.y = start_pos.y + offset
		Pattern.DIAGONAL:
			offset = clamp(offset + direction * speed * delta, -travel_distance, travel_distance)
			if absf(offset) >= travel_distance:
				direction *= -1
			position = start_pos + diagonal_dir * offset
		Pattern.CIRCULAR:
			time += delta
			var angular_speed: float = speed / max(travel_distance, 1.0)
			position = center + Vector2(travel_distance, 0.0).rotated(time * angular_speed)
