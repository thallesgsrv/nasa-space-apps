extends Control
## Menu inicial: usa a primeira tela da folha de menus (cidade ao fundo, caixa de opcoes).
## W/S ou setas escolhem; F / Enter / Espaco confirmam.

const BG := preload("res://assets/ui/start_bg.png")
const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const INK := Color("1b2a5c")
const GAME_SCENE := "res://scenes/cutscene_intro.tscn"   # cutscene inicial; depois dela entra no jogo

# interior da caixa de texto desenhada no start_bg.png (x, y, largura, altura)
const BOX := Rect2(113, 362, 610, 276)
const OPTIONS := ["INICIAR", "MULTIPLAYER LAN", "OPÇÕES"]
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const SPACING := 76.0   # distancia entre as opcoes (cabem 3 na caixa do menu)

var _sel := 0
var _labels: Array[Label] = []
var _hint: Label
var _cursor: Polygon2D
var _starting := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Audio.stop_music()
	UI.show_hud(false)
	GameState.running = false
	var bg := TextureRect.new()
	bg.texture = BG
	bg.position = Vector2.ZERO
	bg.size = Vector2(1536, 1024)
	bg.stretch_mode = TextureRect.STRETCH_KEEP
	add_child(bg)
	for i in OPTIONS.size():
		var lab := Label.new()
		lab.text = tr(OPTIONS[i])
		_labels.append(lab)
		lab.add_theme_font_override("font", FONT)
		lab.add_theme_font_size_override("font_size", 48)
		lab.add_theme_color_override("font_color", INK)
		lab.position = Vector2(BOX.position.x + 130.0, BOX.position.y + 44.0 + i * SPACING)
		add_child(lab)
	_cursor = Polygon2D.new()
	_cursor.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 40), Vector2(30, 20)])
	_cursor.color = INK
	add_child(_cursor)
	var hint := Label.new()
	hint.text = tr("W / S: escolher     F ou Enter: confirmar")
	hint.add_theme_font_override("font", FONT)
	hint.add_theme_font_size_override("font_size", 24)
	hint.add_theme_color_override("font_color", Color("dfe9ff"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, 962)
	hint.size = Vector2(1536, 30)
	add_child(hint)
	_hint = hint
	_place_cursor()


func _place_cursor() -> void:
	_cursor.position = Vector2(BOX.position.x + 62.0, BOX.position.y + 46.0 + _sel * SPACING + 4.0)


# _unhandled_input: se um dialogo estiver aberto, a UI ja consumiu a tecla antes.
func _unhandled_input(event: InputEvent) -> void:
	if _starting or UI.busy:
		return
	if event.is_action_pressed("move_up", true):
		_sel = (_sel - 1 + OPTIONS.size()) % OPTIONS.size()
		_place_cursor()
		Audio.sfx("select", 1.0, 0.35)
	elif event.is_action_pressed("move_down", true):
		_sel = (_sel + 1) % OPTIONS.size()
		_place_cursor()
		Audio.sfx("select", 1.0, 0.35)
	elif event.is_action_pressed("interact") and not event.is_echo():
		Audio.sfx("select", 1.35, 0.5)
		if _sel == 0:
			_start_game()
		elif _sel == 1:
			_open_lobby()
		else:
			_options()


# OPCOES: escolher o idioma (Portugues / English). A escolha fica salva.
func _options() -> void:
	await UI.options_menu()
	for k in _labels.size():
		_labels[k].text = tr(OPTIONS[k])
	_hint.text = tr("W / S: escolher     F ou Enter: confirmar")


func _open_lobby() -> void:
	_starting = true
	await UI.fade_to(1.0, 0.3)
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _start_game() -> void:
	_starting = true
	GameState.reset()
	# tela inicial: o planejamento da missao (CML 1-9) vem ANTES da cutscene; depois o jogo comeca na estacao
	if not MissionState.planning_disabled:
		await MissionState.run_planning()
	await UI.fade_to(1.0, 0.5)
	get_tree().change_scene_to_file(GAME_SCENE)
