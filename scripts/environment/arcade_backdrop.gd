extends Node2D

const WORLD_RECT := Rect2(-800.0, -500.0, 5200.0, 3300.0)
const TILE_SIZE := 128
const GRASS_LIGHT := Color("4d9a42")
const GRASS_DARK := Color("478f3d")
const GRASS_DETAIL := Color(0.12, 0.35, 0.13, 0.28)


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

	for x in range(int(WORLD_RECT.position.x) + 40, int(WORLD_RECT.end.x), 160):
		for y in range(int(WORLD_RECT.position.y) + 44, int(WORLD_RECT.end.y), 160):
			var offset := Vector2((x + y) % 17, (x * 2 + y) % 13)
			var tuft_position := Vector2(x, y) + offset
			draw_line(tuft_position, tuft_position + Vector2(-2.0, -5.0), GRASS_DETAIL, 1.0)
			draw_line(tuft_position, tuft_position + Vector2(3.0, -4.0), GRASS_DETAIL, 1.0)
