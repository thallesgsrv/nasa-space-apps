extends Control
## Menu inicial: a Terra vista do espaco, estrelas que piscam, uma nave cruzando o ceu e um sinal de
## radio saindo da base ("Terra chamando"). A arte estatica vem de assets/ui/start_space.png
## (gerada por tools/gen_start_art.py); tudo o que se mexe e desenhado aqui, em _draw().
## W/S ou setas escolhem (ou o mouse); F / Enter / Espaco confirmam.

const BG := preload("res://assets/ui/start_space.png")
const SHIP := preload("res://assets/vehicles/nave_pequena.png")
const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const FONT_BOLD := preload("res://assets/fonts/PixelOperator8-Bold.ttf")

const GAME_SCENE := "res://scenes/cutscene_intro.tscn"   # cutscene inicial; depois dela entra no jogo
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const OPTIONS := ["INICIAR", "MULTIPLAYER LAN", "OPÇÕES"]

const SCREEN := Vector2(1536, 1024)
const PANEL_RECT := Rect2(458, 442, 620, 308)
const ROW_H := 84.0
const ROW_PAD := 28.0

const COL_TITLE := Color("eaf4ff")
const COL_ACCENT := Color("ffb84a")
const COL_DIM := Color("7f95d6")
const COL_SOFT := Color("8ea2dd")
const COL_INK := Color("04061a")
const COL_GLOW_A := Color("2a6fd6")
const COL_GLOW_B := Color("7fd0ff")

# base de radio: antena sobre a Terra (ponto da curva da Terra desenhada em start_space.png)
const ANTENNA := Vector2(180, 898)

var _sel := 0
var _starting := false
var _t := 0.0
var _intro := 0.0           # 0..1: aparece o titulo e o menu

var _tagline := ""
var _hint := ""
var _labels: Array[Label] = []
var _panel: Panel
var _bar: Panel
var _ui: Control

var _stars: Array = []       # {p, phase, speed, big, col}
var _streaks: Array = []     # {p, speed, len, a}
var _shoot := {"t": -1.0, "from": Vector2.ZERO, "dir": Vector2.ZERO}
var _next_shoot := 3.0
var _ship_x := -260.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	Audio.stop_music()
	UI.show_hud(false)
	GameState.running = false

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	for i in 90:
		_stars.append({
			"p": Vector2(rng.randi_range(0, 383), rng.randi_range(0, 178)) * 4.0,
			"phase": rng.randf() * TAU,
			"speed": rng.randf_range(0.8, 2.6),
			"big": rng.randf() < 0.16,
			"col": [Color("cfdcff"), Color("ffffff"), Color("a9c4ff"), Color("ffe9b0")][rng.randi_range(0, 3)],
		})
	for i in 16:
		_streaks.append({
			"p": Vector2(rng.randf_range(0, SCREEN.x), rng.randf_range(80, 640)),
			"speed": rng.randf_range(40.0, 150.0),
			"len": rng.randi_range(2, 7) * 8.0,
			"a": rng.randf_range(0.08, 0.22),
		})

	_build_menu()
	_refresh_texts()
	_place_cursor(true)

	_ui.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "_intro", 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(_ui, "modulate:a", 1.0, 0.9).set_delay(0.7)


func _build_menu() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ui)

	# moldura em pixel art: dois contornos, azul fundo translucido
	_panel = Panel.new()
	_panel.position = PANEL_RECT.position
	_panel.size = PANEL_RECT.size
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.05, 0.16, 0.80)
	sb.set_border_width_all(4)
	sb.border_color = Color("4a7fe0")
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 6)
	_panel.add_theme_stylebox_override("panel", sb)
	_ui.add_child(_panel)

	var inner := Panel.new()
	inner.position = PANEL_RECT.position + Vector2(10, 10)
	inner.size = PANEL_RECT.size - Vector2(20, 20)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = Color(0, 0, 0, 0)
	sb2.set_border_width_all(2)
	sb2.border_color = Color("1c3f94")
	inner.add_theme_stylebox_override("panel", sb2)
	_ui.add_child(inner)

	# barra de destaque da opcao escolhida
	_bar = Panel.new()
	_bar.size = Vector2(PANEL_RECT.size.x - 56, ROW_H - 12)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb3 := StyleBoxFlat.new()
	sb3.bg_color = Color("173a8c")
	sb3.set_border_width_all(2)
	sb3.border_color = Color("7fd0ff")
	_bar.add_theme_stylebox_override("panel", sb3)
	_ui.add_child(_bar)

	for i in OPTIONS.size():
		var lab := Label.new()
		lab.add_theme_font_override("font", FONT)
		lab.add_theme_font_size_override("font_size", 44)
		lab.add_theme_constant_override("outline_size", 6)
		lab.add_theme_color_override("font_outline_color", COL_INK)
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.position = Vector2(PANEL_RECT.position.x, _row_y(i))
		lab.size = Vector2(PANEL_RECT.size.x, ROW_H - 12)
		_labels.append(lab)
		_ui.add_child(lab)


