extends Node2D

const PLATFORM_HEIGHT := 40.0
const START_TOP_Y := 600.0
const MIN_WIDTH := 150.0
const MAX_WIDTH := 350.0
const AHEAD_BUFFER := 1500.0
const BEHIND_DESPAWN := 1200.0
const SQUARE_TEXTURE := preload("res://assets/white_square.svg")

const TOP_Y_MIN := 80.0
const TOP_Y_MAX := 650.0
const TREND_MIN_LEN := 4
const TREND_MAX_LEN := 9
const TREND_STEP_MIN := 60.0
const TREND_STEP_MAX := 110.0 # kept below the player's real max jump height (see _max_reach)

const SIDE_MIN_LEN := 2
const SIDE_MAX_LEN := 5
const SIDE_STEP_MIN := 20.0
const SIDE_STEP_MAX := 90.0
const MIN_NET_ADVANCE := 40.0

# Must mirror scripts/player.gd (JUMP_VELOCITY magnitude and SPEED), so every
# generated gap is guaranteed reachable with a real jump.
const JUMP_SPEED := 540.0
const RUN_SPEED := 300.0
const REACH_MARGIN := 0.8 # leaves slack for imperfect human timing

const CoinScene := preload("res://scenes/Coin.tscn")
const EnemyScene := preload("res://scenes/Enemy.tscn")
const MovingPlatformScene := preload("res://scenes/MovingPlatform.tscn")

@onready var player: CharacterBody2D = $Player
@onready var stats_label: Label = $UI/StatsLabel
@onready var buff_label: Label = $UI/BuffLabel
@onready var controls_panel: Control = $UI/ControlsPanel
@onready var game_over_panel: Control = $UI/GameOverPanel
@onready var game_over_label: Label = $UI/GameOverPanel/Label
@onready var highscore_banner: Label = $UI/HighscoreBanner
@onready var scoreboard_panel: Control = $UI/ScoreboardPanel
@onready var scoreboard_label: Label = $UI/ScoreboardPanel/Label

var chunks: Array[Node] = []
var colorable: Array[Dictionary] = []
var next_x := 0.0
var current_top_y := START_TOP_Y
var rng := RandomNumberGenerator.new()
var trend := 1
var trend_remaining := 0
var side_trend := 1
var side_trend_remaining := 0
var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")

func _ready() -> void:
	rng.randomize()
	controls_panel.visible = false
	game_over_panel.visible = false
	highscore_banner.visible = false
	scoreboard_panel.visible = false
	Game.reset()
	Game.stats_changed.connect(_on_stats_changed)
	Game.died.connect(_on_player_died)
	Game.new_highscore_reached.connect(_on_new_highscore_reached)
	Palette.palette_changed.connect(_on_palette_changed)
	_on_stats_changed()

	_spawn_start_platform()
	while next_x < player.global_position.x + AHEAD_BUFFER * 2.0:
		_spawn_next_chunk()

func _process(_delta: float) -> void:
	if Game.game_over:
		return
	_update_buff_label()
	while next_x < player.global_position.x + AHEAD_BUFFER:
		_spawn_next_chunk()
	_despawn_behind(player.global_position.x - BEHIND_DESPAWN)

func _update_buff_label() -> void:
	if player.active_buff == -1:
		buff_label.visible = false
		return
	buff_label.text = "BUFF: %s (%.1fs)" % [player.BUFF_NAMES[player.active_buff], maxf(player.buff_timer, 0.0)]
	buff_label.add_theme_color_override("font_color", player.BUFF_COLORS[player.active_buff])
	buff_label.visible = true

func _spawn_start_platform() -> void:
	var width := 500.0
	_add_platform(0.0, width, current_top_y, false)
	next_x = width

# Max horizontal distance the player can cover for a jump that changes height
# by `h` (positive = climbing, negative = dropping), assuming a full-power jump.
# Descents get a larger reach for free since gravity gives extra hang time.
func _max_reach(h: float) -> float:
	var capped_h: float = min(h, (JUMP_SPEED * JUMP_SPEED) / (2.0 * gravity))
	var disc: float = max(JUMP_SPEED * JUMP_SPEED - 2.0 * gravity * capped_h, 0.0)
	var t: float = (JUMP_SPEED + sqrt(disc)) / gravity
	return RUN_SPEED * t * REACH_MARGIN

func _spawn_next_chunk() -> void:
	var at_top := trend == 1 and current_top_y <= TOP_Y_MIN + 5.0
	var at_bottom := trend == -1 and current_top_y >= TOP_Y_MAX - 5.0
	if trend_remaining <= 0 or at_top or at_bottom:
		trend = -1 if trend == 1 else 1
		trend_remaining = rng.randi_range(TREND_MIN_LEN, TREND_MAX_LEN)
	trend_remaining -= 1

	var delta_up := trend * rng.randf_range(TREND_STEP_MIN, TREND_STEP_MAX)
	var new_top_y: float = clamp(current_top_y - delta_up, TOP_Y_MIN, TOP_Y_MAX)
	var height_diff := current_top_y - new_top_y

	var gap: float
	if height_diff > 30.0:
		gap = rng.randf_range(50.0, 110.0)
	else:
		gap = rng.randf_range(60.0, 180.0)

	if side_trend_remaining <= 0:
		side_trend = -1 if side_trend == 1 else 1
		side_trend_remaining = rng.randi_range(SIDE_MIN_LEN, SIDE_MAX_LEN)
	side_trend_remaining -= 1
	gap += side_trend * rng.randf_range(SIDE_STEP_MIN, SIDE_STEP_MAX)

	var max_reach := _max_reach(height_diff)
	gap = clamp(gap, -max_reach, max_reach)

	var width := rng.randf_range(MIN_WIDTH, MAX_WIDTH)
	if gap + width < MIN_NET_ADVANCE:
		gap = MIN_NET_ADVANCE - width

	var start_x := next_x + gap
	var make_dynamic := rng.randf() < 0.25 or (gap > 90.0 and rng.randf() < 0.15)

	if make_dynamic:
		width = 100.0
		_add_moving_platform(start_x, new_top_y)
	else:
		_add_platform(start_x, width, new_top_y, true)

	if rng.randf() < 0.55:
		_add_coin(start_x + width * 0.5, new_top_y - 40.0)

	if not make_dynamic and width > 180.0 and rng.randf() < 0.35:
		var patrol: float = clamp(width * 0.35, 20.0, width * 0.5 - 20.0)
		_add_enemy(start_x + width * 0.5, new_top_y - 20.0, patrol)

	current_top_y = new_top_y
	next_x = start_x + width

