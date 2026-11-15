extends Control
## Minigame de preparo de reagente (bancada de frascos do laboratorio, lado da Terra).
## Receita em PORCENTAGEM de um volume total (ex.: 40% A, 35% B, 25% agua de 250 ml).
## Arraste um frasco: quanto MAIS longe voce arrastar, mais ele INCLINA e mais liquido cai no
## copo; soltar para o fluxo. Teclado: setas escolhem o frasco, segure F para inclinar.
## As porcentagens sao relativas: se passou de um liquido, compense colocando os outros na proporcao.
## O copo tem capacidade limitada (transbordar encerra e perde o preparo). Quanto mais perto da
## receita, maior a qualidade. Tab ou "Concluir" encerra. Esc sai.
## O resultado fica em `result` (quality 0..100, total, fractions, spilled).

signal closed

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const VIEW := Vector2(1536, 1024)
const BEAKER := Rect2(600, 420, 340, 420)       # copo (parte interna)
const LIQ := [
	{"name": "Reagente A", "color": Color("e0553a")},
	{"name": "Reagente B", "color": Color("3a78e8")},
	{"name": "Água", "color": Color("8fdcff")},
]
const PIVOTS := [Vector2(520, 330), Vector2(770, 190), Vector2(1020, 330)]
const SIGNS := [1.0, 1.0, -1.0]                  # lado para onde inclina
const TILT_MAX := 1.75                           # rad (~100 graus)
const TILT_START := 0.8                          # abaixo disso nao cai nada
const RECIPES := [[50, 30, 20], [40, 35, 25], [30, 30, 40], [45, 35, 20], [60, 25, 15], [35, 35, 30]]

var difficulty := 1
var result: Dictionary = {}

var _total := 100.0              # volume total da receita (ml)
var _recipe: Array = [40, 35, 25]
var _cap := 125.0                # capacidade do copo
var _vol: Array = [0.0, 0.0, 0.0]
var _stock: Array = [0.0, 0.0, 0.0]
var _stock0: Array = [0.0, 0.0, 0.0]
var _order: Array = []           # ordem em que cada liquido entrou (para as camadas)
var _tilt: Array = [0.0, 0.0, 0.0]
var _drag := -1
var _grab := Vector2.ZERO
var _sel := 0
var _over := false
var _spilled := false
var _t := 0.0
var _end_btn: Button
var _drops: Array = []


func configure(diff: int = 1) -> void:
	difficulty = clampi(diff, 0, 2)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	match difficulty:
		0:
			_total = 100.0
			_recipe = RECIPES[0]
		1:
			_total = [100.0, 150.0, 200.0][randi() % 3]
			_recipe = RECIPES[1 + randi() % 3]
		_:
			_total = 250.0
			_recipe = RECIPES[1 + randi() % 5]
	_cap = _total * (1.35 if difficulty < 2 else 1.25)
	for i in 3:
		_stock0[i] = _total * float(_recipe[i]) / 100.0 * 1.7
		_stock[i] = _stock0[i]
	_end_btn = Button.new()
	_end_btn.text = tr("Concluir preparo")
	_end_btn.add_theme_font_override("font", FONT)
	_end_btn.add_theme_font_size_override("font_size", 20)
	_end_btn.position = Vector2(VIEW.x - 330.0, 940)
	_end_btn.size = Vector2(300, 54)
	_end_btn.focus_mode = Control.FOCUS_NONE
	_end_btn.pressed.connect(_finish)
	add_child(_end_btn)


# ---------------------------------------------------------------- entrada
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		closed.emit()
		return
	if _over:
		if event.is_action_pressed("interact") and not event.is_echo():
			get_viewport().set_input_as_handled()
			closed.emit()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		if event.pressed:
			if p.x > VIEW.x - 340.0 and p.y > 930.0:
				return
			for i in 3:
				if Rect2(PIVOTS[i] + Vector2(-90, -120), Vector2(180, 240)).has_point(p) and _stock[i] > 0.0:
					_drag = i
					_sel = i
					_grab = p
		else:
			_drag = -1
	elif event is InputEventMouseMotion and _drag >= 0:
		var m: Vector2 = (make_input_local(event) as InputEventMouseMotion).position
		_tilt[_drag] = clampf(m.distance_to(_grab) / 260.0, 0.0, 1.0)
	elif event.is_action_pressed("move_right") and not event.is_echo():
		_sel = (_sel + 1) % 3
	elif event.is_action_pressed("move_left") and not event.is_echo():
		_sel = (_sel + 2) % 3
	elif event.is_action_pressed("inventory") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_finish()