func _row_y(i: int) -> float:
	return PANEL_RECT.position.y + ROW_PAD + 6.0 + i * ROW_H


func _refresh_texts() -> void:
	for k in _labels.size():
		_labels[k].text = tr(OPTIONS[k])
	_tagline = tr("Planeje a missão. Lance. Descubra o que cada decisão causou.")
	_hint = tr("W / S: escolher     F ou Enter: confirmar")
	_style_rows()


func _style_rows() -> void:
	for k in _labels.size():
		_labels[k].add_theme_color_override("font_color", Color.WHITE if k == _sel else COL_DIM)


func _place_cursor(instant: bool = false) -> void:
	var target := Vector2(PANEL_RECT.position.x + 28.0, _row_y(_sel) - 0.0)
	if instant:
		_bar.position = target
	else:
		create_tween().tween_property(_bar, "position", target, 0.12).set_trans(Tween.TRANS_QUAD)
	_style_rows()


func _process(delta: float) -> void:
	_t += delta
	_ship_x += 58.0 * delta
	if _ship_x > SCREEN.x + 260.0:
		_ship_x = -300.0
	for s in _streaks:
		var sp: Vector2 = s["p"]
		sp.x -= float(s["speed"]) * delta
		if sp.x < -80.0:
			sp = Vector2(SCREEN.x + 40.0, randf_range(80, 640))
		s["p"] = sp
	# estrela cadente de tempos em tempos
	if _shoot["t"] >= 0.0:
		_shoot["t"] += delta
		if _shoot["t"] > 0.7:
			_shoot["t"] = -1.0
			_next_shoot = _t + randf_range(4.0, 9.0)
	elif _t > _next_shoot:
		_shoot["t"] = 0.0
		_shoot["from"] = Vector2(randf_range(300, 1300), randf_range(30, 180))
		_shoot["dir"] = Vector2(-1.0, 0.55).normalized()
	queue_redraw()


func _draw() -> void:
	draw_texture(BG, Vector2.ZERO)

	# estrelas piscando (quadrados de 4 px; as grandes viram cruz)
	for s in _stars:
		var a: float = 0.30 + 0.70 * (0.5 + 0.5 * sin(_t * s["speed"] + s["phase"]))
		var c: Color = s["col"]
		c.a = a * _intro
		var p: Vector2 = s["p"]
		draw_rect(Rect2(p, Vector2(4, 4)), c)
		if s["big"] and a > 0.75:
			var cc := c
			cc.a *= 0.6
			draw_rect(Rect2(p + Vector2(-4, 0), Vector2(4, 4)), cc)
			draw_rect(Rect2(p + Vector2(4, 0), Vector2(4, 4)), cc)
			draw_rect(Rect2(p + Vector2(0, -4), Vector2(4, 4)), cc)
			draw_rect(Rect2(p + Vector2(0, 4), Vector2(4, 4)), cc)

	# riscos de poeira passando (sensacao de velocidade)
	for st in _streaks:
		var p: Vector2 = st["p"]
		draw_rect(Rect2(p.snapped(Vector2(4, 4)), Vector2(st["len"], 4)), Color(0.7, 0.8, 1.0, st["a"] * _intro))

	_draw_shooting_star()
	_draw_signal()
	_draw_ship()
	_draw_title()

	# rodape: faixa escura para o texto ler bem por cima da Terra
	var fa := clampf((_intro - 0.5) * 2.0, 0.0, 1.0)
	draw_rect(Rect2(0, 948, SCREEN.x, 76), Color(0.01, 0.02, 0.08, 0.55 * fa))
	draw_rect(Rect2(0, 944, SCREEN.x, 4), Color(0.29, 0.5, 0.88, 0.7 * fa))
	_text_shadow(FONT, _hint, Vector2(0, 996), 24, Color(0.87, 0.91, 1.0, fa), true)
	_text_shadow(FONT, "NASA SPACE APPS CHALLENGE 2026", Vector2(40, 52), 20, Color(0.56, 0.64, 0.87, fa), false)


