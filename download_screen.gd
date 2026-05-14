## download_screen.gd
extends Control

@onready var search_field:    LineEdit    = $VBox/SearchField
@onready var search_button:   Button      = $VBox/SearchButton
@onready var status_label:    Label       = $VBox/StatusLabel
@onready var back_button:     Button      = $VBox/BackButton
@onready var progress_bar:    ProgressBar = $VBox/ProgressBar
@onready var results_list:    ItemList    = $VBox/ResultsList
@onready var download_button: Button      = $VBox/DownloadButton
@onready var http:            HTTPRequest = $HTTPRequest
@onready var title_label:     Label       = $Label
@onready var search_hint:     Label       = $VBox/Label

const SERVER := "https://web-production-133f0.up.railway.app"

var _search_cache: Array  = []
var _selected_id:  String = ""
var _last_query:   String = ""
var _busy:         bool   = false


func _ready() -> void:
	search_button.pressed.connect(_on_search_pressed)
	back_button.pressed.connect(_on_back_pressed)
	download_button.pressed.connect(_on_download_pressed)
	results_list.item_selected.connect(_on_result_selected)

	progress_bar.visible     = false
	download_button.disabled = true

	_apply_language()


func _apply_language() -> void:
	var en := (GameState.current_language == "en")

	if title_label:
		title_label.text      = "Song Search"          if en else "Buscador de Canciones"
	if search_hint:
		search_hint.text      = ""  # nodo Label vacío en la escena, lo dejamos vacío
	search_field.placeholder_text = "Search songs..."  if en else "Buscar Canciones"
	search_button.text        = "Search"               if en else "Buscar"
	download_button.text      = "Download Selected"    if en else "Descarga Seleccionada"
	back_button.text          = "Back"                 if en else "Regresar"
	status_label.text         = "Type a genre or name and press Search." \
		if en else "Escribe un genero o nombre y presiona Buscar."


# ── BUSQUEDA ──────────────────────────────────────────────────────────────────

func _on_search_pressed() -> void:
	var en    := (GameState.current_language == "en")
	var query := search_field.text.strip_edges()

	if query.is_empty():
		status_label.text = "Write something to search." if en else "Escribe algo para buscar."
		return
	if _busy:
		return

	_last_query = query
	_search_cache.clear()
	_selected_id = ""
	results_list.clear()
	download_button.disabled = true

	_set_busy(true)
	status_label.text = "Searching '%s'..." % query if en else "Buscando '%s'..." % query

	var url := SERVER + "/search?query=" + query.uri_encode() + "&limit=10"
	http.request_completed.connect(_on_search_completed, CONNECT_ONE_SHOT)
	http.request(url)


func _on_search_completed(_result, response_code, _headers, body) -> void:
	var en := (GameState.current_language == "en")
	_set_busy(false)
	results_list.clear()

	if response_code != 200:
		status_label.text = "Could not connect to server." if en else "Error al conectar con el servidor."
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or not parsed.has("results"):
		status_label.text = "Invalid response." if en else "Respuesta invalida."
		return

	_search_cache = parsed["results"]

	if _search_cache.is_empty():
		status_label.text = "No results for '%s'." % _last_query \
			if en else "Sin resultados para '%s'." % _last_query
		return

	for track: Dictionary in _search_cache:
		var mins  := int(track["duration"]) / 60
		var secs  := int(track["duration"]) % 60
		var label := "%s — %s  (%d:%02d)" % [
			track["name"], track["artist"], mins, secs
		]
		results_list.add_item(label)

	status_label.text = "%d result(s) for '%s'" % [_search_cache.size(), _last_query] \
		if en else "%d resultado(s) para '%s'" % [_search_cache.size(), _last_query]


# ── SELECCION ─────────────────────────────────────────────────────────────────

func _on_result_selected(index: int) -> void:
	var en := (GameState.current_language == "en")
	if index < 0 or index >= _search_cache.size():
		return
	var track: Dictionary = _search_cache[index]
	_selected_id          = str(track["id"])
	status_label.text     = "Selected: %s — %s" % [track["name"], track["artist"]] \
		if en else "Seleccionado: %s — %s" % [track["name"], track["artist"]]
	download_button.disabled = false


# ── DESCARGA ──────────────────────────────────────────────────────────────────

func _on_download_pressed() -> void:
	var en := (GameState.current_language == "en")
	if _selected_id.is_empty() or _busy:
		return

	var track: Dictionary = _search_cache.filter(
		func(t): return str(t["id"]) == _selected_id
	)[0]

	_set_busy(true)
	status_label.text        = "Downloading '%s'..." % track["name"] \
		if en else "Descargando '%s'..." % track["name"]
	download_button.disabled = true

	var url := SERVER + "/download/" + _selected_id
	http.request_completed.connect(_on_download_completed, CONNECT_ONE_SHOT)
	http.timeout = 120.0
	http.request(url, [], HTTPClient.METHOD_POST)


func _on_download_completed(_result, response_code, _headers, body) -> void:
	var en := (GameState.current_language == "en")
	_set_busy(false)

	if response_code != 200:
		status_label.text = "Download error (code %d)." % response_code \
			if en else "Error durante la descarga (codigo %d)." % response_code
		download_button.disabled = false
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null:
		status_label.text = "Invalid server response." if en else "Respuesta invalida del servidor."
		return

	var status: String = parsed.get("status", "")

	if status == "ok":
		status_label.text        = "Song downloaded! It now appears in the list." \
			if en else "Canción descargada. Ya aparece en la lista."
		download_button.disabled = true
		status_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		status_label.add_theme_font_size_override("font_size", status_label.get_theme_font_size("font_size") + 1)
	elif status == "already_exists":
		status_label.text        = "This song was already downloaded." \
			if en else "La cancion ya estaba descargada."
		download_button.disabled = true
	else:
		status_label.text        = "Unexpected server error." \
			if en else "Error inesperado del servidor."
		download_button.disabled = false


# ── HELPERS ───────────────────────────────────────────────────────────────────

func _set_busy(busy: bool) -> void:
	_busy                   = busy
	search_button.disabled  = busy
	search_field.editable   = not busy
	back_button.disabled    = busy
	progress_bar.visible    = busy


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/song_select.tscn")
