## song_select.gd
## Obtiene la lista de canciones desde el servidor FastAPI.
extends Control

@onready var bgm_player: AudioStreamPlayer = $BGMPlayer
@onready var song_list:         ItemList = $CyberPanel/VBox/SongList
@onready var play_button:       Button   = $CyberPanel/VBox/PlayButton
@onready var song_name_label:   Label    = $CyberPanel/VBox/SongNameLabel
@onready var http:              HTTPRequest = $HTTPRequest
@onready var settings_panel: Panel = $SettingsPanel
@onready var settings_close: Button = $SettingsCerrar
@onready var title: Label = $CyberPanel/VBox/SubtitleLabel
@onready var download_music_button: Button = $CyberPanel/VBox/DownloadButton
@onready var quit_button: Button = $CyberPanel/VBox/QuitButton
@onready var settings_button: Button = $CyberPanel/VBox/SettingsButton
@onready var colorblind_label: Label = $SettingsPanel/LabelDaltonismo
@onready var volume_label: Label = $SettingsPanel/LabelVolumen
@onready var close_settings: Button = $SettingsCerrar
@onready var volume_slider: HSlider = $SettingsPanel/HSlider
@onready var two_player_button: Button = $CyberPanel/VBox/TwoPlayerButton
@onready var instructions_label: Label = $CyberPanel/VBox/InstructionsLabel
@onready var english_switch: CheckButton = $SettingsPanel/EnglishSwitch

const SERVER := "https://web-production-133f0.up.railway.app"

var song_files: Array = []
var _loading_beatmap := false
var loaded_songs: int = 0
var default_volume_level: float = 0.1
var english_mode: bool = false


func _ready() -> void:
	play_button.disabled = true
	song_name_label.text = "Cargando canciones..."

	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(default_volume_level))
	volume_slider.value = default_volume_level

	song_list.item_selected.connect(_on_song_selected)
	play_button.pressed.connect(_on_play_pressed)

	if download_music_button:
		download_music_button.pressed.connect(_on_download_pressed)

	if two_player_button:
		two_player_button.pressed.connect(_on_two_player_toggled)

	# ── Restaurar idioma guardado ──────────────────────────────────────────────
	# GameState.current_language persiste entre escenas, así que solo hay que
	# leerlo y aplicarlo. El toggle también se sincroniza para que refleje
	# el estado real sin disparar la señal (block_signals).
	english_mode = (GameState.current_language == "en")
	if english_switch != null:
		english_switch.set_block_signals(true)
		english_switch.button_pressed = english_mode
		english_switch.set_block_signals(false)

	_apply_language()
	_update_two_player_button()
	_fetch_songs()


# ── Idioma ────────────────────────────────────────────────────────────────────

## Aplica todos los textos de la UI según el idioma actual en GameState.
func _apply_language() -> void:
	var en := (GameState.current_language == "en")

	title.text                  = "Select Song"          if en else "Seleccionar Cancion"
	play_button.text            = "Play"                  if en else "Jugar"
	download_music_button.text  = "Download Music"        if en else "Descargar Musica"
	colorblind_label.text       = "Colorblind Mode"       if en else "Modo Daltonismo"
	volume_label.text           = "Volume"                if en else "Volumen"
	close_settings.text         = "Close"                 if en else "Cerrar"
	instructions_label.text     = "Controls: S  D  F  H  J  K" if en else "Teclas: S  D  F  H  J  K"

	# El label de canciones depende de cuántas haya cargadas
	if loaded_songs > 0:
		song_name_label.text = "%d song(s) found" % loaded_songs if en \
			else "%d cancion(es) encontrada(s)" % loaded_songs

	_update_two_player_button()


# ── Obtener lista de canciones ────────────────────────────────────────────────

func _fetch_songs() -> void:
	http.request_completed.connect(_on_songs_received, CONNECT_ONE_SHOT)
	http.request(SERVER + "/songs")


func _on_songs_received(_result, response_code, _headers, body) -> void:
	var en := (GameState.current_language == "en")

	if response_code != 200:
		song_name_label.text = "Could not connect to server." if en else "No se pudo conectar al servidor."
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or not parsed.has("songs"):
		song_name_label.text = "Invalid server response." if en else "Respuesta invalida del servidor."
		return

	song_files = parsed["songs"]
	song_list.clear()

	if song_files.is_empty():
		song_name_label.text = "No songs. Download some first." if en else "No hay canciones. Descarga alguna primero."
		return

	for song in song_files:
		song_list.add_item(song["name"].replace("_", " ").replace("-", " ").capitalize())

	loaded_songs = song_files.size()
	song_name_label.text = "%d song(s) found" % loaded_songs if en \
		else "%d cancion(es) encontrada(s)" % loaded_songs


# ── Selección ─────────────────────────────────────────────────────────────────

func _on_song_selected(index: int) -> void:
	play_button.disabled = false
	song_name_label.text = "♪ " + song_files[index]["name"]
	_animate_active_play_button()


# ── Play ──────────────────────────────────────────────────────────────────────

