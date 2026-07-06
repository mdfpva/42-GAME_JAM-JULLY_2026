extends Area2D

enum Type { PATROL, FLYER, CHASER, SHOOTER }

const ENEMY_BULLET_SCENE := preload("res://scenes/EnemyBullet.tscn")
const SHOOT_INTERVAL := 2.4
const SHOOT_RANGE := 700.0
const CHASE_RANGE_X := 300.0
const CHASE_RANGE_Y := 60.0 # only chase when the player is at (almost) the same level

@export var patrol_distance := 100.0
@export var speed := 80.0
@export var type: Type = Type.PATROL

var start_x := 0.0
var base_y := 0.0
var direction := 1
var time := 0.0
var shoot_timer := SHOOT_INTERVAL

func _ready() -> void:
	start_x = position.x
	base_y = position.y
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	match type:
		Type.FLYER:
			$Sprite2D.scale = Vector2(1.4, 1.4)
		Type.CHASER:
			$Sprite2D.scale = Vector2(2.1, 1.3)
		Type.SHOOTER:
			$Sprite2D.scale = Vector2(1.5, 2.1)
	_update_color()
	Palette.palette_changed.connect(_update_color)

func _update_color() -> void:
	var c := Palette.get_color("enemy")
	match type:
		Type.FLYER:
			c = c.lightened(0.35)
		Type.CHASER:
			c = c.darkened(0.3)
		Type.SHOOTER:
			c = c.darkened(0.15)
	$Sprite2D.modulate = c

func _process(raw_delta: float) -> void:
	var delta := raw_delta * Game.world_speed_scale
	time += delta
	match type:
		Type.PATROL:
			_patrol(delta, speed)
		Type.FLYER:
			_patrol(delta, speed * 0.8)
			position.y = base_y + sin(time * 2.6) * 55.0
		Type.CHASER:
			var player := get_tree().get_first_node_in_group("player")
			if player and absf(player.global_position.x - global_position.x) < CHASE_RANGE_X \
					and absf(player.global_position.y - global_position.y) < CHASE_RANGE_Y:
				position.x += signf(player.global_position.x - global_position.x) * speed * 1.9 * delta
				position.x = clampf(position.x, start_x - patrol_distance * 1.8, start_x + patrol_distance * 1.8)
			else:
				_patrol(delta, speed)
		Type.SHOOTER:
			_patrol(delta, speed * 0.5)
			shoot_timer -= delta
			if shoot_timer <= 0.0:
				shoot_timer = SHOOT_INTERVAL
				_shoot_at_player()

func _patrol(delta: float, s: float) -> void:
	position.x += direction * s * delta
	if absf(position.x - start_x) > patrol_distance:
		direction *= -1

func _shoot_at_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or absf(player.global_position.x - global_position.x) > SHOOT_RANGE:
		return
	var bullet := ENEMY_BULLET_SCENE.instantiate()
	bullet.dir = (player.global_position - global_position).normalized()
	bullet.global_position = global_position
	get_tree().current_scene.add_child(bullet)

func _die() -> void:
	Game.add_kill()
	Sfx.play("kill", -8.0)
	Fx.burst(global_position, $Sprite2D.modulate, 14, 180.0)
	Fx.shake(3.0)
	queue_free()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		if body.has_method("has_instant_kill") and body.has_instant_kill():
			_die()
		elif body.velocity.y > 0.0 and body.global_position.y < global_position.y - 15.0:
			# Pisão: cair em cima do inimigo mata-o e o jogador ressalta.
			Game.add_stomp()
			_die()
			body.velocity.y = -320.0
		elif body.has_method("consume_shield") and body.consume_shield():
			_die()
		else:
			Game.die()

func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("bullet"):
		area.queue_free()
		_die()
