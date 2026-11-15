extends Control
## Minigame do microscopio (bancada do laboratorio, lado da Terra): analise de amostra.
## A lente (circulo) segue o mouse ou WASD/setas. Ache as colonias iguais a imagem de REFERENCIA
## e marque cada uma (clique / F). Ha distracoes: bolhas, poeira e colonias de outra cor.
## Contagem: 10 = ocupacao ideal; menos de 10 = baixa ocupacao; mais de 10 = presenca de fungos.
## Backspace / botao direito desfaz a ultima marca. Tab ou o botao "Concluir" encerra. Esc sai.
## Dificuldade (0..2): quantidade/tamanho dos pontos, distracoes, contraste, tempo.

signal closed

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const INK := Color("1b2a5c")
const VIEW := Vector2(1536, 1024)
const FIELD := Rect2(70, 110, 1396, 800)
const DIFF := [
	{"name": "Fácil", "r": 17.0, "junk": 9, "time": 75.0, "contrast": 1.0, "lens": 165.0},
	{"name": "Médio", "r": 13.0, "junk": 20, "time": 58.0, "contrast": 0.85, "lens": 140.0},
	{"name": "Difícil", "r": 10.0, "junk": 34, "time": 45.0, "contrast": 0.7, "lens": 120.0},
]
const SHADER := """
shader_type canvas_item;
uniform vec2 center = vec2(768.0, 512.0);
uniform float radius = 150.0;
uniform vec2 area = vec2(1536.0, 1024.0);
void fragment() {
	float d = distance(UV * area, center);
	COLOR = vec4(0.02, 0.03, 0.05, smoothstep(radius - 3.0, radius + 3.0, d) * 0.96);
}
"""

var difficulty := 1
var result: Dictionary = {}     # preenchido ao concluir: count, truth, correct, wrong, label, score

var _d: Dictionary
var _target_color := Color("3fb04a")
var _spots: Array = []          # {pos, kind, r, color, marked, seed}
var _truth := 10
var _lens := Vector2(768, 512)
var _marks: Array = []          # indices em _spots, na ordem das marcas
var _time_left := 60.0
var _over := false
var _shade: ColorRect
var _ring: Control
var _info: Label
var _hint: Label
var _end_btn: Button
var _panel: Label
var _t := 0.0
var _flash := 0.0
var _flash_pos := Vector2.ZERO
var _flash_ok := true


func configure(diff: int = 1) -> void:
	difficulty = clampi(diff, 0, 2)
	_d = DIFF[difficulty]
	_time_left = float(_d["time"])
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hues := [Color("3fb04a"), Color("2f6fe0"), Color("d9a21b"), Color("b04a9a")]
	_target_color = hues[randi() % hues.size()]
	var pool := [10, 10, 10, 10, 6, 7, 8, 9, 11, 12, 13, 14]
	_truth = pool[randi() % pool.size()]
	_generate()

	_shade = ColorRect.new()
	_shade.size = VIEW
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("radius", float(_d["lens"]))
	_shade.material = mat
	add_child(_shade)
	_ring = Control.new()
	_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.draw.connect(_draw_ring)
	add_child(_ring)

	_info = _label("", 22, Color("eef3ff"))
	_info.position = Vector2(24, 18)
	add_child(_info)
	_hint = _label(tr("Mouse/WASD: mover a lente   Clique/F: marcar   Backspace: desfazer   Tab: concluir   Esc: sair"), 14, Color("c9d6ff"))
	_hint.position = Vector2(24, 980)
	add_child(_hint)
	_end_btn = Button.new()
	_end_btn.text = tr("Concluir análise")
	_end_btn.add_theme_font_override("font", FONT)
	_end_btn.add_theme_font_size_override("font_size", 20)
	_end_btn.position = Vector2(VIEW.x - 330.0, 940)
	_end_btn.size = Vector2(300, 54)
	_end_btn.focus_mode = Control.FOCUS_NONE
	_end_btn.pressed.connect(_finish)
	add_child(_end_btn)
	# referencia (acima da sombra, sempre visivel)
	var ref := Control.new()
	ref.position = Vector2(VIEW.x - 300.0, 14)
	ref.size = Vector2(280, 86)
	ref.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ref.draw.connect(func(): _draw_reference(ref))
	add_child(ref)
	_panel = _label("", 24, Color("ffffff"))
	_panel.position = Vector2(220, 300)
	_panel.size = Vector2(VIEW.x - 440.0, 420)
	_panel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.visible = false
	_panel.add_theme_color_override("font_outline_color", Color("0b1030"))
	_panel.add_theme_constant_override("outline_size", 8)
	add_child(_panel)
	_refresh()