func _process(delta: float) -> void:
	_t += delta
	if _over:
		queue_redraw()
		return
	# inclinacao: mouse (arrasto) ou teclado (segurar F)
	for i in 3:
		var target := 0.0
		if _drag == i:
			target = _tilt[i]   # definido pelo arrasto
		elif _drag < 0 and i == _sel and Input.is_action_pressed("interact"):
			target = minf(1.0, _tilt[i] + delta * 0.8)
		if _drag == i or (_drag < 0 and i == _sel and Input.is_action_pressed("interact")):
			_tilt[i] = target
		else:
			_tilt[i] = move_toward(_tilt[i], 0.0, delta * 2.5)   # volta para cima ao soltar
	for i in 3:
		var amount := _flow(i) * delta
		if amount > 0.0:
			_pour(i, amount)
			if randf() < 0.6:
				_drops.append({"pos": _spout(i), "vel": Vector2(randf_range(-20, 20), 40.0), "c": LIQ[i]["color"], "life": 0.7})
	var keep: Array = []
	for d in _drops:
		d["life"] -= delta
		d["vel"] += Vector2(0, 600.0 * delta)
		d["pos"] += (d["vel"] as Vector2) * delta
		if d["life"] > 0.0 and (d["pos"] as Vector2).y < _surface_y():
			keep.append(d)
	_drops = keep
	if _spilled:
		_finish()
	queue_redraw()


func _flow(i: int) -> float:
	var rad: float = _tilt[i] * TILT_MAX
	if rad <= TILT_START or _stock[i] <= 0.0:
		return 0.0
	var k := (rad - TILT_START) / (TILT_MAX - TILT_START)
	return pow(k, 1.4) * _total * 0.30


func _pour(i: int, amount: float) -> void:
	amount = minf(amount, _stock[i])
	_stock[i] -= amount
	if _vol[i] <= 0.0:
		_order.append(i)
	_vol[i] += amount
	if _sum() > _cap:
		_vol[i] -= _sum() - _cap
		_spilled = true


func _sum() -> float:
	return _vol[0] + _vol[1] + _vol[2]


func _spout(i: int) -> Vector2:
	var r: float = _tilt[i] * TILT_MAX * float(SIGNS[i])
	return PIVOTS[i] + Vector2(110.0 * sin(r), -110.0 * cos(r))


func _surface_y() -> float:
	return BEAKER.end.y - BEAKER.size.y * clampf(_sum() / _cap, 0.0, 1.0)


# ---------------------------------------------------------------- fim
func _fractions() -> Array:
	var s := _sum()
	var out: Array = [0.0, 0.0, 0.0]
	if s > 0.0:
		for i in 3:
			out[i] = _vol[i] / s
	return out


func _finish() -> void:
	if _over:
		return
	_over = true
	_end_btn.visible = false
	var f := _fractions()
	var err := 0.0
	for i in 3:
		err += absf(f[i] - float(_recipe[i]) / 100.0)
	var q := maxf(0.0, 1.0 - err * 2.0)
	q *= clampf(_sum() / _total, 0.0, 1.0)
	if _spilled or _sum() <= 0.0:
		q = 0.0
	result = {"quality": int(round(q * 100.0)), "total": _sum(), "fractions": f, "spilled": _spilled, "difficulty": difficulty}


