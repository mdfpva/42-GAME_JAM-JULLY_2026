extends Area2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_update_color()
	Palette.palette_changed.connect(_update_color)

func _update_color() -> void:
	$Sprite2D.modulate = Palette.get_color("coin")

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		Game.add_coin()
		Sfx.play("coin", -10.0)
		Fx.burst(global_position, $Sprite2D.modulate, 6, 90.0)
		queue_free()
