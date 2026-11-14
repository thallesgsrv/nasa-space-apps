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
const GRID := preload("res://scripts/ui/grid_screen.gd")

const INK := Color("1b2a5c")
const VIEW := Vector2(1536, 1024)

signal _advance
signal _chosen(index: int)
signal _panel_closed

var _locks := 0
var _video_active := false
var _video_skip := false
var realtime := false   # true: o tempo do jogo corre mesmo com menu aberto (minigame das valvulas)
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

# painel de texto (menu de missoes)
var _panel: Control
var _panel_text: Label
var _panel_active := false

# rastreador da missao (canto superior direito): aparece por um tempo e encolhe para "!" + losango
var _tracker: Control
var _tracker_label: Label
var _tracker_icon: Control
var _tracker_diamond: Polygon2D
var _tracker_mark: Label
var _tracker_open_left := 0.0
var _tracker_last := ""
const TRACKER_SHOW_TIME := 8.0

# alarme solar + tela piscando (CME)
var _solar_alarm: Label
var _flicker: ColorRect
var _ui_t := 0.0
var _panel_provider: Callable
var _panel_refresh := 0.0

# alarme do nucleo (contagem para explodir)
var _alarm: Label

# painel da viagem (Missao 2)
var _voyage: Control
var _voyage_title: Label
var _voyage_info: Label
var _voyage_bars: Dictionary = {}

# fade (dormir)
var _fade: ColorRect


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_hud()
	_build_dialog()
	_build_menu()
	_build_toast()
	_build_panel()
	_build_tracker()
	_build_voyage()
	_solar_alarm = _label("", 32)
	_solar_alarm.add_theme_color_override("font_outline_color", Color.WHITE)
	_solar_alarm.add_theme_constant_override("outline_size", 10)
	_solar_alarm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_solar_alarm.position = Vector2(0, 215)
	_solar_alarm.size = Vector2(VIEW.x, 44)
	_solar_alarm.visible = false
	add_child(_solar_alarm)
	_flicker = ColorRect.new()
	_flicker.color = Color(1, 1, 1, 0)
	_flicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flicker.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flicker)
	_alarm = _label("", 48)
	_alarm.add_theme_color_override("font_color", Color("e02020"))
	_alarm.add_theme_color_override("font_outline_color", Color.WHITE)
	_alarm.add_theme_constant_override("outline_size", 12)
	_alarm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_alarm.position = Vector2(0, 150)
	_alarm.size = Vector2(VIEW.x, 60)
	_alarm.visible = false
	add_child(_alarm)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	GameState.changed.connect(_refresh_hud)
	GameState.notice.connect(toast)
	Missions.changed.connect(_refresh_tracker)
	Voyage.changed.connect(_refresh_voyage)
	Solar.changed.connect(_refresh_solar)
	show_hud(false)
	_refresh_hud()


# ============================== API ==============================
func lock() -> void:
	_locks += 1


func unlock() -> void:
	_locks = maxi(0, _locks - 1)


func show_hud(v: bool) -> void:
	_hud.visible = v
	if _voyage != null:
		_refresh_voyage()
	if _tracker != null:
		_refresh_tracker()


## Painel grande de texto (menu de missoes); fecha com F / Esc / M.
func show_panel(text: String, provider: Callable = Callable()) -> void:
	lock()
	_panel_provider = provider
	_panel_refresh = 0.0
	_panel_text.text = provider.call() if provider.is_valid() else text
	_panel.visible = true
	_panel_active = true
	await _panel_closed
	_panel.visible = false
	_panel_active = false
	_panel_provider = Callable()
	unlock()


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


