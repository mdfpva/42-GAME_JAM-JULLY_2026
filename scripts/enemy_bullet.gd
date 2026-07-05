extends Area2D

const SPEED := 250.0

var dir := Vector2.LEFT
var lifetime := 3.5

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	position += dir * SPEED * delta * Game.world_speed_scale
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.has_method("consume_shield") and body.consume_shield():
			queue_free()
		else:
			Game.die()
