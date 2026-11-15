extends Control
## Cutscene inicial: (1) o cientista fala com a nave no laboratorio e prepara o lancamento;
## (2) video pre-renderizado do lancamento (ja traz a contagem 3-2-1); depois entra no jogo.
## Esc pula a cutscene (ou o video). F / Enter / Espaco avancam os dialogos.
##
## O Godot so toca video Ogg Theora (.ogv). Coloque o video convertido em VIDEO_PATH.
## Se o arquivo nao existir, a cutscene segue direto para o jogo.

const BG := preload("res://assets/rooms/laboratorio.png")
const SCIENTIST := preload("res://assets/scientist/scientist_up.png")
const SHIP := preload("res://assets/vehicles/nave_transparente.png")
const PANEL := preload("res://assets/ui/panel_menu.png")
const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const VIDEO_PATH := "res://assets/videos/spaceshiplaunch.ogv"
const GAME_SCENE := "res://scenes/game.tscn"
const INK := Color("1b2a5c")

## [quem fala, texto]  (textos de exemplo: troque a vontade)
const LINES := [
	["CIENTISTA", "Central da Terra chamando a nave. Todos os sistemas estão verdes aqui no controle."],
	["NAVE", "Aqui é a nave. Recebendo você forte e claro, Terra. Tripulação a bordo e em posição."],
	["CIENTISTA", "Ótimo. Vou rodar a checagem final antes do lançamento: reator, propulsão e comunicações."],
	["NAVE", "Reator estável. Propulsores prontos. Comunicações limpas."],
	["CIENTISTA", "Lembrem-se: eu acompanho tudo daqui e aviso de qualquer perigo. Vocês cuidam da nave e da missão."],
	["NAVE", "Entendido. Nós fazemos as manobras, você faz as previsões."],
	["CIENTISTA", "Iniciando a contagem final de lançamento. Boa sorte, tripulação."],
]

var _skip := false
var _scientist: TextureRect
var _comm: Control
var _comm_label: Label
var _bob: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UI.show_hud(false)
	GameState.running = false
	_build()
	Audio.play_room("laboratorio")
	_run()


func _build() -> void:
	var bg := TextureRect.new()
	bg.texture = BG
	bg.position = Vector2.ZERO
	bg.size = Vector2(1536, 1024)
	bg.stretch_mode = TextureRect.STRETCH_KEEP
	add_child(bg)

	_scientist = TextureRect.new()
	_scientist.texture = SCIENTIST
	_scientist.stretch_mode = TextureRect.STRETCH_KEEP
	_scientist.position = Vector2(768.0 - SCIENTIST.get_width() * 0.5, 600.0 - SCIENTIST.get_height())
	add_child(_scientist)

	# janela de comunicacao com a nave (canto superior direito)
	_comm = Control.new()
	_comm.position = Vector2(1040, 60)
	_comm.size = Vector2(440, 270)
	_comm.modulate.a = 0.55
	add_child(_comm)
	var box := NinePatchRect.new()
	box.texture = PANEL
	for side in ["left", "right", "top", "bottom"]:
		box.set("patch_margin_" + side, 28)
	box.size = _comm.size
	_comm.add_child(box)
	var ship := TextureRect.new()
	ship.texture = SHIP
	ship.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ship.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ship.position = Vector2(30, 70)
	ship.size = Vector2(380, 170)
	_comm.add_child(ship)
	_comm_label = _label(tr("NAVE  -  SINAL"), 24)
	_comm_label.position = Vector2(34, 28)
	_comm.add_child(_comm_label)

	var hint := _label(tr("Esc: pular cutscene"), 16)
	hint.add_theme_color_override("font_color", Color("dfe9ff"))
	hint.add_theme_color_override("font_outline_color", INK)
	hint.add_theme_constant_override("outline_size", 6)
	hint.position = Vector2(20, 990)
	add_child(hint)


func _run() -> void:
	await UI.fade_to(0.0, 0.8)
	await get_tree().create_timer(0.5).timeout
	for line in LINES:
		if _skip:
			break
		await _speak(line[0], line[1])
	await UI.fade_to(1.0, 0.6)
	await UI.play_video(VIDEO_PATH, false)
	GameState.running = false
	get_tree().change_scene_to_file(GAME_SCENE)


func _speak(who: String, text: String) -> void:
	var ship_talks := who == "NAVE"
	_comm.modulate.a = 1.0 if ship_talks else 0.55
	_set_bob(not ship_talks)
	await UI.say("%s: %s" % [tr(who), tr(text)])
	_set_bob(false)


# o cientista balança de leve enquanto fala
func _set_bob(on: bool) -> void:
	if _bob != null:
		_bob.kill()
	var y := 600.0 - SCIENTIST.get_height()
	_scientist.position.y = y
	if on:
		_bob = create_tween().set_loops()
		_bob.tween_property(_scientist, "position:y", y - 6.0, 0.25)
		_bob.tween_property(_scientist, "position:y", y, 0.25)


func _unhandled_input(event: InputEvent) -> void:
	# Esc pula os dialogos (o video e pulado pela propria UI)
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		_do_skip()


func _do_skip() -> void:
	_skip = true
	# fecha o dialogo aberto (primeiro completa o texto, depois avanca)
	for i in 2:
		if UI._dialog_active:
			UI._advance.emit()


func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l