func _animate_active_play_button():
	
	play_button.pivot_offset = play_button.size / 2.0
	# Detener cualquier animación previa si existe
	var tw = create_tween().set_loops() # Bucle infinito
	
	# El botón pasará de su color normal a uno mucho más brillante (HDR)
	# Esto creará un efecto de "resplandor" que sube y baja
	tw.tween_property(play_button, "self_modulate", Color(2.0, 2.0, 2.0, 1.0), 0.8)
	tw.tween_property(play_button, "self_modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8)
	
	# Efecto extra: Un sutil cambio de escala
	var tw_scale = create_tween().set_loops()
	tw_scale.tween_property(play_button, "scale", Vector2(1.008, 1.008), 0.4).set_trans(Tween.TRANS_SINE)
	tw_scale.tween_property(play_button, "scale", Vector2(1.0, 1.0), 0.4).set_trans(Tween.TRANS_SINE)

func _on_play_pressed() -> void:
	bgm_player.stop()
	if _loading_beatmap:
		return

	var sel := song_list.get_selected_items()
	if sel.is_empty():
		return

	var en       := (GameState.current_language == "en")
	var song     := song_files[sel[0]] as Dictionary
	var filename := song["file"] as String

	play_button.disabled = true
	song_name_label.text = "Loading beatmap..." if en else "Cargando beatmap..."
	_loading_beatmap     = true

	var url := SERVER + "/songs/" + filename.uri_encode() + "/beatmap"
	http.request_completed.connect(_on_beatmap_received.bind(filename), CONNECT_ONE_SHOT)
	http.request(url)


func _on_beatmap_received(_result, response_code, _headers, body, filename: String) -> void:
	var en := (GameState.current_language == "en")

	if response_code != 200:
		song_name_label.text = "Error getting beatmap." if en else "Error al obtener beatmap."
		play_button.disabled  = false
		_loading_beatmap      = false
		return

	var beatmap = JSON.parse_string(body.get_string_from_utf8())
	if beatmap == null:
		song_name_label.text = "Invalid beatmap." if en else "Beatmap invalido."
		play_button.disabled  = false
		_loading_beatmap      = false
		return

	GameState.current_beatmap = beatmap
	song_name_label.text      = "Loading audio..." if en else "Cargando audio..."

	http.request_completed.connect(_on_audio_received.bind(filename), CONNECT_ONE_SHOT)
	http.request(SERVER + "/songs/" + filename.uri_encode() + "/audio")


func _on_audio_received(_result, response_code, _headers, body, filename: String) -> void:
	_loading_beatmap = false
	var en := (GameState.current_language == "en")

	if response_code != 200:
		song_name_label.text = "Error loading audio." if en else "Error al cargar audio."
		play_button.disabled  = false
		return

	var stream := AudioStreamMP3.new()
	stream.data = body

	GameState.selected_stream    = stream
	GameState.selected_song_name = filename.get_basename()
	GameState.selected_song_path = SERVER + "/songs/" + filename

	get_tree().change_scene_to_file("res://scenes/gameplay.tscn")


# ── Botón de descarga ─────────────────────────────────────────────────────────

func _on_download_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/download_screen.tscn")


# ── 2 Jugadores ───────────────────────────────────────────────────────────────

func _on_two_player_toggled() -> void:
	GameState.two_player_mode = not GameState.two_player_mode
	_update_two_player_button()


func _update_two_player_button() -> void:
	if two_player_button == null:
		return
		
	var en := (GameState.current_language == "en")
	
	if GameState.two_player_mode:
		two_player_button.text     = ("👥 2 Players: ON"   if en else "👥 2 Jugadores: ON")
		two_player_button.modulate = Color(0.3, 1.0, 0.3)
	else:
		two_player_button.text     = ("👤 2 Players: OFF"  if en else "👤 2 Jugadores: OFF")
		two_player_button.modulate = Color(1.0, 1.0, 1.0)


# ── Settings ──────────────────────────────────────────────────────────────────

func _on_settings_button_pressed() -> void:
	settings_panel.visible = not settings_panel.visible
	settings_close.visible = not settings_close.visible


func _on_settings_cerrar_pressed() -> void:
	settings_panel.visible = false
	settings_close.visible = false


func _on_h_slider_value_changed(value: float) -> void:
	var bus_index := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_index, linear_to_db(value))


func _on_check_button_toggled(toggled_on: bool) -> void:
	GameState.colorblind_mode = toggled_on
	var color_rect = ScreenFilter.get_node("ColorRect")
	color_rect.material.set_shader_parameter("is_active", toggled_on)


# ── Cambio de idioma ──────────────────────────────────────────────────────────

func _on_button_pressed() -> void:
	if GameState.current_language == "es":
		GameState.current_language = "en"
	else:
		GameState.current_language = "es"
	english_mode = (GameState.current_language == "en")
	_apply_language()


func _on_english_switch_toggled(toggled_on: bool) -> void:
	english_mode               = toggled_on
	GameState.current_language = "en" if toggled_on else "es"
	_apply_language()
