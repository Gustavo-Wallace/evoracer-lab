class_name RaceTrack
extends Node2D

const BACKGROUND_COLOR := Color("07101a")
const ROAD_COLOR := Color("252f3a")
const OUTER_BORDER_COLOR := Color("6c8294")
const INNER_BORDER_COLOR := Color("7f96a8")
const GUIDE_COLOR := Color(0.55, 0.68, 0.76, 0.16)
const START_LIGHT := Color("dceaf2")
const START_DARK := Color("202a33")

const OUTER_RECT := Rect2(80.0, 70.0, 1120.0, 580.0)
const INNER_RECT := Rect2(315.0, 215.0, 650.0, 290.0)
const GUIDE_RECT := Rect2(197.5, 142.5, 885.0, 435.0)
const OUTER_RADIUS := 145.0
const INNER_RADIUS := 92.0
const GUIDE_RADIUS := 118.0
const CORNER_SEGMENTS := 10

@onready var outer_surface: Polygon2D = $OuterSurface
@onready var inner_ground: Polygon2D = $InnerGround
@onready var guide_line: Line2D = $GuideLine
@onready var outer_border: Line2D = $OuterBorder
@onready var inner_border: Line2D = $InnerBorder
@onready var boundaries: StaticBody2D = $Boundaries
@onready var start_grid: Node2D = $StartGrid


func _ready() -> void:
	var outer_points := _rounded_rectangle(OUTER_RECT, OUTER_RADIUS, CORNER_SEGMENTS)
	var inner_points := _rounded_rectangle(INNER_RECT, INNER_RADIUS, CORNER_SEGMENTS)
	var guide_points := _rounded_rectangle(GUIDE_RECT, GUIDE_RADIUS, CORNER_SEGMENTS)

	outer_surface.polygon = outer_points
	inner_ground.polygon = inner_points
	guide_line.points = guide_points
	outer_border.points = outer_points
	inner_border.points = inner_points

	_create_boundary(outer_points, "Outer")
	_create_boundary(inner_points, "Inner")
	_create_start_grid()


func _rounded_rectangle(rect: Rect2, radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centers := [
		rect.position + Vector2(radius, radius),
		Vector2(rect.end.x - radius, rect.position.y + radius),
		rect.end - Vector2(radius, radius),
		Vector2(rect.position.x + radius, rect.end.y - radius),
	]
	var starting_angles := [PI, -PI * 0.5, 0.0, PI * 0.5]

	for corner_index in range(centers.size()):
		for step in range(segments + 1):
			var angle: float = starting_angles[corner_index] + (PI * 0.5 * step / segments)
			points.append(centers[corner_index] + Vector2.from_angle(angle) * radius)

	return points


func _create_boundary(points: PackedVector2Array, boundary_name: String) -> void:
	for index in range(points.size()):
		var segment := SegmentShape2D.new()
		segment.a = points[index]
		segment.b = points[(index + 1) % points.size()]

		var collision := CollisionShape2D.new()
		collision.name = "%sSegment%02d" % [boundary_name, index]
		collision.shape = segment
		boundaries.add_child(collision)


func _create_start_grid() -> void:
	const CELL_SIZE := Vector2(10.0, 16.0)
	const ROWS := 8
	const COLUMNS := 2
	var origin := Vector2(500.0, INNER_RECT.end.y + 8.0)

	for row in range(ROWS):
		for column in range(COLUMNS):
			var cell := Polygon2D.new()
			var cell_origin := origin + Vector2(column * CELL_SIZE.x, row * CELL_SIZE.y)
			cell.polygon = PackedVector2Array([
				cell_origin,
				cell_origin + Vector2(CELL_SIZE.x, 0.0),
				cell_origin + CELL_SIZE,
				cell_origin + Vector2(0.0, CELL_SIZE.y),
			])
			cell.color = START_LIGHT if (row + column) % 2 == 0 else START_DARK
			start_grid.add_child(cell)