# ---------------------------------------------------------------- geracao
func _generate() -> void:
	var taken: Array = []
	var r: float = _d["r"]
	for i in _truth:
		_spots.append(_make_spot("target", r * randf_range(0.85, 1.15), _target_color, taken))
	var junk: int = _d["junk"]
	for i in junk:
		var k := randf()
		if k < 0.4:
			_spots.append(_make_spot("bubble", randf_range(10.0, 30.0), Color.WHITE, taken))
		elif k < 0.75:
			_spots.append(_make_spot("dust", randf_range(2.0, 5.0), Color("6a6a60"), taken))
		else:
			var c := _other_color()
			_spots.append(_make_spot("other", r * randf_range(0.85, 1.15), c, taken))


func _other_color() -> Color:
	var all := [Color("3fb04a"), Color("2f6fe0"), Color("d9a21b"), Color("b04a9a"), Color("d8562f")]
	all = all.filter(func(c): return c != _target_color)
	return all[randi() % all.size()]


func _make_spot(kind: String, r: float, c: Color, taken: Array) -> Dictionary:
	var p := Vector2.ZERO
	for tries in 40:
		p = Vector2(randf_range(FIELD.position.x + 40.0, FIELD.end.x - 40.0), randf_range(FIELD.position.y + 40.0, FIELD.end.y - 40.0))
		var ok := true
		for q: Vector2 in taken:
			if q.distance_to(p) < 64.0:
				ok = false
				break
		if ok:
			break
	if kind != "dust":
		taken.append(p)
	return {"pos": p, "kind": kind, "r": r, "color": c, "marked": false, "seed": randf() * 100.0}


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("171a22"))
	draw_rect(FIELD, Color("e7e3c9"))
	# manchas suaves da lamina
	for i in 14:
		var s := float(i) * 7.3
		draw_circle(FIELD.position + Vector2(fmod(s * 331.0, FIELD.size.x), fmod(s * 173.0, FIELD.size.y)), 90.0 + fmod(s * 13.0, 120.0), Color(0.78, 0.8, 0.7, 0.18))
	for S in _spots:
		_draw_spot(S)
	if _flash > 0.0:
		var col := Color("3fe05a") if _flash_ok else Color("ff4a4a")
		col.a = _flash
		draw_arc(_flash_pos, 34.0 + (1.0 - _flash) * 30.0, 0.0, TAU, 32, col, 4.0)


func _draw_spot(S: Dictionary) -> void:
	var p: Vector2 = S["pos"]
	var r: float = S["r"]
	var c: Color = S["color"]
	match S["kind"]:
		"target", "other":
			var k: float = _d["contrast"]
			var edge := c.lerp(Color("e7e3c9"), 1.0 - k)
			draw_circle(p, r * 1.25, Color(edge.r, edge.g, edge.b, 0.28))
			draw_circle(p, r, edge)
			draw_circle(p, r * 0.5, edge.darkened(0.3))
			var sd: float = S["seed"]
			for j in 5:
				var a := sd + float(j) * 1.26
				draw_circle(p + Vector2(cos(a), sin(a)) * r * 0.7, r * 0.16, edge.lightened(0.25))
		"bubble":
			draw_arc(p, r, 0.0, TAU, 28, Color(1, 1, 1, 0.9), 3.0)
			draw_circle(p, r, Color(1, 1, 1, 0.12))
			draw_arc(p + Vector2(-r * 0.3, -r * 0.3), r * 0.4, PI, PI * 1.5, 8, Color(1, 1, 1, 0.9), 3.0)
		"dust":
			var sd2: float = S["seed"]
			draw_circle(p, r, S["color"])
			draw_line(p, p + Vector2(cos(sd2), sin(sd2)) * (r * 3.0), Color(0.42, 0.42, 0.38, 0.8), 2.0)
	if S["marked"]:
		draw_arc(p, maxf(r, 12.0) + 9.0, 0.0, TAU, 24, Color("1b2a5c"), 4.0)
		draw_arc(p, maxf(r, 12.0) + 14.0, 0.0, TAU, 24, Color.WHITE, 2.0)


func _draw_ring() -> void:
	var R: float = _d["lens"]
	_ring.draw_arc(_lens, R, 0.0, TAU, 72, Color("0b1030"), 8.0)
	_ring.draw_arc(_lens, R + 6.0, 0.0, TAU, 72, Color("8aa0ff"), 2.0)
	_ring.draw_line(_lens + Vector2(-R * 0.18, 0), _lens + Vector2(R * 0.18, 0), Color(0.1, 0.1, 0.2, 0.55), 2.0)
	_ring.draw_line(_lens + Vector2(0, -R * 0.18), _lens + Vector2(0, R * 0.18), Color(0.1, 0.1, 0.2, 0.55), 2.0)