## Toca um video (.ogv) em tela cheia por cima do jogo. Esc / Enter / Espaco / F pulam.
## Escurece antes e DEIXA A TELA PRETA no fim: quem chamou decide quando clarear (UI.fade_to(0, t)).
## Se o arquivo nao existir, nao faz nada.
func play_video(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_warning("Video nao encontrado: %s (precisa ser .ogv)." % path)
		return
	lock()
	await fade_to(1.0, 0.5)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.size = VIEW
	add_child(black)
	var vp := VideoStreamPlayer.new()
	vp.stream = load(path)
	vp.expand = true
	vp.size = VIEW
	add_child(vp)
	move_child(black, _fade.get_index())  # video fica abaixo do fade (a UI usa o fade para as transicoes)
	move_child(vp, _fade.get_index())
	_video_skip = false
	_video_active = true
	vp.play()
	await get_tree().process_frame
	await get_tree().process_frame
	# mantem a proporcao do video (barras pretas se for 16:9)
	var tex := vp.get_video_texture()
	if tex != null and tex.get_height() > 0:
		var aspect := float(tex.get_width()) / float(tex.get_height())
		var w := VIEW.x
		var h := w / aspect
		if h > VIEW.y:
			h = VIEW.y
			w = h * aspect
		vp.size = Vector2(w, h)
		vp.position = Vector2((VIEW.x - w) / 2.0, (VIEW.y - h) / 2.0)
	await fade_to(0.0, 0.3)
	while vp.is_playing() and not _video_skip:
		await get_tree().process_frame
	vp.stop()
	await fade_to(1.0, 0.4)
	_video_active = false
	vp.queue_free()
	black.queue_free()
	unlock()


## Abre a tela de grade ("inventory" ou "storage"); feche com queue_free() no fim.
func open_grid(kind: String) -> Control:
	var g = GRID.new()
	g.configure(kind)
	add_child(g)
	move_child(g, _hud.get_index() + 1)  # fica atras do menu de escolha, dialogo e avisos
	return g


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
	_fade.color = Color(0, 0, 0, _fade.color.a)
	if seconds <= 0.0:
		_fade.color.a = alpha
		return
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, seconds)
	await tw.finished


## Clarao branco que escurece (explosao da nave).
func flash_white() -> void:
	_fade.color = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_interval(0.15)
	tw.tween_property(_fade, "color", Color(0, 0, 0, 1), 1.4)
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
	var critical := GameState.meltdown_left >= 0.0 and _hud.visible
	_alarm.visible = critical
	if critical:
		_alarm.text = "NÚCLEO CRÍTICO! EXPLOSÃO EM %d s" % ceili(GameState.meltdown_left)
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
	if _video_active:
		if (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel")) and not event.is_echo():
			get_viewport().set_input_as_handled()
			_video_skip = true
		return
	if event.is_action_pressed("objective") and not event.is_echo() and not (_menu_active or _dialog_active or _panel_active):
		get_viewport().set_input_as_handled()
		show_objective()
		return
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
	elif _panel_active:
		if (event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("missions")) and not event.is_echo():
			get_viewport().set_input_as_handled()
			_panel_closed.emit()


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


# ============================ painel e rastreador ============================
func _build_panel() -> void:
	_panel = Control.new()
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(dim)
	var box := NinePatchRect.new()
	box.texture = TEX_DIALOG
	for side in ["left", "right", "top", "bottom"]:
		box.set("patch_margin_" + side, 36)
	box.position = Vector2(148, 100)
	box.size = Vector2(1240, 820)
	_panel.add_child(box)
	_panel_text = _label("", 24)
	_panel_text.position = Vector2(200, 150)
	_panel_text.size = Vector2(1136, 720)
	_panel_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_panel_text)


func _build_tracker() -> void:
	_tracker = Control.new()
	_tracker.size = Vector2(600, 120)
	_tracker.position = Vector2(VIEW.x - 600.0 - 16.0, 100)
	_tracker.visible = false
	add_child(_tracker)
	var box := NinePatchRect.new()
	box.texture = TEX_TOAST
	for side in ["left", "right", "top", "bottom"]:
		box.set("patch_margin_" + side, 20)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tracker.add_child(box)
	_tracker_label = _label("", 24)
	_tracker_label.position = Vector2(30, 18)
	_tracker_label.size = Vector2(540, 90)
	_tracker_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tracker.add_child(_tracker_label)
	# icone recolhido: "!" azul com um losango piscando embaixo (clique ou V mostram a mensagem de novo)
	_tracker_icon = Control.new()
	_tracker_icon.size = Vector2(70, 110)
	_tracker_icon.position = Vector2(VIEW.x - 90.0, 100)
	_tracker_icon.mouse_filter = Control.MOUSE_FILTER_STOP
	_tracker_icon.visible = false
	_tracker_icon.gui_input.connect(_on_tracker_icon_input)
	add_child(_tracker_icon)
	_tracker_mark = _label("!", 64)
	_tracker_mark.add_theme_color_override("font_color", Color("2a6bff"))
	_tracker_mark.add_theme_color_override("font_outline_color", Color.WHITE)
	_tracker_mark.add_theme_constant_override("outline_size", 10)
	_tracker_mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tracker_mark.size = Vector2(70, 72)
	_tracker_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker_icon.add_child(_tracker_mark)
	_tracker_diamond = Polygon2D.new()
	_tracker_diamond.polygon = PackedVector2Array([Vector2(0, -13), Vector2(11, 0), Vector2(0, 13), Vector2(-11, 0)])
	_tracker_diamond.color = Color("2a6bff")
	_tracker_diamond.position = Vector2(35, 92)
	_tracker_icon.add_child(_tracker_diamond)