func _rating(q: int) -> String:
	if q >= 90:
		return tr("Reagente perfeito!")
	if q >= 70:
		return tr("Reagente bom.")
	if q >= 40:
		return tr("Reagente aceitável.")
	return tr("Reagente impróprio.")


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("14181f"))
	draw_rect(Rect2(Vector2(70, 120), Vector2(VIEW.x - 140.0, 840)), Color("1d2733"))
	draw_rect(Rect2(Vector2(70, 120), Vector2(VIEW.x - 140.0, 840)), Color("46586e"), false, 4.0)
	draw_rect(Rect2(Vector2(70, 850), Vector2(VIEW.x - 140.0, 110)), Color("3a3f4a"))   # bancada
	_txt(Vector2(24, 40), tr("Preparo de reagente — total da receita: %d ml") % int(_total), 24, Color("eef3ff"))
	var lines := PackedStringArray()
	for i in 3:
		lines.append("%s %d%% (%d ml)" % [tr(LIQ[i]["name"]), _recipe[i], int(round(_total * float(_recipe[i]) / 100.0))])
	_txt(Vector2(24, 74), tr("Receita: ") + "   ".join(lines), 18, Color("c9d6ff"))
	# copo
	for k in range(1, 10):
		var y := BEAKER.end.y - BEAKER.size.y * float(k) / 10.0
		draw_line(Vector2(BEAKER.position.x, y), Vector2(BEAKER.position.x + (36.0 if k % 5 != 0 else 60.0), y), Color(1, 1, 1, 0.5), 2.0)
	var yb := BEAKER.end.y
	for i in _order:
		var h: float = BEAKER.size.y * float(_vol[i]) / _cap
		yb -= h
		draw_rect(Rect2(BEAKER.position.x + 3.0, yb, BEAKER.size.x - 6.0, h), LIQ[i]["color"])
	var bx0 := BEAKER.position.x
	var bx1 := BEAKER.end.x
	draw_polyline(PackedVector2Array([Vector2(bx0 - 12.0, BEAKER.position.y - 8.0), BEAKER.position, Vector2(bx0, BEAKER.end.y), BEAKER.end, Vector2(bx1, BEAKER.position.y), Vector2(bx1 + 12.0, BEAKER.position.y - 8.0)]), Color("dff4ff"), 6.0)
	_txt(Vector2(BEAKER.position.x, BEAKER.end.y + 40), tr("%d ml de %d ml") % [int(_sum()), int(_cap)], 20, Color("ffffff"), BEAKER.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# porcentagens atuais
	var f := _fractions()
	for i in 3:
		var c: Color = LIQ[i]["color"]
		_txt(Vector2(1000, 520 + i * 44), "%s: %d%%  (%s %d%%)" % [tr(LIQ[i]["name"]), int(round(f[i] * 100.0)), tr("meta"), _recipe[i]], 18, c.lightened(0.3))
	# frascos
	for i in 3:
		_draw_flask(i)
	# fluxo
	for i in 3:
		if _flow(i) > 0.0:
			var s := _spout(i)
			var w := 3.0 + 6.0 * (_flow(i) / (_total * 0.30))
			draw_line(s, Vector2(s.x, _surface_y()), LIQ[i]["color"], w)
	for d in _drops:
		draw_circle(d["pos"], 3.0, d["c"])
	_txt(Vector2(24, 985), tr("Arraste um frasco (quanto mais longe, mais inclina)   ←/→ + segurar F   Tab: concluir   Esc: sair"), 14, Color("a9bbff"))
	if _over:
		draw_rect(Rect2(Vector2(220, 300), Vector2(VIEW.x - 440.0, 400)), Color(0.02, 0.04, 0.1, 0.96))
		draw_rect(Rect2(Vector2(220, 300), Vector2(VIEW.x - 440.0, 400)), Color("8aa0ff"), false, 4.0)
		var q: int = result["quality"]
		var texts: Array = []
		if _spilled:
			texts = [tr("Transbordou!"), tr("O preparo foi perdido."), tr("Qualidade: 0%")]
		else:
			texts = [_rating(q), tr("Qualidade: %d%%") % q,
				tr("Misturado: A %d%%, B %d%%, Água %d%%") % [int(round(f[0] * 100.0)), int(round(f[1] * 100.0)), int(round(f[2] * 100.0))]]
		texts.append(tr("(F: continuar)"))
		var y := 380.0
		for line in texts:
			_txt(Vector2(240, y), line, 26, Color("ffffff"), VIEW.x - 480.0, HORIZONTAL_ALIGNMENT_CENTER)
			y += 70.0


func _draw_flask(i: int) -> void:
	var rot: float = _tilt[i] * TILT_MAX * float(SIGNS[i])
	draw_set_transform(PIVOTS[i], rot, Vector2.ONE)
	var col: Color = LIQ[i]["color"]
	var frac: float = float(_stock[i]) / float(_stock0[i])
	var body := Rect2(-55, -60, 110, 150)
	draw_rect(Rect2(-18, -112, 36, 54), Color(0.85, 0.95, 1.0, 0.18))
	draw_rect(body, Color(0.85, 0.95, 1.0, 0.14))
	var h: float = body.size.y * clampf(frac, 0.0, 1.0)
	draw_rect(Rect2(body.position.x + 3.0, body.end.y - h, body.size.x - 6.0, h), col)
	draw_rect(body, Color("dff4ff"), false, 4.0)
	draw_rect(Rect2(-18, -112, 36, 54), Color("dff4ff"), false, 4.0)
	draw_rect(Rect2(-26, -120, 52, 10), Color("dff4ff"))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var p: Vector2 = PIVOTS[i]
	_txt(p + Vector2(-90, 130), tr(LIQ[i]["name"]), 16, Color("ffffff") if i == _sel else Color("a9bbff"), 180.0, HORIZONTAL_ALIGNMENT_CENTER)
	if i == _sel:
		draw_rect(Rect2(p + Vector2(-90, -125), Vector2(180, 250)), Color(1, 1, 1, 0.35), false, 2.0)


func _txt(pos: Vector2, text: String, size: int, color: Color, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(FONT, pos, text, align, width, size, color)
