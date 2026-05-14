## gameplay.gd
extends Node2D

# ── Nodos ────────────────────────────────────────────────────────────────────
@onready var audio_player: AudioStreamPlayer = $AudioStreamPlayer
@onready var notes_root:   Node2D            = $Notes
@onready var progress_bar: ProgressBar       = $UI/SongProgress
@onready var hit_line:     Node2D            = $HitLine

@onready var score_label_p1: Label = $UI/P1/ScoreLabel
@onready var combo_label_p1: Label = $UI/P1/ComboLabel
@onready var judge_label_p1: Label = $UI/P1/JudgeLabel

@onready var score_label_p2: Label = $UI/P2/ScoreLabel
@onready var combo_label_p2: Label = $UI/P2/ComboLabel
@onready var judge_label_p2: Label = $UI/P2/JudgeLabel

# ── Constantes ────────────────────────────────────────────────────────────────
const LANE_COUNT     := 6
const NOTE_FALL_TIME := 2.0
const NOTE_SPAWN_Y   := -60.0
const NOTE_SCENE     := preload("res://scenes/note.tscn")
const RECEPTOR_SCENE := preload("res://scenes/lane_receptor.tscn")

const LANE_COLORS := [
	Color(1.00, 0.30, 0.30),
	Color(1.00, 0.60, 0.20),
	Color(1.00, 1.00, 0.20),
	Color(0.20, 0.80, 1.00),
	Color(0.50, 0.50, 1.00),
	Color(0.80, 0.30, 1.00),
]

const P1_LANES   := [0, 1, 2]
const P2_LANES   := [3, 4, 5]
const P1_ACTIONS := ["lane_0", "lane_1", "lane_2"]
const P2_ACTIONS := ["lane_3", "lane_4", "lane_5"]

# ── Estado ────────────────────────────────────────────────────────────────────
var pending_notes: Array = []
var active_notes:  Array = []

var score_p1:     int = 0
var combo_p1:     int = 0
var max_combo_p1: int = 0
var hit_p1:       int = 0
var miss_p1:      int = 0

var score_p2:     int = 0
var combo_p2:     int = 0
var max_combo_p2: int = 0
var hit_p2:       int = 0
var miss_p2:      int = 0

var total_notes: int = 0

var note_fall_speed: float = 0.0
var hit_y:           float = 0.0
var miss_y:          float = 0.0
var lane_x:          Array = []

var game_started := false
var game_ended   := false
var two_player   := false

var _receptors: Array = []


func _ready() -> void:
	two_player = GameState.two_player_mode

	var vp_h := get_viewport_rect().size.y
	var vp_w := get_viewport_rect().size.x
	hit_y  = vp_h - 110.0
	miss_y = vp_h + 80.0
	note_fall_speed = (hit_y - NOTE_SPAWN_Y) / NOTE_FALL_TIME

	hit_line.position.y = hit_y

	var lane_w := vp_w / float(LANE_COUNT)
	for i in LANE_COUNT:
		lane_x.append(lane_w * i + lane_w * 0.5)

	active_notes.resize(LANE_COUNT)
	for i in LANE_COUNT:
		active_notes[i] = []

	judge_label_p1.modulate.a = 0.0
	judge_label_p2.modulate.a = 0.0
	score_label_p1.text = "0"
	score_label_p2.text = "0"
	combo_label_p1.text = ""
	combo_label_p2.text = ""
	progress_bar.value  = 0.0

	$UI/P2.visible = two_player

	_draw_lane_lines(vp_w, vp_h)
	_draw_lane_receptors()

	var beatmap := GameState.current_beatmap
	if beatmap.is_empty():
		push_error("gameplay.gd: No hay beatmap en GameState.")
		return

	total_notes   = beatmap.get("note_count", 0)
	pending_notes = beatmap.get("notes", []).duplicate(true)

	audio_player.stream = GameState.selected_stream
	audio_player.play()
	game_started = true


