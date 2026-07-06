extends Node

signal stats_changed
signal died
signal new_highscore_reached
signal kill_buff_earned
signal mission_completed(text: String)
signal pause_toggled(paused: bool)
signal meta_changed
signal achievement_unlocked(text: String)

const START_X := 100.0
const SAVE_PATH := "user://scores.json"
const META_PATH := "user://meta.json"
const GHOST_PATH := "user://ghost.json"
const MAX_SCORES := 5
const COMBO_WINDOW_MS := 4000
const COMBO_MAX := 9
const MISSION_REWARD := 300
const BOSS_BONUS := 250
const UPGRADE_MAX := 3
const UPGRADE_COSTS := [30, 60, 100] # cost of levels 1, 2, 3
const TRAIL_COSTS := {"fogo": 50, "estrelas": 60, "arco": 80}

const BIOME_NORMAL := 0
const BIOME_ICE := 1
const BIOME_CAVE := 2
const BIOME_NIGHT := 3

const ACHIEVEMENTS := {
	"boss": "Caça-Boss — mata um boss",
	"m1000": "Maratonista — chega aos 1000m",
	"combo5": "Imparável — combo x5",
	"stomp3": "Esmagador — 3 pisões numa run",
	"rico": "Mealheiro cheio — 100 moedas acumuladas",
	"missoes": "Cumpridor — as 3 missões numa run",
}

var distance := 0
var coins := 0
var kills := 0
var game_over := false
var coin_multiplier := 1
var kill_multiplier := 1
var world_speed_scale := 1.0
var combo := 1
var kill_points := 0
var mission_bonus := 0
var last_kill_ms := -1000000
var kill_times: Array[int] = []
var coin_times: Array[int] = []
var missions: Array[Dictionary] = []
var daily_mode := false
var scores: Array = []
var is_new_highscore := false
var previous_best := 0
var beaten_highscore_live := false
var total_coins := 0
var upgrades := {"speed": 0, "jump": 0, "buff": 0}
var master_volume_db := 0.0
var current_biome := BIOME_NORMAL # updated by main from the player's position
var achievements: Array = []
var stomps_run := 0
var owned_trails: Array = []
var equipped_trail := "default"
var ghost_data: Dictionary = {}

func _ready() -> void:
	# Must keep receiving input while the tree is paused (pause menu/shop).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_scores()
	_load_meta()
	_load_ghost()
	AudioServer.set_bus_volume_db(0, master_volume_db)

func unlock(id: String) -> void:
	if id in achievements:
		return
	achievements.append(id)
	_save_meta()
	Sfx.play("mission", -6.0)
	achievement_unlocked.emit(ACHIEVEMENTS[id])

func add_stomp() -> void:
	stomps_run += 1
	if stomps_run >= 3:
		unlock("stomp3")

func buy_or_equip_trail(id: String) -> void:
	if id in owned_trails:
		equipped_trail = "default" if equipped_trail == id else id
		_save_meta()
		meta_changed.emit()
		return
	var cost: int = TRAIL_COSTS[id]
	if total_coins >= cost:
		total_coins -= cost
		owned_trails.append(id)
		equipped_trail = id
		Sfx.play("mission", -8.0)
		_save_meta()
		meta_changed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_game") and not game_over:
		get_tree().paused = not get_tree().paused
		pause_toggled.emit(get_tree().paused)
	elif get_tree().paused and event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				buy_upgrade("speed")
			KEY_2:
				buy_upgrade("jump")
			KEY_3:
				buy_upgrade("buff")
			KEY_4:
				buy_or_equip_trail("fogo")
			KEY_5:
				buy_or_equip_trail("estrelas")
			KEY_6:
				buy_or_equip_trail("arco")
			KEY_MINUS:
				set_master_volume(master_volume_db - 3.0)
			KEY_EQUAL:
				set_master_volume(master_volume_db + 3.0)

