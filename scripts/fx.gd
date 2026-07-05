extends Node

# Lightweight juice helpers: one-shot particle bursts and camera shake.

const SQUARE_TEXTURE := preload("res://assets/white_square.svg")

func burst(pos: Vector2, color: Color, count := 14, speed := 160.0) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.emitting = true
	p.amount = count
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.gravity = Vector2(0, 500)
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.texture = SQUARE_TEXTURE
	p.scale_amount_min = 0.15
	p.scale_amount_max = 0.35
	p.color = color
	scene.add_child(p)
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)

func shake(strength: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("add_shake"):
		player.add_shake(strength)
