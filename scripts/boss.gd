extends Area2D

const BULLET_SCENE := preload("res://scenes/EnemyBullet.tscn")
const MAX_HP := 6
const SHOOT_INTERVAL := 1.8
const ENGAGE_RANGE := 600.0

var hp := MAX_HP
var base_y := 0.0
var time := 0.0
var shoot_timer := SHOOT_INTERVAL

func _ready() -> void:
	base_y = position.y
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	_update_color()
	Palette.palette_changed.connect(_update_color)

func _update_color() -> void:
	$Sprite2D.modulate = Palette.get_color("enemy").darkened(0.4)

func _process(raw_delta: float) -> void:
	var delta := raw_delta * Game.world_speed_scale
	time += delta
	position.y = base_y + sin(time * 1.6) * 45.0
	var player := get_tree().get_first_node_in_group("player")
	if player and absf(player.global_position.x - global_position.x) < ENGAGE_RANGE:
		position.x += signf(player.global_position.x - global_position.x) * 35.0 * delta
		shoot_timer -= delta
		if shoot_timer <= 0.0:
			shoot_timer = SHOOT_INTERVAL
			_shoot_fan(player)

func _shoot_fan(player: Node2D) -> void:
	var dir := (player.global_position - global_position).normalized()
	for angle in [-0.3, 0.0, 0.3]:
		var bullet := BULLET_SCENE.instantiate()
		bullet.dir = dir.rotated(angle)
		bullet.global_position = global_position
		get_tree().current_scene.add_child(bullet)

func _hit(damage: int) -> void:
	hp -= damage
	Fx.burst(global_position, $Sprite2D.modulate, 8, 120.0)
	Sfx.play("kill", -14.0)
	if hp <= 0:
		Fx.burst(global_position, $Sprite2D.modulate, 30, 300.0)
		Fx.shake(9.0)
		Sfx.play("kill", -4.0)
		Game.add_kill()
		Game.add_boss_bonus()
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("bullet"):
		area.queue_free()
		_hit(1)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.has_method("has_instant_kill") and body.has_instant_kill():
			_hit(MAX_HP)
		elif body.velocity.y > 0.0 and body.global_position.y < global_position.y - 30.0:
			# Stomp only chips the boss; it takes several hits to kill.
			_hit(2)
			body.velocity.y = -420.0
			Fx.shake(5.0)
		elif body.has_method("consume_shield") and body.consume_shield():
			body.velocity.y = -300.0
		else:
			Game.die()
