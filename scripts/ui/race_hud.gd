class_name RaceHUD
extends CanvasLayer

@onready var speed_value: Label = $Layout/SpeedPanel/SpeedReadout/SpeedValue
@onready var track_label: Label = $Layout/TrackPanel/TrackContent/TrackLabel
@onready var lap_label: Label = $Layout/TrackPanel/TrackContent/RaceData/LapLabel
@onready var checkpoint_label: Label = $Layout/TrackPanel/TrackContent/RaceData/CheckpointLabel
@onready var lap_time_label: Label = $Layout/TrackPanel/TrackContent/RaceData/LapTimeLabel
@onready var spectator_label: Label = $Layout/SpectatorPanel/SpectatorLabel
@onready var leaderboard_panel: PanelContainer = $Layout/LeaderboardPanel
@onready var leaderboard_rows: RichTextLabel = $Layout/LeaderboardPanel/Content/Rows
@onready var event_panel: PanelContainer = $Layout/EventPanel
@onready var event_label: Label = $Layout/EventPanel/EventLabel
@onready var mode_label: Label = $Layout/ModePanel/ModeLabel

var _event_time_remaining := 0.0


func _process(delta: float) -> void:
	if _event_time_remaining <= 0.0:
		return
	_event_time_remaining = maxf(_event_time_remaining - delta, 0.0)
	if _event_time_remaining <= 0.0:
		event_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_leaderboard") and not event.is_echo():
		leaderboard_panel.visible = not leaderboard_panel.visible
		get_viewport().set_input_as_handled()


func set_speed(speed_kmh: float) -> void:
	speed_value.text = "%03d" % roundi(speed_kmh)


func set_track_name(track_name: String) -> void:
	track_label.text = "TRACK 01 - %s" % track_name.to_upper()


func set_mode_label(mode_name: String) -> void:
	mode_label.text = mode_name.to_upper()


func set_race_progress(
	current_lap: int,
	current_checkpoint: int,
	checkpoint_count: int,
	_total_progress: float,
	total_laps: int = 0
) -> void:
	lap_label.text = (
		"LAP %02d/%02d" % [mini(current_lap, total_laps), total_laps]
		if total_laps > 0
		else "LAP %02d" % current_lap
	)
	checkpoint_label.text = "CP %02d/%02d" % [
		current_checkpoint,
		checkpoint_count - 1,
	]


func set_lap_timing(
	lap_time: float,
	_time_since_last_progress: float,
	is_final_time: bool = false
) -> void:
	var minutes := floori(lap_time / 60.0)
	var seconds := fmod(lap_time, 60.0)
	lap_time_label.text = "%s %02d:%05.2f" % [
		"LAST" if is_final_time else "TIME",
		minutes,
		seconds,
	]


func set_spectator_info(
	mode_name: String,
	vehicle_id: String,
	race_position: int,
	car_count: int,
	controller_code := "?"
) -> void:
	spectator_label.text = "%s | %s[%s] | P%02d/%02d" % [
		mode_name,
		vehicle_id,
		controller_code,
		race_position,
		car_count,
	]


func set_leaderboard(entries: Array[Dictionary], followed_vehicle_id: String) -> void:
	var lines := PackedStringArray()
	for entry in entries:
		var position := int(entry["position"])
		var vehicle_id := String(entry["vehicle_id"])
		var controller := String(entry.get("controller", "?"))
		var state := String(entry["state"])
		var lap := int(entry["lap"])
		var lap_count := int(entry["total_laps"])
		var gap := float(entry["gap_seconds"])
		var lap_text := "FIN" if state == "FINISHED" else "L%d/%d" % [lap, lap_count]
		if state == "ABANDONED":
			lap_text = "DNF"
		var gap_text := "--" if position == 1 else "+%.1fs" % gap
		var marker := ">" if vehicle_id == followed_vehicle_id else " "
		var line := "%s %02d  %-10s  %-5s  %s" % [
			marker,
			position,
			"%s[%s]" % [vehicle_id, controller],
			lap_text,
			gap_text,
		]
		if vehicle_id == followed_vehicle_id:
			line = "[color=#ffd45e]%s[/color]" % line
		elif state == "FINISHED":
			line = "[color=#8fe07d]%s[/color]" % line
		elif state == "ABANDONED":
			line = "[color=#a5a59a]%s[/color]" % line
		lines.append(line)
	leaderboard_rows.text = "\n".join(lines)


func show_race_event(message: String, event_type: StringName) -> void:
	var color := Color("ffe59c")
	match event_type:
		&"OVERTAKE":
			color = Color("ffd45e")
		&"NEW_LEADER":
			color = Color("fff07a")
		&"BEST_LAP":
			color = Color("8fe07d")
		&"FINISH":
			color = Color("fff1c2")
		&"RACE_END":
			color = Color("ffb06b")
	event_label.text = message
	event_label.add_theme_color_override("font_color", color)
	event_panel.visible = true
	_event_time_remaining = 2.4
