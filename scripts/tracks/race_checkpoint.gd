class_name RaceCheckpoint
extends Area2D

@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var debug_label: Label = $DebugLabel

var checkpoint_index := 0
var checkpoint_count := 0
var _debug_visible := false
var _checkpoint_width := 0.0
var _checkpoint_depth := 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func configure(
	index: int,
	total_count: int,
	checkpoint_transform: Transform2D,
	width: float,
	depth: float
) -> void:
	checkpoint_index = index
	checkpoint_count = total_count
	transform = checkpoint_transform
	_checkpoint_width = width
	_checkpoint_depth = depth

	var rectangle := collision_shape.shape as RectangleShape2D
	if rectangle != null:
		rectangle.size = Vector2(width, depth)

	debug_label.text = "FINISH" if index == 0 else "CP %02d" % index
	debug_label.position = Vector2(-42.0, -depth * 0.5 - 25.0)
	queue_redraw()


func set_debug_visible(is_visible: bool) -> void:
	_debug_visible = is_visible
	debug_label.visible = is_visible
	queue_redraw()


func _draw() -> void:
	if not _debug_visible:
		return

	var color := (
		Color(1.0, 0.78, 0.18, 0.32)
		if checkpoint_index == 0
		else Color(0.2, 0.62, 1.0, 0.28)
	)
	var bounds := Rect2(
		Vector2(-_checkpoint_width * 0.5, -_checkpoint_depth * 0.5),
		Vector2(_checkpoint_width, _checkpoint_depth)
	)
	draw_rect(bounds, color, true)
	draw_rect(bounds, Color(color, 0.9), false, 3.0)
	draw_line(
		Vector2(-_checkpoint_width * 0.5, 0.0),
		Vector2(_checkpoint_width * 0.5, 0.0),
		Color(color, 1.0),
		3.0
	)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("race_cars"):
		return

	for child in body.get_children():
		if child is RaceProgressTracker:
			child.try_validate_checkpoint(checkpoint_index, global_transform)
			return
