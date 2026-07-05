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
const SpikeScene := preload("res://scenes/Spike.tscn")
const CrumblingPlatformScene := preload("res://scenes/CrumblingPlatform.tscn")
const BossScene := preload("res://scenes/Boss.tscn")

const BOSS_INTERVAL := 15000.0 # px (= 1500 m)
const DIFFICULTY_RAMP_X := 20000.0 # px until max difficulty

@onready var player: CharacterBody2D = $Player
@onready var stats_label: Label = $UI/StatsLabel
@onready var buff_label: Label = $UI/BuffLabel
@onready var missions_label: Label = $UI/MissionsLabel
@onready var daily_label: Label = $UI/DailyLabel
@onready var pause_panel: Control = $UI/PausePanel
@onready var pause_label: Label = $UI/PausePanel/Label
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
var current_difficulty := 0.0
var next_boss_x := BOSS_INTERVAL

func _ready() -> void:
	if Game.daily_mode:
		rng.seed = Game.daily_seed()
	else:
		rng.randomize()
	controls_panel.visible = false
	game_over_panel.visible = false
	highscore_banner.visible = false
	scoreboard_panel.visible = false
	Game.reset()
	Game.stats_changed.connect(_on_stats_changed)
	Game.died.connect(_on_player_died)
	Game.new_highscore_reached.connect(_on_new_highscore_reached)
	Game.mission_completed.connect(_on_mission_completed)
	Game.pause_toggled.connect(_on_pause_toggled)
	Game.meta_changed.connect(_refresh_pause_panel)
	Palette.palette_changed.connect(_on_palette_changed)
	daily_label.visible = Game.daily_mode
	pause_panel.visible = false
	get_tree().paused = false
	_build_parallax()
	_on_stats_changed()
	_update_missions_label()

	_spawn_start_platform()
	while next_x < player.global_position.x + AHEAD_BUFFER * 2.0:
		_spawn_next_chunk()

func _process(_delta: float) -> void:
	if Game.game_over:
		return
	Game.decay_combo()
	_update_buff_label()
	_update_missions_label()
	var intensity := 0.35 + 0.06 * (Game.combo - 1) + current_difficulty * 0.15
	if player.active_buff != -1:
		intensity += 0.3
	Music.set_intensity(intensity)
	while next_x < player.global_position.x + AHEAD_BUFFER:
		_spawn_next_chunk()
	_despawn_behind(player.global_position.x - BEHIND_DESPAWN)

func _update_missions_label() -> void:
	var lines: Array[String] = ["MISSÕES:"]
	for m in Game.missions:
		if m["done"]:
			lines.append("[OK] " + Game.mission_text(m))
		else:
			lines.append("- %s (%d/%d)" % [Game.mission_text(m), mini(Game.mission_progress(m), m["target"]), m["target"]])
	missions_label.text = "\n".join(lines)

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
	# Higher difficulty shrinks the safety slack (0.8 -> 0.9), never past
	# the physical limit (1.0), so gaps stay possible — just tighter.
	return RUN_SPEED * t * lerpf(REACH_MARGIN, 0.90, current_difficulty)

func _spawn_next_chunk() -> void:
	current_difficulty = clampf(next_x / DIFFICULTY_RAMP_X, 0.0, 1.0)
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
	gap *= 1.0 + 0.2 * current_difficulty

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
	var make_crumbling := not make_dynamic and rng.randf() < 0.15 + 0.1 * current_difficulty

	if make_dynamic:
		width = 100.0
		_add_moving_platform(start_x, new_top_y)
	elif make_crumbling:
		width = 120.0
		_add_crumbling_platform(start_x, new_top_y)
	else:
		_add_platform(start_x, width, new_top_y, true)

	if rng.randf() < 0.6:
		_add_coin_pattern(start_x, width, new_top_y, gap, current_top_y)

	if not make_dynamic and not make_crumbling and width > 180.0 and rng.randf() < 0.35 + 0.2 * current_difficulty:
		var patrol: float = clamp(width * 0.35, 20.0, width * 0.5 - 20.0)
		_add_enemy(start_x, width, new_top_y, patrol)

	if not make_dynamic and not make_crumbling and width > 200.0 and rng.randf() < 0.22 + 0.13 * current_difficulty:
		_add_spikes(start_x, width, new_top_y)

	if start_x > next_boss_x:
		next_boss_x += BOSS_INTERVAL
		var boss := BossScene.instantiate()
		boss.position = Vector2(start_x + width * 0.5, new_top_y - 140.0)
		add_child(boss)
		chunks.append(boss)
		_flash_banner("BOSS À VISTA!")

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

