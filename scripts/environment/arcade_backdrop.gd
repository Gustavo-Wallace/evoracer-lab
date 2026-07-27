extends Node2D

const WORLD_RECT := Rect2(-800.0, -500.0, 5200.0, 3300.0)
const TILE_SIZE := 128
const GRASS_LIGHT := Color("579f48")
const GRASS_DARK := Color("4b9341")
const GRASS_MOWING := Color(0.18, 0.42, 0.16, 0.12)
const GRASS_DETAIL_DARK := Color(0.1, 0.3, 0.11, 0.3)
const GRASS_DETAIL_LIGHT := Color(0.72, 0.82, 0.4, 0.24)
const FLOWER_CREAM := Color(0.96, 0.9, 0.65, 0.55)


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(WORLD_RECT, GRASS_DARK)

	for tile_x in range(int(WORLD_RECT.position.x), int(WORLD_RECT.end.x), TILE_SIZE):
		for tile_y in range(int(WORLD_RECT.position.y), int(WORLD_RECT.end.y), TILE_SIZE):
			var tile_column := floori(float(tile_x) / TILE_SIZE)
			var tile_row := floori(float(tile_y) / TILE_SIZE)
			if (tile_column + tile_row) % 2 == 0:
					draw_rect(
						Rect2(tile_x, tile_y, TILE_SIZE, TILE_SIZE),
						GRASS_LIGHT
					)

	for stripe_y in range(int(WORLD_RECT.position.y), int(WORLD_RECT.end.y), 384):
		draw_rect(
			Rect2(
				WORLD_RECT.position.x,
				stripe_y,
				WORLD_RECT.size.x,
				72.0
			),
			GRASS_MOWING
		)

	for x in range(int(WORLD_RECT.position.x) + 40, int(WORLD_RECT.end.x), 160):
		for y in range(int(WORLD_RECT.position.y) + 44, int(WORLD_RECT.end.y), 160):
			var offset := Vector2((x + y) % 17, (x * 2 + y) % 13)
			var tuft_position := Vector2(x, y) + offset
			draw_line(
				tuft_position,
				tuft_position + Vector2(-2.0, -5.0),
				GRASS_DETAIL_DARK,
				1.0
			)
			draw_line(
				tuft_position,
				tuft_position + Vector2(3.0, -4.0),
				GRASS_DETAIL_LIGHT,
				1.0
			)
			if posmod(x / 160 + y / 160, 7) == 0:
				draw_circle(tuft_position + Vector2(6.0, -3.0), 1.5, FLOWER_CREAM)
