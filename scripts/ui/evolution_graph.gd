class_name EvolutionGraph
extends Control

var _history: Array[Dictionary] = []


func set_history(entries: Array[Dictionary]) -> void:
	_history = entries.duplicate(true)
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2(8.0, 8.0), size - Vector2(16.0, 16.0))
	draw_rect(bounds, Color(0.04, 0.06, 0.045, 0.74), true)
	draw_rect(bounds, Color(0.72, 0.63, 0.38, 0.55), false, 1.0)
	if _history.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			bounds.position + Vector2(10.0, 22.0),
			"WAITING FOR GENERATIONS",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			10,
			Color(0.86, 0.8, 0.62, 0.72)
		)
		return

	var visible_history := _history.slice(maxi(_history.size() - 20, 0))
	var minimum := INF
	var maximum := -INF
	for entry in visible_history:
		minimum = minf(minimum, float(entry.get("best_fitness", 0.0)))
		minimum = minf(minimum, float(entry.get("average_fitness", 0.0)))
		maximum = maxf(maximum, float(entry.get("best_fitness", 0.0)))
		maximum = maxf(maximum, float(entry.get("average_fitness", 0.0)))
	if is_equal_approx(minimum, maximum):
		minimum -= 1.0
		maximum += 1.0

	var best_points := PackedVector2Array()
	var average_points := PackedVector2Array()
	for index in range(visible_history.size()):
		var x_ratio := (
			float(index) / float(visible_history.size() - 1)
			if visible_history.size() > 1
			else 0.5
		)
		var best_ratio := inverse_lerp(
			minimum,
			maximum,
			float(visible_history[index].get("best_fitness", 0.0))
		)
		var average_ratio := inverse_lerp(
			minimum,
			maximum,
			float(visible_history[index].get("average_fitness", 0.0))
		)
		best_points.append(Vector2(
			lerpf(bounds.position.x, bounds.end.x, x_ratio),
			lerpf(bounds.end.y, bounds.position.y, best_ratio)
		))
		average_points.append(Vector2(
			lerpf(bounds.position.x, bounds.end.x, x_ratio),
			lerpf(bounds.end.y, bounds.position.y, average_ratio)
		))
	if best_points.size() >= 2:
		draw_polyline(best_points, Color("ffd45e"), 2.5, true)
		draw_polyline(average_points, Color("77c88a"), 2.0, true)
	else:
		draw_circle(best_points[0], 3.0, Color("ffd45e"))
		draw_circle(average_points[0], 3.0, Color("77c88a"))
	draw_string(
		ThemeDB.fallback_font,
		bounds.position + Vector2(6.0, 13.0),
		"BEST",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		9,
		Color("ffd45e")
	)
	draw_string(
		ThemeDB.fallback_font,
		bounds.position + Vector2(44.0, 13.0),
		"AVG",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		9,
		Color("77c88a")
	)