func _draw_lane_lines(vp_w: float, vp_h: float) -> void:
	var lane_lines: Node2D = $LaneLines
	var lane_w := vp_w / float(LANE_COUNT)

	for i in LANE_COUNT + 1:
		var line := ColorRect.new()
		line.size     = Vector2(2, vp_h)
		line.position = Vector2(lane_w * i - 1.0, 0.0)
		line.color    = Color(0.25, 0.25, 0.35, 1.0)
		lane_lines.add_child(line)

	for i in LANE_COUNT:
		var bg := ColorRect.new()
		bg.size     = Vector2(lane_w - 2.0, vp_h)
		bg.position = Vector2(lane_w * i + 1.0, 0.0)
		var alpha: float = 0.04 if i % 2 == 0 else 0.07
		bg.color    = Color(LANE_COLORS[i].r, LANE_COLORS[i].g, LANE_COLORS[i].b, alpha)
		lane_lines.add_child(bg)

	if two_player:
		var divider := ColorRect.new()
		divider.size     = Vector2(4, vp_h)
		divider.position = Vector2(vp_w * 0.5 - 2.0, 0.0)
		divider.color    = Color(1.0, 1.0, 1.0, 0.3)
		lane_lines.add_child(divider)

	var key_names := ["S", "D", "F", "H", "J", "K"]
	for i in LANE_COUNT:
		var lbl := Label.new()
		lbl.text     = key_names[i]
		lbl.modulate = LANE_COLORS[i]
		lbl.position = Vector2(lane_x[i] - 10.0, vp_h - 68.0)
		lbl.add_theme_font_size_override("font_size", 18)
		lane_lines.add_child(lbl)


func _draw_lane_receptors() -> void:
	_receptors.clear()
	for i in LANE_COUNT:
		var receptor: Node2D = RECEPTOR_SCENE.instantiate()
		receptor.lane_color  = LANE_COLORS[i]
		receptor.lane_index  = i
		receptor.position    = Vector2(lane_x[i], 0.0)
		hit_line.add_child(receptor)
		_receptors.append(receptor)


func _process(_delta: float) -> void:
	if not game_started or game_ended:
		return

	if Input.is_action_just_pressed("ui_cancel"):
		audio_player.stop()
		get_tree().change_scene_to_file("res://scenes/song_select.tscn")
		return

	var t := audio_player.get_playback_position()
	var dur: float = GameState.current_beatmap.get("duration", 1.0)
	progress_bar.value = clampf(t / dur, 0.0, 1.0) * 100.0

	_spawn_pending(t)

	if two_player:
		_process_input_player(t, P1_ACTIONS, P1_LANES)
		_process_input_player(t, P2_ACTIONS, P2_LANES)
	else:
		_process_input_player(t, P1_ACTIONS + P2_ACTIONS, P1_LANES + P2_LANES)

	if not audio_player.playing and pending_notes.is_empty():
		_end_game()


func _process_input_player(t: float, actions: Array, lanes: Array) -> void:
	var pressed_lanes: Array = []
	for i in actions.size():
		if Input.is_action_just_pressed(actions[i]):
			pressed_lanes.append(lanes[i])

	if pressed_lanes.is_empty():
		return

	var is_p1 := lanes == P1_LANES

	# Evaluar cada carril presionado de forma independiente
	for lane in pressed_lanes:
		# Animación del receptor: siempre al presionar
		if lane < _receptors.size():
			_receptors[lane].animate_press()

		# Buscar nota hittable en este carril específico
		var has_hittable := false
		for note in active_notes[lane]:
			if is_instance_valid(note) and note.is_hittable(t):
				has_hittable = true
				break

		if has_hittable:
			# Hay nota en este carril — intentar atinarle
			_hit_lane(lane, t)
		else:
			# Carril vacío — miss por presionar al aire, rompe combo
			if is_p1 or not two_player:
				combo_p1 = 0
				miss_p1 += 1
				combo_label_p1.text = ""
			else:
				combo_p2 = 0
				miss_p2 += 1
				combo_label_p2.text = ""
			_show_judge_on_lane("MISS", Color(0.6, 0.6, 0.6), lane)


func _spawn_pending(song_time: float) -> void:
	while not pending_notes.is_empty():
		var next: Dictionary = pending_notes[0]
		if song_time >= next["time"] - NOTE_FALL_TIME:
			pending_notes.pop_front()
			_spawn_note(next["time"], next["lane"])
		else:
			break


func _spawn_note(beat_time: float, lane: int) -> void:
	var note: Node2D = NOTE_SCENE.instantiate()
	notes_root.add_child(note)
	note.lane       = lane
	note.beat_time  = beat_time
	note.fall_speed = note_fall_speed
	note.miss_y     = miss_y
	note.position   = Vector2(lane_x[lane], NOTE_SPAWN_Y)
	note.set_color(LANE_COLORS[lane])
	note.note_hit.connect(_on_note_hit)
	note.note_missed.connect(_on_note_missed)
	active_notes[lane].append(note)


