extends CharacterBody2D

const SPEED := 300.0
const JUMP_VELOCITY := -540.0
const COYOTE_TIME := 0.12
const FLIGHT_SPEED := 320.0
const BUFF_MIN_DURATION := 4.0
const BUFF_MAX_DURATION := 8.0
const MAGNET_RADIUS := 320.0
const MAGNET_PULL_SPEED := 600.0
const RAPID_FIRE_INTERVAL := 0.15
const SUPER_JUMP_MULT := 1.5
const DOUBLE_SPEED_MULT := 2.0
const SLOW_MOTION_SCALE := 0.5
const BULLET_SCENE := preload("res://scenes/Bullet.tscn")

enum Buff { FLIGHT, INSTANT_KILL, COIN_MAGNET, RAPID_FIRE, SUPER_JUMP, SHIELD, SLOW_MOTION, DOUBLE_SPEED, DOUBLE_COINS, DOUBLE_KILLS }

const BUFF_NAMES := {
	Buff.FLIGHT: "Voo Livre",
	Buff.INSTANT_KILL: "Toque Fatal",
	Buff.COIN_MAGNET: "Íman de Moedas",
	Buff.RAPID_FIRE: "Tiro Rápido",
	Buff.SUPER_JUMP: "Super Salto",
	Buff.SHIELD: "Escudo",
	Buff.SLOW_MOTION: "Câmara Lenta",
	Buff.DOUBLE_SPEED: "Velocidade Dupla",
	Buff.DOUBLE_COINS: "Moedas a Dobrar",
	Buff.DOUBLE_KILLS: "Inimigos a Dobrar",
}

const BUFF_COLORS := {
	Buff.FLIGHT: Color(0.4, 0.9, 1.0),
	Buff.INSTANT_KILL: Color(1.0, 0.2, 0.2),
	Buff.COIN_MAGNET: Color(1.0, 0.8, 0.25),
	Buff.RAPID_FIRE: Color(1.0, 0.55, 0.1),
	Buff.SUPER_JUMP: Color(0.3, 1.0, 0.4),
	Buff.SHIELD: Color(0.75, 0.85, 1.0),
	Buff.SLOW_MOTION: Color(0.55, 0.5, 1.0),
	Buff.DOUBLE_SPEED: Color(1.0, 0.3, 0.8),
	Buff.DOUBLE_COINS: Color(1.0, 1.0, 0.3),
	Buff.DOUBLE_KILLS: Color(0.6, 0.3, 0.1),
}

var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
var coyote_timer := 0.0
var active_buff := -1 # -1 = none, otherwise a Buff enum value
var buff_timer := 0.0
var fire_timer := 0.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("player")
	rng.randomize()
	_update_color()
	Palette.palette_changed.connect(_update_color)
	Game.kill_buff_earned.connect(_on_kill_buff_earned)

func _update_color() -> void:
	if active_buff != -1:
		return
	$Sprite2D.modulate = Palette.get_color("player")

func has_instant_kill() -> bool:
	return active_buff == Buff.INSTANT_KILL

# The enemy calls this on contact: returns true if the shield absorbed the
# hit (consuming the whole buff), false if the player has no shield.
func consume_shield() -> bool:
	if active_buff != Buff.SHIELD:
		return false
	_end_buff()
	return true

# Only one buff is ever active at a time; all Buff values are equally likely,
# regardless of how many buffs exist (see Buff enum above).
func _on_kill_buff_earned() -> void:
	var buff: int = rng.randi_range(0, Buff.size() - 1)
	activate_buff(buff, rng.randf_range(BUFF_MIN_DURATION, BUFF_MAX_DURATION))

func activate_buff(buff: int, duration: float) -> void:
	_clear_buff_effects()
	active_buff = buff
	buff_timer = duration
	$Sprite2D.modulate = BUFF_COLORS[buff]
	match buff:
		Buff.FLIGHT:
			velocity = Vector2.ZERO
		Buff.SLOW_MOTION:
			Game.world_speed_scale = SLOW_MOTION_SCALE
		Buff.DOUBLE_COINS:
			Game.coin_multiplier = 2
		Buff.DOUBLE_KILLS:
			Game.kill_multiplier = 2

# Undoes every buff side effect that lives outside the player, so replacing
# one buff with another never leaves stale state behind.
func _clear_buff_effects() -> void:
	Game.world_speed_scale = 1.0
	Game.coin_multiplier = 1
	Game.kill_multiplier = 1

func _end_buff() -> void:
	_clear_buff_effects()
	active_buff = -1
	_update_color()

func _pull_coins(delta: float) -> void:
	for coin in get_tree().get_nodes_in_group("coin"):
		var offset: Vector2 = global_position - coin.global_position
		if offset.length() < MAGNET_RADIUS:
			coin.global_position += offset.limit_length(MAGNET_PULL_SPEED * delta)

func _unhandled_input(event: InputEvent) -> void:
	if Game.game_over:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_X:
		shoot()

func shoot() -> void:
	var bullet: Area2D = BULLET_SCENE.instantiate()
	var facing := 1 if $Sprite2D.scale.x > 0 else -1
	bullet.direction = facing
	bullet.global_position = global_position + Vector2(facing * 24, 0)
	get_tree().current_scene.add_child(bullet)

func _physics_process(delta: float) -> void:
	if Game.game_over:
		return

	if active_buff != -1:
		buff_timer -= delta
		if buff_timer <= 0.0:
			_end_buff()

	if active_buff == Buff.COIN_MAGNET:
		_pull_coins(delta)

	if active_buff == Buff.RAPID_FIRE:
		fire_timer -= delta
		if fire_timer <= 0.0:
			shoot()
			fire_timer = RAPID_FIRE_INTERVAL

	if active_buff == Buff.FLIGHT:
		var vx := Input.get_axis("ui_left", "ui_right")
		var vy := Input.get_axis("ui_up", "ui_down")
		velocity.x = vx * FLIGHT_SPEED
		velocity.y = vy * FLIGHT_SPEED
		if vx != 0:
			$Sprite2D.scale.x = 2 if vx > 0 else -2

		move_and_slide()
		Game.update_distance(global_position.x)
		if global_position.y > 900:
			Game.die()
		return

	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		velocity.y += gravity * delta
		coyote_timer -= delta

	if coyote_timer > 0.0 and Input.is_action_just_pressed("ui_accept"):
		velocity.y = JUMP_VELOCITY * (SUPER_JUMP_MULT if active_buff == Buff.SUPER_JUMP else 1.0)
		coyote_timer = 0.0

	var run_speed := SPEED * (DOUBLE_SPEED_MULT if active_buff == Buff.DOUBLE_SPEED else 1.0)
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction != 0:
		velocity.x = direction * run_speed
		$Sprite2D.scale.x = 2 if direction > 0 else -2
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

	Game.update_distance(global_position.x)

	if global_position.y > 900:
		Game.die()