# gap/prev_top_y let the arc pattern trace the jump the player just made.
func _add_coin_pattern(x: float, width: float, top_y: float, gap: float, prev_top_y: float) -> void:
	var style := rng.randi_range(0, 2)
	if style == 1 and gap < 70.0:
		style = 0
	if style == 2 and prev_top_y - top_y < 50.0:
		style = 0
	match style:
		0: # fila ao longo da plataforma
			var count := clampi(int(width / 70.0), 2, 5)
			for i in count:
				_add_coin(x + width * (i + 1) / (count + 1.0), top_y - 40.0)
		1: # arco sobre o vão, a seguir a trajetória do salto
			for i in 4:
				var t := (i + 1) / 5.0
				var cy := lerpf(prev_top_y, top_y, t) - sin(t * PI) * 90.0 - 40.0
				_add_coin(x - gap + gap * t, cy)
		2: # coluna vertical numa subida (boa para voo/super salto)
			for i in 3:
				_add_coin(x + width * 0.35, top_y - 40.0 - i * 45.0)

func _add_enemy(platform_x: float, platform_width: float, top_y: float, patrol: float) -> void:
	var enemy := EnemyScene.instantiate()
	var roll := rng.randf()
	if roll < 0.45:
		enemy.type = 0 # patrulha
	elif roll < 0.65:
		enemy.type = 1 # voador
	elif roll < 0.85:
		enemy.type = 2 # perseguidor
	else:
		enemy.type = 3 # atirador
	var y := top_y - 20.0
	if enemy.type == 1:
		y = top_y - 110.0
	enemy.position = Vector2(platform_x + platform_width * 0.5, y)
	enemy.patrol_distance = patrol
	enemy.speed = 80.0 * (1.0 + 0.6 * current_difficulty)
	add_child(enemy)
	chunks.append(enemy)

func _add_spikes(platform_x: float, platform_width: float, top_y: float) -> void:
	var count := rng.randi_range(2, 3)
	var center_x := platform_x + platform_width * rng.randf_range(0.35, 0.65)
	for i in count:
		var spike := SpikeScene.instantiate()
		spike.position = Vector2(center_x + (i - (count - 1) * 0.5) * 20.0, top_y - 9.0)
		add_child(spike)
		chunks.append(spike)

func _add_crumbling_platform(x: float, top_y: float) -> void:
	var cp := CrumblingPlatformScene.instantiate()
	cp.position = Vector2(x + 60.0, top_y + 20.0)
	add_child(cp)
	chunks.append(cp)

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
	var text := "Pontos: %d   Distância: %dm   Moedas: %d   Inimigos: %d" % [Game.get_score(), Game.distance, Game.coins, Game.kills]
	if Game.combo > 1:
		text += "   COMBO x%d" % Game.combo
	stats_label.text = text

func _flash_banner(text: String) -> void:
	highscore_banner.text = text
	highscore_banner.visible = true
	await get_tree().create_timer(3.0).timeout
	highscore_banner.visible = false

func _on_new_highscore_reached() -> void:
	_flash_banner("NOVO RECORDE! CONTINUA ASSIM!")

func _on_mission_completed(text: String) -> void:
	_flash_banner("MISSÃO CUMPRIDA: %s  (+%d pts)" % [text, Game.MISSION_REWARD])