func _hit_lane(lane: int, song_time: float) -> void:
	var best_note: Node2D = null
	var best_diff: float  = INF

	for note in active_notes[lane]:
		if is_instance_valid(note) and note.is_hittable(song_time):
			var d: float = abs(song_time - note.beat_time)
			if d < best_diff:
				best_diff = d
				best_note = note

	if best_note != null:
		best_note.try_hit(song_time)


func _is_p1_lane(lane: int) -> bool:
	return lane in P1_LANES


func _on_note_hit(lane: int, accuracy: float) -> void:
	active_notes[lane] = active_notes[lane].filter(func(n): return is_instance_valid(n))
	var is_p1 := _is_p1_lane(lane)

	if lane < _receptors.size():
		_receptors[lane].animate_hit(accuracy)

	var judge_text: String = "BAD"
	if   accuracy >= 0.95: judge_text = "PERFECT!"
	elif accuracy >= 0.55: judge_text = "GOOD"

	if is_p1 or not two_player:
		hit_p1   += 1
		combo_p1 += 1
		if combo_p1 > max_combo_p1:
			max_combo_p1 = combo_p1
		var pts := int(100.0 * accuracy * (1.0 + combo_p1 * 0.01))
		score_p1 += pts
		score_label_p1.text = str(score_p1)
		combo_label_p1.text = "x%d" % combo_p1 if combo_p1 > 1 else ""
	else:
		hit_p2   += 1
		combo_p2 += 1
		if combo_p2 > max_combo_p2:
			max_combo_p2 = combo_p2
		var pts := int(100.0 * accuracy * (1.0 + combo_p2 * 0.01))
		score_p2 += pts
		score_label_p2.text = str(score_p2)
		combo_label_p2.text = "x%d" % combo_p2 if combo_p2 > 1 else ""

	_show_judge_on_lane(judge_text, LANE_COLORS[lane], lane)


func _on_note_missed(lane: int) -> void:
	active_notes[lane] = active_notes[lane].filter(func(n): return is_instance_valid(n))
	var is_p1 := _is_p1_lane(lane)

	if is_p1 or not two_player:
		miss_p1  += 1
		combo_p1  = 0
		combo_label_p1.text = ""
	else:
		miss_p2  += 1
		combo_p2  = 0
		combo_label_p2.text = ""

	_show_judge_on_lane("MISS", Color(0.6, 0.6, 0.6), lane)


func _show_judge_on_lane(text: String, color: Color, lane: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.modulate = color
	# Usar fuente cyberpunk
	lbl.add_theme_font_override("font", preload("res://RhythmicHits.ttf"))
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.position = Vector2(lane_x[lane] - 50.0, hit_y - 40.0)
	lbl.scale = Vector2(0.5, 0.5) # Empieza pequeño
	lbl.pivot_offset = Vector2(50, 15) # Centro para que escale bien
	add_child(lbl)

	var tw := create_tween().set_parallel(true)
	# 1. Salto hacia arriba
	tw.tween_property(lbl, "position:y", lbl.position.y - 30.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	# 2. "Punch" de escala (se hace grande y vuelve)
	var stw = create_tween()
	stw.tween_property(lbl, "scale", Vector2(1.3, 1.3), 0.1)
	stw.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.1)
	# 3. Desvanecimiento
	tw.tween_property(lbl, "modulate:a", 0.0, 0.4).set_delay(0.2)
	tw.chain().tween_callback(lbl.queue_free)


func _end_game() -> void:
	if game_ended:
		return
	game_ended   = true
	game_started = false

	var accuracy_p1: float = float(hit_p1) / float(total_notes) if total_notes > 0 else 0.0
	var accuracy_p2: float = float(hit_p2) / float(total_notes) if total_notes > 0 else 0.0

	GameState.last_score       = score_p1
	GameState.last_max_combo   = max_combo_p1
	GameState.last_accuracy    = accuracy_p1
	GameState.last_hit_notes   = hit_p1
	GameState.last_total_notes = total_notes

	GameState.last_score_p2     = score_p2
	GameState.last_max_combo_p2 = max_combo_p2
	GameState.last_accuracy_p2  = accuracy_p2
	GameState.last_hit_notes_p2 = hit_p2

	await get_tree().create_timer(1.0).timeout
	get_tree().change_scene_to_file("res://scenes/results.tscn")
	