func upgrade_cost(id: String) -> int:
	var lvl: int = upgrades.get(id, 0)
	if lvl >= UPGRADE_MAX:
		return -1
	return UPGRADE_COSTS[lvl]

func buy_upgrade(id: String) -> bool:
	var cost := upgrade_cost(id)
	if cost < 0 or total_coins < cost:
		return false
	total_coins -= cost
	upgrades[id] += 1
	Sfx.play("mission", -8.0)
	_save_meta()
	meta_changed.emit()
	return true

func set_master_volume(db: float) -> void:
	master_volume_db = clampf(db, -30.0, 6.0)
	AudioServer.set_bus_volume_db(0, master_volume_db)
	_save_meta()
	meta_changed.emit()

func add_boss_bonus() -> void:
	kill_points += BOSS_BONUS
	stats_changed.emit()
	_check_live_highscore()
	unlock("boss")

func get_score() -> int:
	return distance + coins * 5 + kill_points + mission_bonus

func add_coin() -> void:
	coins += coin_multiplier
	coin_times.append(Time.get_ticks_msec())
	if coin_times.size() > 30:
		coin_times.pop_front()
	stats_changed.emit()
	_check_missions()
	_check_live_highscore()

func add_kill() -> void:
	var previous := kills
	var now := Time.get_ticks_msec()
	combo = mini(combo + 1, COMBO_MAX) if now - last_kill_ms <= COMBO_WINDOW_MS else 1
	last_kill_ms = now
	if combo >= 5:
		unlock("combo5")
	kills += kill_multiplier
	kill_points += 10 * kill_multiplier * combo
	kill_times.append(now)
	if kill_times.size() > 30:
		kill_times.pop_front()
	stats_changed.emit()
	_check_missions()
	_check_live_highscore()
	# Crossing-a-multiple-of-10 check instead of % 10, so a double-kill
	# jump like 9 -> 11 still earns the buff.
	@warning_ignore("integer_division")
	if kills / 10 > previous / 10:
		kill_buff_earned.emit()

func decay_combo() -> void:
	if combo > 1 and Time.get_ticks_msec() - last_kill_ms > COMBO_WINDOW_MS:
		combo = 1
		stats_changed.emit()

func break_combo() -> void:
	if combo > 1:
		combo = 1
		stats_changed.emit()

func update_distance(player_x: float) -> void:
	var d := int(max(0.0, player_x - START_X) / 10.0)
	if d > distance:
		distance = d
		stats_changed.emit()
		_check_missions()
		_check_live_highscore()
		if distance >= 1000:
			unlock("m1000")

func _check_live_highscore() -> void:
	if not beaten_highscore_live and previous_best > 0 and get_score() > previous_best:
		beaten_highscore_live = true
		new_highscore_reached.emit()

func die() -> void:
	if game_over:
		return
	game_over = true
	Sfx.play("death")
	_record_score()
	died.emit()

func reset() -> void:
	distance = 0
	coins = 0
	kills = 0
	game_over = false
	coin_multiplier = 1
	kill_multiplier = 1
	world_speed_scale = 1.0
	combo = 1
	kill_points = 0
	mission_bonus = 0
	last_kill_ms = -1000000
	stomps_run = 0
	kill_times.clear()
	coin_times.clear()
	is_new_highscore = false
	previous_best = get_highscore()
	beaten_highscore_live = false
	_generate_missions()

func daily_seed() -> int:
	var d := Time.get_date_dict_from_system()
	return hash("%04d-%02d-%02d" % [d.year, d.month, d.day])

func _generate_missions() -> void:
	missions.clear()
	var rng := RandomNumberGenerator.new()
	if daily_mode:
		# Offset so the missions differ from the level-generation stream.
		rng.seed = daily_seed() + 7
	else:
		rng.randomize()
	var pool: Array[Dictionary] = [
		{"type": "kills", "target": [10, 15, 20][rng.randi_range(0, 2)]},
		{"type": "coins", "target": [20, 30, 40][rng.randi_range(0, 2)]},
		{"type": "distance", "target": [300, 500, 800][rng.randi_range(0, 2)]},
		{"type": "fast_kills", "target": 3},
		{"type": "fast_coins", "target": 8},
	]
	for i in 3:
		var m: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		m["done"] = false
		missions.append(m)