func _add_platform(x: float, width: float, top_y: float, track: bool) -> void:
	var body := StaticBody2D.new()
	body.position = Vector2(x + width * 0.5, top_y + PLATFORM_HEIGHT * 0.5)
	add_child(body)

	var role := "ground" if width > 250.0 else "platform"
	var sprite := Sprite2D.new()
	sprite.texture = SQUARE_TEXTURE
	sprite.scale = Vector2(width / 16.0, PLATFORM_HEIGHT / 16.0)
	sprite.modulate = Palette.get_color(role)
	body.add_child(sprite)
	colorable.append({"node": sprite, "role": role})

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(width, PLATFORM_HEIGHT)
	shape.shape = rect
	body.add_child(shape)

	if track:
		chunks.append(body)

func _add_moving_platform(x: float, top_y: float) -> void:
	var mp := MovingPlatformScene.instantiate()
	mp.position = Vector2(x + 50.0, top_y + 12.0)
	var pattern: int = rng.randi_range(0, 3)
	mp.pattern = pattern
	match pattern:
		0: # horizontal
			mp.travel_distance = 160.0
			mp.speed = 80.0
		1: # vertical
			mp.travel_distance = 130.0
			mp.speed = 70.0
		2: # diagonal
			mp.travel_distance = 150.0
			mp.speed = 75.0
			mp.diagonal_dir = Vector2(1, -1).normalized() if rng.randf() < 0.5 else Vector2(1, 1).normalized()
		3: # circular
			mp.travel_distance = 80.0
			mp.speed = 100.0
	add_child(mp)
	chunks.append(mp)

func _add_coin(x: float, y: float) -> void:
	var coin := CoinScene.instantiate()
	coin.position = Vector2(x, y)
	add_child(coin)
	chunks.append(coin)

func _add_enemy(x: float, y: float, patrol: float) -> void:
	var enemy := EnemyScene.instantiate()
	enemy.position = Vector2(x, y)
	enemy.patrol_distance = patrol
	add_child(enemy)
	chunks.append(enemy)

func _despawn_behind(threshold_x: float) -> void:
	for i in range(chunks.size() - 1, -1, -1):
		var node: Node = chunks[i]
		if not is_instance_valid(node):
			chunks.remove_at(i)
			continue
		if node.position.x < threshold_x:
			node.queue_free()
			chunks.remove_at(i)

func _on_palette_changed() -> void:
	for i in range(colorable.size() - 1, -1, -1):
		var entry: Dictionary = colorable[i]
		if not is_instance_valid(entry["node"]):
			colorable.remove_at(i)
			continue
		entry["node"].modulate = Palette.get_color(entry["role"])

func _on_stats_changed() -> void:
	stats_label.text = "Distância: %dm   Moedas: %d   Inimigos: %d" % [Game.distance, Game.coins, Game.kills]

func _on_new_highscore_reached() -> void:
	highscore_banner.visible = true
	await get_tree().create_timer(3.0).timeout
	highscore_banner.visible = false

func _build_score_table_lines() -> Array[String]:
	var lines: Array[String] = ["TABELA DE PONTUAÇÕES"]
	if Game.scores.is_empty():
		lines.append("(ainda sem registos)")
	for i in range(Game.scores.size()):
		var entry: Dictionary = Game.scores[i]
		var marker := "  <- TU" if i == 0 and Game.is_new_highscore and Game.game_over else ""
		lines.append("%d. %dm — %d moedas, %d inimigos%s" % [i + 1, int(entry["distance"]), int(entry["coins"]), int(entry["kills"]), marker])
	return lines

func _show_scoreboard() -> void:
	var lines := _build_score_table_lines()
	lines.append("")
	lines.append("T - Fechar")
	scoreboard_label.text = "\n".join(lines)
	scoreboard_panel.visible = true

func _on_player_died() -> void:
	highscore_banner.visible = false
	var lines: Array[String] = ["GAME OVER"]

	if Game.is_new_highscore:
		lines.append("")
		lines.append("NOVO RECORDE! PARABÉNS!")

	lines.append("")
	lines.append("Distância: %dm   Moedas: %d   Inimigos: %d" % [Game.distance, Game.coins, Game.kills])
	lines.append("")
	lines.append_array(_build_score_table_lines())
	lines.append("")
	lines.append("R - Reiniciar")

	game_over_label.text = "\n".join(lines)
	game_over_panel.visible = true

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_H:
			controls_panel.visible = not controls_panel.visible
		elif event.keycode == KEY_T:
			if scoreboard_panel.visible:
				scoreboard_panel.visible = false
			else:
				_show_scoreboard()
		elif event.keycode == KEY_C:
			Game.clear_scores()
			if game_over_panel.visible:
				_on_player_died()
			if scoreboard_panel.visible:
				_show_scoreboard()