func _draw_shooting_star() -> void:
	if float(_shoot["t"]) < 0.0:
		return
	var k: float = float(_shoot["t"]) / 0.7
	var dir: Vector2 = _shoot["dir"]
	var head: Vector2 = Vector2(_shoot["from"]) + dir * (k * 520.0)
	for i in 12:
		var q: Vector2 = (head - dir * (i * 16.0)).snapped(Vector2(4, 4))
		var a: float = (1.0 - i / 12.0) * (1.0 - k * 0.6)
		draw_rect(Rect2(q, Vector2(8 if i < 3 else 4, 4)), Color(0.9, 0.95, 1.0, a))


## "Terra chamando": aneis de sinal saindo da antena da base.
func _draw_signal() -> void:
	var a := clampf((_intro - 0.3) * 1.6, 0.0, 1.0)
	# torre
	var tower := Color("cfe3ff")
	draw_rect(Rect2(ANTENNA + Vector2(-2, -34), Vector2(4, 40)), tower)
	draw_rect(Rect2(ANTENNA + Vector2(-12, -22), Vector2(24, 4)), tower)
	draw_rect(Rect2(ANTENNA + Vector2(-8, 4), Vector2(16, 4)), tower)
	var blink := 1.0 if fmod(_t, 1.0) < 0.5 else 0.25
	draw_rect(Rect2(ANTENNA + Vector2(-4, -42), Vector2(8, 8)), Color(1.0, 0.45, 0.3, blink * a))
	# aneis
	var top := ANTENNA + Vector2(0, -38)
	for i in 3:
		var ph := fmod(_t * 0.45 + i / 3.0, 1.0)
		var r := 24.0 + ph * 250.0
		var col := Color(COL_GLOW_B.r, COL_GLOW_B.g, COL_GLOW_B.b, (1.0 - ph) * 0.8 * a)
		draw_arc(top, r, PI + 0.55, TAU - 0.55, 40, col, 5.0, false)


func _draw_ship() -> void:
	var a := clampf((_intro - 0.2) * 1.5, 0.0, 1.0)
	var sc := 0.72
	var sz := SHIP.get_size() * sc
	var bob := sin(_t * 1.3) * 10.0
	var pos := Vector2(_ship_x, 375.0 + bob - sz.y * 0.5).snapped(Vector2(4, 4))
	# chama do motor (esquerda da nave): quadrados que tremem
	var fx := pos + Vector2(8, sz.y * 0.54)
	var flick := 0.6 + 0.4 * sin(_t * 38.0)
	for i in 7:
		var w := (7 - i) * 8.0 * flick
		var col := COL_ACCENT.lerp(Color("ff5a2a"), i / 7.0)
		col.a = (1.0 - i / 8.0) * a
		draw_rect(Rect2(fx + Vector2(-i * 10.0 - w * 0.5, -4.0 - w * 0.12), Vector2(10, 8 + w * 0.24)), col)
	draw_texture_rect(SHIP, Rect2(pos, sz), false, Color(1, 1, 1, a))