func mission_text(m: Dictionary) -> String:
	match m["type"]:
		"kills":
			return "Mata %d inimigos" % m["target"]
		"coins":
			return "Apanha %d moedas" % m["target"]
		"distance":
			return "Chega aos %dm" % m["target"]
		"fast_kills":
			return "Mata %d inimigos em 5s" % m["target"]
		"fast_coins":
			return "Apanha %d moedas em 8s" % m["target"]
	return ""

func mission_progress(m: Dictionary) -> int:
	match m["type"]:
		"kills":
			return kills
		"coins":
			return coins
		"distance":
			return distance
		"fast_kills":
			return _count_recent(kill_times, 5000)
		"fast_coins":
			return _count_recent(coin_times, 8000)
	return 0

func _count_recent(times: Array[int], window_ms: int) -> int:
	var now := Time.get_ticks_msec()
	var count := 0
	for t in times:
		if now - t <= window_ms:
			count += 1
	return count

func _check_missions() -> void:
	for m in missions:
		if not m["done"] and mission_progress(m) >= m["target"]:
			m["done"] = true
			mission_bonus += MISSION_REWARD
			Sfx.play("mission")
			mission_completed.emit(mission_text(m))
			stats_changed.emit()
	if missions.size() == 3 and missions.all(func(m): return m["done"]):
		unlock("missoes")

func clear_scores() -> void:
	scores.clear()
	is_new_highscore = false
	previous_best = 0
	_save_scores()

func get_highscore() -> int:
	if scores.is_empty():
		return 0
	return int(scores[0].get("score", scores[0].get("distance", 0)))

func _record_score() -> void:
	total_coins += coins
	if total_coins >= 100:
		unlock("rico")
	_save_meta()
	is_new_highscore = get_score() > 0 and get_score() > previous_best
	scores.append({"score": get_score(), "distance": distance, "coins": coins, "kills": kills, "daily": daily_mode})
	scores.sort_custom(func(a, b): return a.get("score", a.get("distance", 0)) > b.get("score", b.get("distance", 0)))
	if scores.size() > MAX_SCORES:
		scores.resize(MAX_SCORES)
	_save_scores()

func _save_scores() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(scores))
		file.close()

func _load_scores() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Array:
		scores = parsed

func save_ghost(points: Array, interval: float) -> void:
	ghost_data = {"interval": interval, "points": points}
	var file := FileAccess.open(GHOST_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(ghost_data))
		file.close()

func _load_ghost() -> void:
	if not FileAccess.file_exists(GHOST_PATH):
		return
	var file := FileAccess.open(GHOST_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		ghost_data = parsed

func _save_meta() -> void:
	var file := FileAccess.open(META_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({
			"total_coins": total_coins,
			"upgrades": upgrades,
			"volume_db": master_volume_db,
			"achievements": achievements,
			"owned_trails": owned_trails,
			"equipped_trail": equipped_trail,
		}))
		file.close()

func _load_meta() -> void:
	if not FileAccess.file_exists(META_PATH):
		return
	var file := FileAccess.open(META_PATH, FileAccess.READ)
	if not file:
		return
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		total_coins = int(parsed.get("total_coins", 0))
		master_volume_db = float(parsed.get("volume_db", 0.0))
		var u = parsed.get("upgrades", {})
		if u is Dictionary:
			for key in upgrades.keys():
				upgrades[key] = clampi(int(u.get(key, 0)), 0, UPGRADE_MAX)
		var a = parsed.get("achievements", [])
		if a is Array:
			achievements = a
		var t = parsed.get("owned_trails", [])
		if t is Array:
			owned_trails = t
		equipped_trail = str(parsed.get("equipped_trail", "default"))
