## video_background.gd
## Descarga frames del servidor y los muestra como slideshow animado en el fondo.
## Debe ser el primer hijo de la escena para que quede detrás de todo lo demás.

extends TextureRect

const SERVER         := "https://web-production-133f0.up.railway.app"
const BG_ALPHA       := 0.22    # Opacidad del fondo (0=invisible, 1=completo)
const FRAME_INTERVAL := 4.5     # Segundos entre frames
const FADE_DURATION  := 0.9     # Duración del crossfade entre frames

@onready var http:    HTTPRequest = $HTTPRequest
@onready var overlay: ColorRect   = $Overlay

var _frames:        Array = []
var _current_frame: int   = 0
var _frame_timer:   float = 0.0
var _playing:       bool  = false


func _ready() -> void:
	# FIX 1: Forzamos el tamaño a la resolución de la pantalla (ya que anchors falla en Node2D)
	size = get_viewport_rect().size 
	expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	
	# FIX 2: Usamos 'self_modulate' para no hacer invisible al Overlay accidentalmente
	self_modulate.a = 0.0   

	# Overlay oscuro semitransparente encima de los frames
	overlay.color = Color(0, 0, 0, 0.65)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)

	var song := GameState.selected_song_name
	if song.is_empty():
		return

	http.request_completed.connect(_on_response)
	var err := http.request(SERVER + "/video_bg/" + song.uri_encode())
	if err != OK:
		push_warning("video_background: no se pudo iniciar la petición HTTP.")


func _on_response(_result, code, _headers, body) -> void:
	if code != 200:
		push_warning("video_background: servidor respondió %d" % code)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed == null or not parsed.has("frames"):
		push_warning("video_background: respuesta inválida del servidor.")
		return

	# Decodificar cada frame base64 → ImageTexture
	for b64 in parsed["frames"]:
		var raw := Marshalls.base64_to_raw(b64)
		var img := Image.new()
		if img.load_jpg_from_buffer(raw) == OK:
			_frames.append(ImageTexture.create_from_image(img))

	if _frames.is_empty():
		push_warning("video_background: ningún frame se pudo decodificar.")
		return

	# Mostrar primer frame con fade-in suave (Animando self_modulate)
	texture  = _frames[0]
	_playing = true
	create_tween().tween_property(self, "self_modulate:a", BG_ALPHA, 1.5)

	print("video_background: %d frames cargados. Fuente: %s" % [
		_frames.size(), parsed.get("source", "?")
	])


func _process(delta: float) -> void:
	if not _playing or _frames.size() <= 1:
		return

	_frame_timer += delta
	if _frame_timer >= FRAME_INTERVAL:
		_frame_timer = 0.0
		_advance_frame()


func _advance_frame() -> void:
	_current_frame = (_current_frame + 1) % _frames.size()
	var next_tex: Texture2D = _frames[_current_frame]
	# Crossfade: bajar alfa → cambiar textura → subir alfa
	var tw := create_tween()
	tw.tween_property(self, "self_modulate:a", 0.0,      FADE_DURATION * 0.4)
	tw.tween_callback(func(): texture = next_tex)
	tw.tween_property(self, "self_modulate:a", BG_ALPHA, FADE_DURATION * 0.6)
