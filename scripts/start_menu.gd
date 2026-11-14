extends Control
## Menu inicial: usa a primeira tela da folha de menus (cidade ao fundo, caixa de opcoes).
## W/S ou setas escolhem; F / Enter / Espaco confirmam.

const BG := preload("res://assets/ui/start_bg.png")
const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const INK := Color("1b2a5c")
const GAME_SCENE := "res://scenes/game.tscn"

# interior da caixa de texto desenhada no start_bg.png (x, y, largura, altura)
const BOX := Rect2(113, 362, 610, 276)
const OPTIONS := ["INICIAR", "OPÇÕES"]

var _sel := 0
var _cursor: Polygon2D
var _starting := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
		lab.text = OPTIONS[i]
		lab.add_theme_font_override("font", FONT)
		lab.add_theme_font_size_override("font_size", 48)
		lab.add_theme_color_override("font_color", INK)
		lab.position = Vector2(BOX.position.x + 130.0, BOX.position.y + 44.0 + i * 96.0)
		add_child(lab)
	_cursor = Polygon2D.new()
	_cursor.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 40), Vector2(30, 20)])
	_cursor.color = INK
	add_child(_cursor)
	var hint := Label.new()
	hint.text = "W / S: escolher     F ou Enter: confirmar"
	hint.add_theme_font_override("font", FONT)
	hint.add_theme_font_size_override("font_size", 24)
	hint.add_theme_color_override("font_color", Color("dfe9ff"))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.position = Vector2(0, 962)
	hint.size = Vector2(1536, 30)
	add_child(hint)
	_place_cursor()


func _place_cursor() -> void:
	_cursor.position = Vector2(BOX.position.x + 62.0, BOX.position.y + 46.0 + _sel * 96.0 + 4.0)


# _unhandled_input: se um dialogo estiver aberto, a UI ja consumiu a tecla antes.
func _unhandled_input(event: InputEvent) -> void:
	if _starting or UI.busy:
		return
	if event.is_action_pressed("move_up", true):
		_sel = (_sel - 1 + OPTIONS.size()) % OPTIONS.size()
		_place_cursor()
	elif event.is_action_pressed("move_down", true):
		_sel = (_sel + 1) % OPTIONS.size()
		_place_cursor()
	elif event.is_action_pressed("interact") and not event.is_echo():
		if _sel == 0:
			_start_game()
		else:
			UI.say([
				"Opções em breve.",
				"Controles: W A S D andam, F interage, I abre a mochila.",
			])


func _start_game() -> void:
	_starting = true
	GameState.reset()
	Mission.reset()
	await UI.fade_to(1.0, 0.5)
	get_tree().change_scene_to_file(GAME_SCENE)
