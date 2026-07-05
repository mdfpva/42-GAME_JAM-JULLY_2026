extends StaticBody2D

var crumbling := false

func _ready() -> void:
	$Sensor.body_entered.connect(_on_sensor_body_entered)
	_update_color()
	Palette.palette_changed.connect(_update_color)

func _update_color() -> void:
	# Preserve alpha so a palette shuffle mid-crumble doesn't undo the fade.
	var c := Palette.get_color("platform").darkened(0.35)
	c.a = $Sprite2D.modulate.a
	$Sprite2D.modulate = c

func _on_sensor_body_entered(body: Node2D) -> void:
	if crumbling or not body.is_in_group("player"):
		return
	crumbling = true
	Sfx.play("crumble", -10.0)
	var tw := create_tween()
	tw.tween_property($Sprite2D, "modulate:a", 0.35, 0.5)
	tw.tween_callback(_fall)

func _fall() -> void:
	$CollisionShape2D.set_deferred("disabled", true)
	var tw := create_tween()
	tw.tween_property($Sprite2D, "modulate:a", 0.0, 0.3)
	tw.tween_callback(queue_free)
