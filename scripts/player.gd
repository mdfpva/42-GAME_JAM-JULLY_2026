extends CharacterBody2D

const SPEED := 300.0
const JUMP_VELOCITY := -540.0
const COYOTE_TIME := 0.12
const JUMP_BUFFER := 0.12
const JUMP_CUT := 0.45 # releasing jump early keeps only this fraction of rise
const FLIGHT_SPEED := 320.0
const BUFF_MIN_DURATION := 4.0
const BUFF_MAX_DURATION := 8.0
const MAGNET_RADIUS := 320.0
const MAGNET_PULL_SPEED := 600.0
const RAPID_FIRE_INTERVAL := 0.15
const SUPER_JUMP_MULT := 1.5
const DOUBLE_SPEED_MULT := 2.0
const SLOW_MOTION_SCALE := 0.5
const SQUASH_RECOVER_SPEED := 3.0
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
var jump_buffer_timer := 0.0
var active_buff := -1 # -1 = none, otherwise a Buff enum value
var buff_timer := 0.0
var fire_timer := 0.0
var facing := 1
var squash := 1.0 # 1 = normal; <1 squashed on landing, >1 stretched on jump
var was_on_floor := true
var shake_strength := 0.0
var speed_upgrade := 1.0
var jump_upgrade := 1.0
var buff_time_bonus := 0.0
var trail: CPUParticles2D
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	add_to_group("player")
	rng.randomize()
	speed_upgrade = 1.0 + 0.10 * int(Game.upgrades.get("speed", 0))
	jump_upgrade = 1.0 + 0.08 * int(Game.upgrades.get("jump", 0))
	buff_time_bonus = 1.0 * int(Game.upgrades.get("buff", 0))
	_make_trail()
	_update_color()
	Palette.palette_changed.connect(_update_color)
	Game.kill_buff_earned.connect(_on_kill_buff_earned)

func _make_trail() -> void:
	trail = CPUParticles2D.new()
	trail.amount = 24
	trail.lifetime = 0.3
	trail.local_coords = false
	trail.texture = $Sprite2D.texture
	trail.scale_amount_min = 0.15
	trail.scale_amount_max = 0.25
	trail.gravity = Vector2.ZERO
	trail.initial_velocity_min = 10.0
	trail.initial_velocity_max = 30.0
	trail.spread = 180.0
	add_child(trail)

func add_shake(strength: float) -> void:
	shake_strength = maxf(shake_strength, strength)

func _update_fx(delta: float) -> void:
	trail.emitting = absf(velocity.x) > 40.0 or active_buff == Buff.FLIGHT
	match Game.equipped_trail:
		"fogo":
			trail.color = Color(1.0, randf_range(0.3, 0.6), 0.05)
		"arco":
			trail.color = Color.from_hsv(fmod(Time.get_ticks_msec() * 0.0004, 1.0), 0.85, 1.0)
		"estrelas":
			trail.color = Color(1.0, 1.0, 0.85)
		_:
			trail.color = $Sprite2D.modulate
	if shake_strength > 0.01:
		$Camera2D.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_strength
		shake_strength = maxf(shake_strength - 40.0 * delta, 0.0)
	else:
		$Camera2D.offset = Vector2.ZERO

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
	Game.break_combo()
	_end_buff()
	return true

# Only one buff is ever active at a time; all Buff values are equally likely,
# regardless of how many buffs exist (see Buff enum above).
func _on_kill_buff_earned() -> void:
	var buff: int = rng.randi_range(0, Buff.size() - 1)
	activate_buff(buff, rng.randf_range(BUFF_MIN_DURATION, BUFF_MAX_DURATION) + buff_time_bonus)
	Sfx.play("buff")

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
	if event.is_action_pressed("shoot") and not event.is_echo():
		shoot()

func shoot() -> void:
	var bullet: Area2D = BULLET_SCENE.instantiate()
	bullet.direction = facing
	bullet.global_position = global_position + Vector2(facing * 24, 0)
	get_tree().current_scene.add_child(bullet)
	Sfx.play("shoot", -12.0)

func _update_sprite(delta: float) -> void:
	squash = move_toward(squash, 1.0, SQUASH_RECOVER_SPEED * delta)
	$Sprite2D.scale = Vector2(facing * 2.0 / sqrt(squash), 3.0 * squash)

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
			facing = 1 if vx > 0 else -1

		move_and_slide()
		was_on_floor = false
		_update_sprite(delta)
		_update_fx(delta)
		Game.update_distance(global_position.x)
		if global_position.y > 900:
			Game.die()
		return

	if is_on_floor():
		coyote_timer = COYOTE_TIME
	else:
		velocity.y += gravity * delta
		coyote_timer -= delta

	# Jump buffering: a press slightly before landing still triggers the jump.
	if Input.is_action_just_pressed("ui_accept"):
		jump_buffer_timer = JUMP_BUFFER
	else:
		jump_buffer_timer -= delta

	if coyote_timer > 0.0 and jump_buffer_timer > 0.0:
		velocity.y = JUMP_VELOCITY * jump_upgrade * (SUPER_JUMP_MULT if active_buff == Buff.SUPER_JUMP else 1.0)
		coyote_timer = 0.0
		jump_buffer_timer = 0.0
		squash = 1.35
		Sfx.play("jump", -8.0)

	# Variable jump: releasing early cuts the rise short.
	if velocity.y < 0.0 and Input.is_action_just_released("ui_accept"):
		velocity.y *= JUMP_CUT

	var run_speed := SPEED * speed_upgrade * (DOUBLE_SPEED_MULT if active_buff == Buff.DOUBLE_SPEED else 1.0)
	var direction := Input.get_axis("ui_left", "ui_right")
	var on_ice := Game.current_biome == Game.BIOME_ICE
	if direction != 0:
		if on_ice:
			velocity.x = move_toward(velocity.x, direction * run_speed, run_speed * 3.0 * delta)
		else:
			velocity.x = direction * run_speed
		facing = 1 if direction > 0 else -1
	elif on_ice:
		velocity.x = move_toward(velocity.x, 0, run_speed * 1.5 * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

	if is_on_floor() and not was_on_floor:
		squash = 0.62
		Sfx.play("land", -16.0)
		Fx.burst(global_position + Vector2(0, 22), Color(1, 1, 1, 0.6), 6, 70.0)
	was_on_floor = is_on_floor()
	_update_sprite(delta)
	_update_fx(delta)

	Game.update_distance(global_position.x)

	if global_position.y > 900:
		Game.die()