func _build_voyage() -> void:
	_voyage = Control.new()
	_voyage.position = Vector2(20, 96)
	_voyage.size = Vector2(400, 160)
	_voyage.visible = false
	add_child(_voyage)
	var box := NinePatchRect.new()
	box.texture = TEX_BAR
	for side in ["left", "right", "top", "bottom"]:
		box.set("patch_margin_" + side, 20)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_voyage.add_child(box)
	_voyage_title = _label("", 24)
	_voyage_title.position = Vector2(24, 12)
	_voyage.add_child(_voyage_title)
	_voyage_info = _label("", 16)
	_voyage_info.position = Vector2(24, 44)
	_voyage.add_child(_voyage_info)
	var defs := [["energy", "ENERGIA", Color("e8c23a")], ["fuel", "COMBUSTÍVEL", Color("e07a3a")], ["progress", "PROGRESSO", Color("3ac28a")]]
	for i in defs.size():
		var d: Array = defs[i]
		var y := 74.0 + i * 26.0
		var lab := _label(d[1], 16)
		lab.position = Vector2(24, y)
		_voyage.add_child(lab)
		var bg := ColorRect.new()
		bg.color = Color(INK, 0.35)
		bg.position = Vector2(210, y + 2)
		bg.size = Vector2(150, 14)
		_voyage.add_child(bg)
		var fill := ColorRect.new()
		fill.color = d[2]
		fill.position = bg.position
		fill.size = Vector2(150, 14)
		_voyage.add_child(fill)
		_voyage_bars[d[0]] = fill


func _refresh_voyage() -> void:
	_voyage.visible = Voyage.active and _hud.visible
	if not _voyage.visible:
		return
	var s := maxi(0, int(ceil(Voyage.time_left)))
	_voyage_title.text = "VIAGEM: " + Voyage.route
	_voyage_info.text = "Tempo %02d:%02d%s" % [s / 60, s % 60, "   SEM CONTATO" if not Voyage.comms_ok() else ""]
	_voyage_bars["energy"].size.x = 150.0 * clampf(Voyage.energy, 0.0, 100.0) / 100.0
	_voyage_bars["fuel"].size.x = 150.0 * clampf(Voyage.fuel, 0.0, 100.0) / 100.0
	_voyage_bars["progress"].size.x = 150.0 * clampf(Voyage.progress, 0.0, 100.0) / 100.0


func _refresh_tracker() -> void:
	var txt: String = Missions.tracker_text()
	_tracker_label.text = txt
	if txt != _tracker_last:      # objetivo novo: mostra a mensagem por um tempo
		_tracker_last = txt
		_tracker_open_left = TRACKER_SHOW_TIME
	_update_tracker_visibility()


func _update_tracker_visibility() -> void:
	var has: bool = _hud.visible and _tracker_last != ""
	_tracker.visible = has and _tracker_open_left > 0.0
	_tracker_icon.visible = has and _tracker_open_left <= 0.0


## Mostra a mensagem do objetivo de novo (clique no "!" ou tecla V).
func show_objective() -> void:
	if _tracker_last != "":
		_tracker_open_left = TRACKER_SHOW_TIME
		_update_tracker_visibility()


func _on_tracker_icon_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		show_objective()


func _process(delta: float) -> void:
	_ui_t += delta
	if _tracker_open_left > 0.0:
		_tracker_open_left -= delta
		if _tracker_open_left <= 0.0:
			_update_tracker_visibility()
	if _tracker_icon.visible:
		_tracker_diamond.modulate.a = 0.25 + 0.75 * absf(sin(_ui_t * 2.4))   # losango piscando
		_tracker_mark.position.y = sin(_ui_t * 3.0) * 4.0
	_flicker.color.a = (0.2 if int(_ui_t * 10.0) % 2 == 0 else 0.0) if Solar.inverted_left > 0.0 else 0.0
	if _panel_active and _panel_provider.is_valid():
		_panel_refresh += delta
		if _panel_refresh >= 0.2:
			_panel_refresh = 0.0
			_panel_text.text = _panel_provider.call()


func _refresh_solar() -> void:
	var on: bool = Solar.alert_sent and not Solar.resolved and _hud.visible
	_solar_alarm.visible = on
	if on:
		_solar_alarm.text = "ALARME SOLAR! %s: %d s" % ["ESCUDOS ATIVOS" if Solar.shield_on else "Ative os escudos (sala do reator)", ceili(Solar.countdown)]
		_solar_alarm.add_theme_color_override("font_color", Color("1fa84a") if Solar.shield_on else Color("e07a00"))


# ============================ util ============================
func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", INK)
	return l
