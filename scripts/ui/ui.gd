extends CanvasLayer
## Interface do jogo (autoload "UI"): caixa de dialogo, menu de escolha, avisos,
## HUD (comida / sono / agua + vida) e escurecer a tela para dormir.
## Tudo e montado por codigo usando as caixas de assets/ui (recortadas da folha de menus).
##
## Uso:  await UI.say(["texto 1", "texto 2"])      var i = await UI.choose(["A", "B"], "Titulo")

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const TEX_DIALOG := preload("res://assets/ui/dialog_box.png")
const TEX_PANEL := preload("res://assets/ui/panel_menu.png")
const TEX_BAR := preload("res://assets/ui/panel_bar.png")
const TEX_TOAST := preload("res://assets/ui/panel_toast.png")

const INK := Color("1b2a5c")
const VIEW := Vector2(1536, 1024)

signal _advance
signal _chosen(index: int)

var _locks := 0
var busy: bool:
	get:
		return _locks > 0

# HUD
var _hud: Control
var _bars: Dictionary = {}       # nome -> ColorRect (preenchimento)
var _hp_fill: ColorRect
const BAR_W := 190.0

# dialogo
var _dialog: Control
var _dialog_text: Label
var _dialog_arrow: Label
var _typing := false
var _type_tween: Tween
var _dialog_active := false

# menu de escolha
var _menu: Control
var _menu_box: NinePatchRect
var _menu_title: Label
var _menu_rows: Array[Label] = []
var _menu_cursor: Polygon2D
var _menu_active := false
var _menu_options: Array = []
var _menu_sel := 0

# aviso
var _toast: Control
var _toast_label: Label
var _toast_tween: Tween

# fade (dormir)
var _fade: ColorRect


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_build_dialog()
	_build_menu()
	_build_toast()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	GameState.changed.connect(_refresh_hud)
	GameState.notice.connect(toast)
	show_hud(false)
	_refresh_hud()


# ============================== API ==============================
func lock() -> void:
	_locks += 1


func unlock() -> void:
	_locks = maxi(0, _locks - 1)


func show_hud(v: bool) -> void:
	_hud.visible = v


## Mostra uma ou mais falas; cada uma avanca com F / Enter / Espaco.
func say(lines) -> void:
	var arr: Array = lines if lines is Array else [lines]
	lock()
	_dialog_active = true
	_dialog.visible = true
	for line in arr:
		await _show_line(str(line))
	_dialog.visible = false
	_dialog_active = false
	unlock()


## Menu de escolha; devolve o indice escolhido ou -1 se cancelar (Esc).
func choose(options: Array, title: String = "") -> int:
	lock()
	_open_menu(options, title)
	var idx: int = await _chosen
	_menu.visible = false
	_menu_active = false
	unlock()
	return idx


func toast(text: String, seconds: float = 3.0) -> void:
	_toast_label.text = text
	var w := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x + 80.0
	_toast.size = Vector2(w, 64)
	_toast.position = Vector2((VIEW.x - w) / 2.0, 24)
	_toast_label.size = _toast.size
	_toast.visible = true
	_toast.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(seconds)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
	_toast_tween.tween_callback(func(): _toast.visible = false)


## Escurece (alpha 1) ou clareia (alpha 0) a tela por cima de tudo.
func fade_to(alpha: float, seconds: float) -> void:
	if seconds <= 0.0:
		_fade.color.a = alpha
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, seconds)
	await tw.finished


## Escurece a tela, espera e clareia (usado para dormir).
func blink(hold: float = 1.2, fade_time: float = 0.8) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, fade_time)
	tw.tween_interval(hold)
	tw.tween_property(_fade, "color:a", 0.0, fade_time)
	await tw.finished


# ============================== HUD ==============================
func _build_hud() -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud)
	var defs := [
		["food", "COMIDA", Color("e8a13a")],
		["sleep", "SONO", Color("8a78e8")],
		["thirst", "ÁGUA", Color("3aa6e8")],
	]
	var pw := 330.0
	var gap := 24.0
	var x0 := (VIEW.x - (pw * 3.0 + gap * 2.0)) / 2.0
	for i in defs.size():
		var d: Array = defs[i]
		var x := x0 + i * (pw + gap)
		_bars[d[0]] = _make_bar(Vector2(x, 944), Vector2(pw, 64), d[1], d[2])
	# vida (canto superior esquerdo)
	_hp_fill = _make_bar(Vector2(20, 20), Vector2(pw, 64), "VIDA", Color("e04a4a"))


func _make_bar(pos: Vector2, size: Vector2, text: String, color: Color) -> ColorRect:
	var box := NinePatchRect.new()
	box.texture = TEX_BAR
	for side in ["left", "right", "top", "bottom"]:
		box.set("patch_margin_" + side, 20)
	box.position = pos
	box.size = size
	_hud.add_child(box)
	var lab := _label(text, 24)
	lab.position = Vector2(26, 18)
	box.add_child(lab)
	var bg := ColorRect.new()
	bg.color = Color(INK, 0.35)
	bg.position = Vector2(size.x - BAR_W - 28, 22)
	bg.size = Vector2(BAR_W, 20)
	box.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.set_meta("base_color", color)
	fill.position = bg.position
	fill.size = Vector2(BAR_W, 20)
	box.add_child(fill)
	return fill