func _draw_reference(c: Control) -> void:
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("0b1030"))
	c.draw_rect(Rect2(Vector2.ZERO, c.size), Color("8aa0ff"), false, 2.0)
	var col := _target_color
	var r := 26.0
	var p := Vector2(48, 44)
	c.draw_circle(p, r * 1.25, Color(col.r, col.g, col.b, 0.3))
	c.draw_circle(p, r, col)
	c.draw_circle(p, r * 0.5, col.darkened(0.3))
	for j in 5:
		var a := float(j) * 1.26
		c.draw_circle(p + Vector2(cos(a), sin(a)) * r * 0.7, r * 0.16, col.lightened(0.25))
	c.draw_string(FONT, Vector2(96, 36), tr("REFERÊNCIA"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("eef3ff"))
	c.draw_string(FONT, Vector2(96, 62), tr("ache e marque"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("c9d6ff"))


# ---------------------------------------------------------------- logica
func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.0)
	if _over:
		queue_redraw()
		return
	var v := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
	if v != Vector2.ZERO:
		_lens += v.normalized() * 520.0 * delta
	_lens = _lens.clamp(FIELD.position, FIELD.end)
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_finish()
	(_shade.material as ShaderMaterial).set_shader_parameter("center", _lens)
	_ring.queue_redraw()
	queue_redraw()
	_refresh()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		closed.emit()
		return
	if _over:
		if (event.is_action_pressed("interact") or event.is_action_pressed("inventory")) and not event.is_echo():
			get_viewport().set_input_as_handled()
			closed.emit()
		return
	if event is InputEventMouseMotion:
		_lens = (make_input_local(event) as InputEventMouseMotion).position
	elif event is InputEventMouseButton and event.pressed:
		var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		if p.x > VIEW.x - 340.0 and p.y > 930.0:
			return   # clique no botao Concluir
		if event.button_index == MOUSE_BUTTON_LEFT:
			_lens = p
			_mark()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_undo()
	elif event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_mark()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_BACKSPACE:
		_undo()
	elif event.is_action_pressed("inventory") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_finish()


func _mark() -> void:
	var R: float = _d["lens"]
	var best := -1
	var bd := 1e9
	for i in _spots.size():
		var S: Dictionary = _spots[i]
		if S["marked"] or S["kind"] == "dust":
			continue
		var d := (S["pos"] as Vector2).distance_to(_lens)
		var reach := maxf(float(S["r"]), 14.0) + 12.0
		if d < R - 6.0 and d < reach + 8.0 and d < bd:
			best = i
			bd = d
	if best < 0:
		return
	var S2: Dictionary = _spots[best]
	S2["marked"] = true
	_marks.append(best)
	_flash = 1.0
	_flash_pos = S2["pos"]
	_flash_ok = S2["kind"] == "target"


func _undo() -> void:
	if _marks.is_empty():
		return
	var i: int = _marks.pop_back()
	_spots[i]["marked"] = false


func _counts() -> Dictionary:
	var ok := 0
	for i in _marks:
		if _spots[i]["kind"] == "target":
			ok += 1
	return {"count": _marks.size(), "correct": ok, "wrong": _marks.size() - ok}


func _classify(n: int) -> String:
	if n == 10:
		return tr("Ocupação ideal")
	if n < 10:
		return tr("Baixa ocupação")
	return tr("Presença de fungos")


func _finish() -> void:
	if _over:
		return
	_over = true
	var c := _counts()
	var score := clampf(float(c["correct"]) / float(_truth) - 0.12 * float(c["wrong"]), 0.0, 1.0)
	result = {"count": c["count"], "truth": _truth, "correct": c["correct"], "wrong": c["wrong"],
		"label": _classify(c["count"]), "true_label": _classify(_truth), "score": int(round(score * 100.0)), "difficulty": difficulty}
	_shade.visible = false
	_ring.visible = false
	_end_btn.visible = false
	_hint.text = tr("F: continuar")
	_panel.visible = true
	_panel.text = "%s\n\n%s\n%s\n\n%s" % [
		tr("Análise concluída"),
		tr("Você contou %d → %s") % [c["count"], result["label"]],
		tr("Valor real: %d → %s") % [_truth, result["true_label"]],
		tr("Acertos: %d   Marcas erradas: %d   Pontuação: %d%%") % [c["correct"], c["wrong"], result["score"]]]
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.1, 0.82)
	bg.position = Vector2(180, 270)
	bg.size = Vector2(VIEW.x - 360.0, 400)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, _panel.get_index())


func _refresh() -> void:
	var c := _counts()
	_info.text = tr("Contagem: %d    Tempo: %d s    Dificuldade: %s") % [c["count"], int(ceil(_time_left)), tr(_d["name"])]


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