func _on_pause_toggled(paused: bool) -> void:
	pause_panel.visible = paused
	if paused:
		_refresh_pause_panel()

func _refresh_pause_panel() -> void:
	var lines: Array[String] = ["PAUSA", ""]
	lines.append("+ / - : Volume geral (%d dB)" % int(Game.master_volume_db))
	lines.append("")
	lines.append("LOJA — mealheiro: %d moedas" % Game.total_coins)
	var ids: Array[String] = ["speed", "jump", "buff"]
	var labels: Array[String] = ["Velocidade +10%/nível", "Salto +8%/nível", "Buff +1s/nível"]
	for i in 3:
		var lvl: int = Game.upgrades[ids[i]]
		var cost := Game.upgrade_cost(ids[i])
		var cost_txt := "MÁX" if cost < 0 else "custa %d" % cost
		lines.append("%d - %s  [nível %d/3, %s]" % [i + 1, labels[i], lvl, cost_txt])
	lines.append("")
	lines.append("(melhorias aplicam-se ao reiniciar: R)")
	lines.append("P / Esc - Continuar")
	pause_label.text = "\n".join(lines)

# Two mirrored layers of soft "hills" built from the same white square,
# moving slower than the action for depth.
func _build_parallax() -> void:
	var pb := ParallaxBackground.new()
	pb.layer = -10
	add_child(pb)
	var configs := [
		{"scale": 0.2, "color": Color(0.70, 0.80, 0.92), "max_h": 320.0, "seed": 11},
		{"scale": 0.45, "color": Color(0.55, 0.70, 0.86), "max_h": 220.0, "seed": 22},
	]
	for cfg in configs:
		var pl := ParallaxLayer.new()
		pl.motion_scale = Vector2(cfg["scale"], 0.1)
		pl.motion_mirroring = Vector2(2400.0, 0.0)
		pb.add_child(pl)
		var prng := RandomNumberGenerator.new()
		prng.seed = cfg["seed"]
		var x := 0.0
		while x < 2400.0:
			var w: float = prng.randf_range(140.0, 320.0)
			var h: float = prng.randf_range(90.0, cfg["max_h"])
			var s := Sprite2D.new()
			s.texture = SQUARE_TEXTURE
			s.scale = Vector2(w / 16.0, h / 16.0)
			s.position = Vector2(x + w * 0.5, 760.0 - h * 0.5)
			s.modulate = cfg["color"]
			pl.add_child(s)
			x += w * prng.randf_range(0.55, 0.8)

func _build_score_table_lines() -> Array[String]:
	var lines: Array[String] = ["TABELA DE PONTUAÇÕES"]
	if Game.scores.is_empty():
		lines.append("(ainda sem registos)")
	for i in range(Game.scores.size()):
		var entry: Dictionary = Game.scores[i]
		var marker := "  <- TU" if i == 0 and Game.is_new_highscore and Game.game_over else ""
		var daily_tag := " [D]" if entry.get("daily", false) else ""
		var score := int(entry.get("score", entry.get("distance", 0)))
		lines.append("%d. %d pts — %dm, %d moedas, %d inimigos%s%s" % [i + 1, score, int(entry["distance"]), int(entry["coins"]), int(entry["kills"]), daily_tag, marker])
	return lines

func _show_scoreboard() -> void:
	var lines := _build_score_table_lines()
	lines.append("")
	lines.append("T - Fechar")
	scoreboard_label.text = "\n".join(lines)
	scoreboard_panel.visible = true

func _on_player_died() -> void:
	Fx.burst(player.global_position, player.get_node("Sprite2D").modulate, 24, 260.0)
	Fx.shake(10.0)
	Music.set_intensity(0.15)
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
		elif event.keycode == KEY_D:
			Game.daily_mode = not Game.daily_mode
			get_tree().reload_current_scene()
		elif event.keycode == KEY_C:
			Game.clear_scores()
			if game_over_panel.visible:
				_on_player_died()
			if scoreboard_panel.visible:
				_show_scoreboard()