func _refresh_hud() -> void:
	_set_fill(_bars["food"], GameState.food)
	_set_fill(_bars["sleep"], GameState.sleep)
	_set_fill(_bars["thirst"], GameState.thirst)
	_set_fill(_hp_fill, GameState.health)


func _set_fill(fill: ColorRect, value: float) -> void:
	fill.size.x = BAR_W * clampf(value, 0.0, 100.0) / 100.0
	fill.color = Color("d63a3a") if value < 25.0 else fill.get_meta("base_color")


# ============================ dialogo ============================
func _build_dialog() -> void:
	_dialog = Control.new()
	_dialog.size = Vector2(1280, 240)
	_dialog.position = Vector2((VIEW.x - 1280.0) / 2.0, 690)
	_dialog.visible = false
	add_child(_dialog)
	var box := NinePatchRect.new()
	box.texture = TEX_DIALOG
	for side in ["left", "right", "top", "bottom"]:
		box.set("patch_margin_" + side, 36)
	box.size = _dialog.size
	_dialog.add_child(box)
	_dialog_text = _label("", 32)
	_dialog_text.position = Vector2(64, 40)
	_dialog_text.size = Vector2(1152, 160)
	_dialog_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dialog.add_child(_dialog_text)
	_dialog_arrow = _label("[F]", 24)
	_dialog_arrow.position = Vector2(1130, 192)
	_dialog_arrow.visible = false
	_dialog.add_child(_dialog_arrow)


func _show_line(text: String) -> void:
	_dialog_text.text = text
	_dialog_text.visible_characters = 0
	_dialog_arrow.visible = false
	_typing = true
	if _type_tween:
		_type_tween.kill()
	var n := text.length()
	_type_tween = create_tween()
	_type_tween.tween_property(_dialog_text, "visible_characters", n, maxf(0.05, n * 0.016))
	_type_tween.finished.connect(_on_typed)
	while true:
		await _advance
		if _typing:  # primeiro F: completa o texto
			_type_tween.kill()
			_dialog_text.visible_characters = -1
			_on_typed()
		else:
			break


func _on_typed() -> void:
	_typing = false
	_dialog_arrow.visible = true


# ============================ menu ============================
func _build_menu() -> void:
	_menu = Control.new()
	_menu.visible = false
	add_child(_menu)
	_menu_box = NinePatchRect.new()
	_menu_box.texture = TEX_PANEL
	for side in ["left", "right", "top", "bottom"]:
		_menu_box.set("patch_margin_" + side, 30)
	_menu.add_child(_menu_box)
	_menu_title = _label("", 32)
	_menu.add_child(_menu_title)
	_menu_cursor = Polygon2D.new()
	_menu_cursor.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 24), Vector2(18, 12)])
	_menu_cursor.color = INK
	_menu.add_child(_menu_cursor)


func _open_menu(options: Array, title: String) -> void:
	_menu_options = options
	_menu_sel = 0
	for r in _menu_rows:
		r.queue_free()
	_menu_rows.clear()
	var row_h := 52.0
	var width := 0.0
	if title != "":
		width = FONT.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x
	for o in options:
		width = maxf(width, FONT.get_string_size(str(o), HORIZONTAL_ALIGNMENT_LEFT, -1, 32).x)
	var w := width + 150.0
	var top := 36.0 + (56.0 if title != "" else 0.0)
	var h := top + options.size() * row_h + 30.0
	_menu_box.size = Vector2(w, h)
	_menu.size = Vector2(w, h)
	_menu.position = Vector2(VIEW.x - w - 90.0, 640.0 - h)
	_menu_title.text = title
	_menu_title.visible = title != ""
	_menu_title.position = Vector2(56, 30)
	for i in options.size():
		var lab := _label(str(options[i]), 32)
		lab.position = Vector2(92, top + i * row_h)
		_menu.add_child(lab)
		_menu_rows.append(lab)
	_menu.set_meta("top", top)
	_menu.set_meta("row_h", row_h)
	_place_cursor()
	_menu.visible = true
	_menu_active = true


func _place_cursor() -> void:
	var top: float = _menu.get_meta("top")
	var row_h: float = _menu.get_meta("row_h")
	_menu_cursor.position = Vector2(52, top + _menu_sel * row_h + 6)


# ============================ entrada ============================
func _input(event: InputEvent) -> void:
	if _menu_active:
		if event.is_action_pressed("move_up", true):
			_menu_sel = (_menu_sel - 1 + _menu_options.size()) % _menu_options.size()
			_place_cursor()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("move_down", true):
			_menu_sel = (_menu_sel + 1) % _menu_options.size()
			_place_cursor()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("interact") and not event.is_echo():
			get_viewport().set_input_as_handled()
			_chosen.emit(_menu_sel)
		elif event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_chosen.emit(-1)
	elif _dialog_active:
		if event.is_action_pressed("interact") and not event.is_echo():
			get_viewport().set_input_as_handled()
			_advance.emit()


# ============================ aviso ============================
func _build_toast() -> void:
	_toast = Control.new()
	_toast.visible = false
	add_child(_toast)
	var box := NinePatchRect.new()
	box.texture = TEX_TOAST
	for side in ["left", "right", "top", "bottom"]:
		box.set("patch_margin_" + side, 20)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast.add_child(box)
	_toast_label = _label("", 24)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)


# ============================ util ============================
func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l