func _draw_title() -> void:
	var a := clampf(_intro * 1.5, 0.0, 1.0)
	var y_off := (1.0 - a) * -24.0
	var w1 := FONT_BOLD.get_string_size("TERRA ", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	var w2 := FONT_BOLD.get_string_size("CHAMANDO", HORIZONTAL_ALIGNMENT_LEFT, -1, 100).x
	var size := int(100.0 * minf(1.0, 1240.0 / (w1 + w2)))
	w1 = FONT_BOLD.get_string_size("TERRA ", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	w2 = FONT_BOLD.get_string_size("CHAMANDO", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := (SCREEN.x - (w1 + w2)) * 0.5
	var base := Vector2(x, 184.0 + y_off)
	var pulse := 0.5 + 0.5 * sin(_t * 1.6)
	var glow := COL_GLOW_A.lerp(COL_GLOW_B, pulse)
	glow.a = a
	# sombra dura, contorno que respira e preenchimento
	draw_string(FONT_BOLD, base + Vector2(0, 10), "TERRA ", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.55 * a))
	draw_string(FONT_BOLD, base + Vector2(w1, 10), "CHAMANDO", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.55 * a))
	draw_string_outline(FONT_BOLD, base, "TERRA ", HORIZONTAL_ALIGNMENT_LEFT, -1, size, 14, glow)
	draw_string_outline(FONT_BOLD, base + Vector2(w1, 0), "CHAMANDO", HORIZONTAL_ALIGNMENT_LEFT, -1, size, 14, glow)
	draw_string_outline(FONT_BOLD, base, "TERRA ", HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(COL_INK, a))
	draw_string_outline(FONT_BOLD, base + Vector2(w1, 0), "CHAMANDO", HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(COL_INK, a))
	draw_string(FONT_BOLD, base, "TERRA ", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(COL_TITLE, a))
	draw_string(FONT_BOLD, base + Vector2(w1, 0), "CHAMANDO", HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(COL_ACCENT, a))

	# subtitulo e frase de efeito
	var sa := clampf((_intro - 0.35) * 1.8, 0.0, 1.0)
	_text_shadow(FONT, "SPACE MISSION DESIGN GAME", Vector2(0, 244.0), 30, Color(COL_SOFT, sa), true)
	var ln := Color(0.3, 0.45, 0.85, sa * 0.7)
	draw_rect(Rect2(Vector2(SCREEN.x * 0.5 - 360, 262), Vector2(280, 4)), ln)
	draw_rect(Rect2(Vector2(SCREEN.x * 0.5 + 80, 262), Vector2(280, 4)), ln)
	draw_rect(Rect2(Vector2(SCREEN.x * 0.5 - 8, 258), Vector2(16, 16)).grow(-2), Color(COL_ACCENT, sa))
	_text_shadow(FONT, _tagline, Vector2(0, 308.0), 24, Color(0.81, 0.86, 1.0, sa), true)


## Texto com sombra dura; centralizado na tela quando center = true (x ignorado).
func _text_shadow(font: Font, text: String, pos: Vector2, size: int, col: Color, center: bool) -> void:
	var p := pos
	var align := HORIZONTAL_ALIGNMENT_LEFT
	var width := -1.0
	if center:
		p.x = 0.0
		align = HORIZONTAL_ALIGNMENT_CENTER
		width = SCREEN.x
	draw_string(font, p + Vector2(3, 3), text, align, width, size, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, p, text, align, width, size, col)


# _unhandled_input: se um dialogo estiver aberto, a UI ja consumiu a tecla antes.
func _unhandled_input(event: InputEvent) -> void:
	if _starting or UI.busy:
		return
	if event is InputEventMouseMotion:
		var row := _row_at(get_local_mouse_position())
		if row >= 0 and row != _sel:
			_choose(row)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var row := _row_at(get_local_mouse_position())
		if row >= 0:
			_choose(row)
			_activate()
		return
	if event.is_action_pressed("move_up", true):
		_choose((_sel - 1 + OPTIONS.size()) % OPTIONS.size())
	elif event.is_action_pressed("move_down", true):
		_choose((_sel + 1) % OPTIONS.size())
	elif event.is_action_pressed("interact") and not event.is_echo():
		_activate()


func _row_at(p: Vector2) -> int:
	if not PANEL_RECT.has_point(p):
		return -1
	var i := int((p.y - PANEL_RECT.position.y - ROW_PAD) / ROW_H)
	return i if i >= 0 and i < OPTIONS.size() else -1


func _choose(i: int) -> void:
	_sel = i
	_place_cursor()
	Audio.sfx("select", 1.0, 0.35)


func _activate() -> void:
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
	_refresh_texts()


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
