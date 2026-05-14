## analyzer_screen.gd
## Pantalla de carga: verifica si existe el JSON; si no, ejecuta Python en segundo plano.

extends Control

@onready var progress_bar:    ProgressBar = $VBox/ProgressBar
@onready var status_label:    Label       = $VBox/StatusLabel
@onready var song_name_label: Label       = $VBox/SongNameLabel

var _analysis_thread: Thread


func _ready() -> void:
	var display := GameState.selected_song_name.replace("_", " ").replace("-", " ").capitalize()
	song_name_label.text = "♪ " + display
	progress_bar.value   = 0.0

	await get_tree().process_frame
	await get_tree().process_frame

	_check_and_load()


func _check_and_load() -> void:
	var en         := (GameState.current_language == "en")
	var audio_path := GameState.selected_song_path
	var json_path  := audio_path.get_basename() + ".json"

	if FileAccess.file_exists(json_path):
		_load_beatmap(json_path)
		return

	status_label.text = "Analyzing with Python for the first time (this takes a few seconds)..." \
		if en else "Analizando con Python por primera vez (esto toma unos segundos)..."
	progress_bar.value = 40.0

	_analysis_thread = Thread.new()
	_analysis_thread.start(_run_python_script)


func _run_python_script() -> void:
	var output      := []
	var script_path := ProjectSettings.globalize_path("res://scripts/python_song_analyzer.py")
	
	print('hi')

	OS.execute("python", [script_path], output, true)

	print("Debugging OS.execute:")
	print(" - Script path: ", script_path)
	if output.is_empty():
		print(" - Python returned nothing (is it installed in PATH?)")
	else:
		print(" - PYTHON OUTPUT:")
		for line in output:
			print("   > ", line)

	call_deferred("_on_python_finished")


func _on_python_finished() -> void:
	_analysis_thread.wait_to_finish()

	var en         := (GameState.current_language == "en")
	var audio_path := GameState.selected_song_path
	var json_path  := audio_path.get_basename() + ".json"

	if FileAccess.file_exists(json_path):
		_load_beatmap(json_path)
	else:
		status_label.text     = "Error: Python failed to generate JSON. Check the console." \
			if en else "Error: Python fallo al generar el JSON. Revisa la consola."
		progress_bar.modulate = Color.RED


func _load_beatmap(json_path: String) -> void:
	var en := (GameState.current_language == "en")
	status_label.text = "Loading beatmap..." if en else "Cargando beatmap..."

	var file      := FileAccess.open(json_path, FileAccess.READ)
	var json_text := file.get_as_text()
	file.close()

	var parsed_data = JSON.parse_string(json_text)

	if parsed_data == null or typeof(parsed_data) != TYPE_DICTIONARY:
		status_label.text     = "Error: JSON file is corrupted." \
			if en else "Error: El archivo JSON esta corrupto."
		progress_bar.modulate = Color.RED
		return

	progress_bar.value = 100.0
	var note_count: int = parsed_data.get("note_count", 0)
	status_label.text  = "%d notes loaded. Starting game..." % note_count \
		if en else "%d notas cargadas. Iniciando juego..." % note_count

	GameState.current_beatmap = parsed_data

	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")
