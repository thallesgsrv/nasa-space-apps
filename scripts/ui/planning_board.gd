extends Control
## Prancheta do planejamento da missao (CML 1-9), na Terra.
## Mostra: a trilha dos 9 CMLs (quem decide cada um), os creditos, as barras do projeto e as
## ALTERNATIVAS como cartoes (passe o mouse: as barras mostram o efeito antes de escolher).
## Quem decide escolhe com o mouse (clique) ou com setas + F; os outros jogadores so acompanham.
## Os dados vem do MissionState (params, plan_cml, plan_owners, plan_hint, decisions).

signal picked(index: int)

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const VIEW := Vector2(1536, 1024)
const CARD_Y := 470.0
const CARD_H := 300.0
const GAUGES := [   # chave, nome, minimo, maximo, "bom e subir?"
	{"k": "reliability", "n": "Confiabilidade", "lo": 0.0, "hi": 100.0, "up": true},
	{"k": "comms", "n": "Comunicação", "lo": 0.0, "hi": 100.0, "up": true},
	{"k": "science", "n": "Ciência", "lo": 0.0, "hi": 100.0, "up": true},
	{"k": "risk", "n": "Risco", "lo": 0.0, "hi": 100.0, "up": false},
	{"k": "energy_mult", "n": "Consumo de energia", "lo": 0.5, "hi": 1.5, "up": false},
	{"k": "mass", "n": "Massa", "lo": 80.0, "hi": 140.0, "up": false},
	{"k": "parts", "n": "Peças reserva", "lo": 0.0, "hi": 4.0, "up": true},
]
const ROLE_SHORT := {0: "Comandante", 1: "Base (Terra)", 2: "Engenheiro", 3: "Astronauta 2"}

var _cards: Array = []
var _title := ""
var _decider := false
var _hover := -1
var _sel := 0
var _t := 0.0
var _shake := 0.0


func configure() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Mostra as alternativas e espera a escolha (indice). cards: [{label, desc, fx, ok}].
func choose(cards: Array, title: String) -> int:
	_cards = cards
	_title = title
	_decider = true
	_hover = -1
	_sel = 0
	for i in cards.size():
		if bool(cards[i].get("ok", true)):
			_sel = i
			break
	var i: int = await picked
	_decider = false
	_cards = []
	return i


func is_deciding() -> bool:
	return _decider


# ---------------------------------------------------------------- entrada
func _card_rect(i: int) -> Rect2:
	var n := _cards.size()
	var w := minf(330.0, (VIEW.x - 160.0 - float(n - 1) * 24.0) / float(maxi(n, 1)))
	if n == 1:
		w = 520.0
	var total := w * n + 24.0 * (n - 1)
	var x := (VIEW.x - total) / 2.0 + float(i) * (w + 24.0)
	return Rect2(x, CARD_Y, w, CARD_H)


func _input(event: InputEvent) -> void:
	if not _decider:
		return
	if event is InputEventMouseMotion:
		var p: Vector2 = (make_input_local(event) as InputEventMouseMotion).position
		_hover = -1
		for i in _cards.size():
			if _card_rect(i).has_point(p):
				_hover = i
				_sel = i
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p2: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		for i in _cards.size():
			if _card_rect(i).has_point(p2):
				_sel = i
				_confirm()
				return
	elif event.is_action_pressed("move_right") and not event.is_echo():
		_sel = (_sel + 1) % _cards.size()
		_hover = -1
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left") and not event.is_echo():
		_sel = (_sel - 1 + _cards.size()) % _cards.size()
		_hover = -1
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_confirm()


func _confirm() -> void:
	if _sel < 0 or _sel >= _cards.size():
		return
	if not bool(_cards[_sel].get("ok", true)):
		_shake = 8.0
		Audio.sfx("select", 0.6, 0.3)
		return
	Audio.sfx("select", 1.35, 0.5)
	picked.emit(_sel)


func _process(delta: float) -> void:
	_t += delta
	_shake = maxf(0.0, _shake - delta * 30.0)
	queue_redraw()


# ---------------------------------------------------------------- desenho
func _txt(pos: Vector2, text: String, size: int, color: Color, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(FONT, pos, text, align, width, size, color)


func _wrap(pos: Vector2, text: String, size: int, color: Color, width: float, lines: int = -1) -> void:
	draw_multiline_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, size, lines, color)


func _preview_params() -> Dictionary:
	var cur: Dictionary = MissionState.params.duplicate()
	if not _decider or _sel < 0 or _sel >= _cards.size():
		return cur
	var fx: Dictionary = _cards[_sel].get("fx", {})
	for k in fx:
		if k == "set":
			for sk in fx["set"]:
				if sk != "objective":
					cur[sk] = fx["set"][sk]
		else:
			cur[k] = float(cur.get(k, 0.0)) + float(fx[k])
	return cur


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0a0e1a"))
	draw_rect(Rect2(Vector2(40, 30), VIEW - Vector2(80, 60)), Color("101a33"))
	draw_rect(Rect2(Vector2(40, 30), VIEW - Vector2(80, 60)), Color("4a6bff"), false, 4.0)
	_txt(Vector2(70, 82), tr("PLANEJAMENTO DA MISSÃO"), 28, Color("8fe0a0"))
	_draw_credits()
	_draw_track()
	_draw_header()
	if _decider:
		_draw_cards()
	else:
		_draw_spectator()
	_draw_gauges()


func _draw_credits() -> void:
	var cur := int(MissionState.p("credits"))
	var after := cur
	if _decider and _sel >= 0 and _sel < _cards.size():
		after = cur + int((_cards[_sel].get("fx", {}) as Dictionary).get("credits", 0.0))
	var r := Rect2(VIEW.x - 420.0, 52.0, 340.0, 56.0)
	draw_rect(r, Color("1d2d5c"))
	draw_rect(r, Color("ffd86a"), false, 3.0)
	_txt(r.position + Vector2(16, 36), tr("CRÉDITOS"), 18, Color("c9d6ff"))
	var s := str(cur) if after == cur else "%d > %d" % [cur, after]
	var col := Color("ffd86a") if after >= cur else Color("ff8a6a")
	_txt(r.position + Vector2(150, 38), s, 26, col, 180.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_track() -> void:
	var x0 := 130.0
	var x1 := VIEW.x - 130.0
	var y := 170.0
	draw_line(Vector2(x0, y), Vector2(x1, y), Color("30467f"), 4.0)
	var owners: Array = MissionState.plan_owners
	for n in range(1, 10):
		var cx := x0 + (x1 - x0) * float(n - 1) / 8.0
		var done: bool = MissionState.cml_done >= n
		var cur: bool = MissionState.plan_cml == n
		var col := Color("3a7a46") if done else (Color("ffd86a") if cur else Color("30467f"))
		var rad := 20.0 + (3.0 * sin(_t * 5.0) if cur else 0.0)
		draw_circle(Vector2(cx, y), rad, col)
		draw_arc(Vector2(cx, y), rad, 0.0, TAU, 24, Color("dfe9ff"), 2.0)
		if done:
			draw_polyline(PackedVector2Array([Vector2(cx - 9, y), Vector2(cx - 2, y + 8), Vector2(cx + 10, y - 9)]), Color("0a0e1a"), 4.0)
		else:
			_txt(Vector2(cx - 30, y + 9), str(n), 24, Color("0a0e1a") if cur else Color("a9bbff"), 60.0, HORIZONTAL_ALIGNMENT_CENTER)
		var owner_txt := ""
		if n == 1:
			owner_txt = tr("Todos votam") if Net.is_online() else tr("Você")
		elif n - 1 < owners.size():
			owner_txt = tr("Você") if not Net.is_online() else tr(ROLE_SHORT.get(int(owners[n - 1]), ""))
		_txt(Vector2(cx - 75, y + 48), owner_txt, 14, Color("ffd86a") if cur else Color("8aa0d8"), 150.0, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_header() -> void:
	var n: int = clampi(MissionState.plan_cml, 1, 9)
	var info: Dictionary = MissionState.CML_INFO[n - 1]
	_txt(Vector2(70, 270), tr(info["title"]), 24, Color("ffffff"))
	_wrap(Vector2(70, 304), tr("Objetivo: ") + tr(info["goal"]), 18, Color("c9d6ff"), VIEW.x - 140.0, 2)
	_wrap(Vector2(70, 358), tr("Para passar: ") + tr(info["pass"]), 16, Color("8aa0d8"), VIEW.x - 140.0, 1)
	var hint: String = MissionState.plan_hint
	if hint != "" and not _decider:
		_wrap(Vector2(70, 392), hint, 18, Color("ffd86a"), VIEW.x - 140.0, 4)


func _draw_cards() -> void:
	_txt(Vector2(70, 394), _title, 20, Color("7dff95"))
	var hint: String = MissionState.plan_hint
	if hint != "":
		# dicas ficam acima dos cartoes, em amarelo
		_wrap(Vector2(70, 422), hint, 16, Color("ffd86a"), VIEW.x - 140.0, 2)
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var r := _card_rect(i)
		var ok: bool = bool(c.get("ok", true))
		var sel := i == _sel
		if sel:
			r.position.y -= 8.0
			if not ok:
				r.position.x += randf_range(-1.0, 1.0) * _shake
		var bg := Color("1b2a5c") if ok else Color("221c30")
		if sel and ok:
			bg = Color("27407f")
		draw_rect(r, bg)
		draw_rect(r, Color("ffd86a") if (sel and ok) else (Color("ff7a7a") if (sel and not ok) else Color("5a74c8")), false, 4.0 if sel else 2.0)
		_wrap(r.position + Vector2(16, 36), String(c.get("label", "")), 22, Color("ffffff") if ok else Color("8a8a9a"), r.size.x - 32.0, 2)
		_wrap(r.position + Vector2(16, 96), String(c.get("desc", "")), 16, Color("c9d6ff") if ok else Color("7a7a8a"), r.size.x - 32.0, 5)
		var y := r.position.y + 200.0
		for chip in MissionState.fx_chips(c.get("fx", {})):
			var col: Color = Color("7dff95") if chip["good"] else Color("ff8a6a")
			if chip.get("neutral", false):
				col = Color("a9bbff")
			if y < r.end.y - 16.0:
				_txt(Vector2(r.position.x + 16, y), String(chip["text"]), 16, col if ok else col.darkened(0.5), r.size.x - 24.0)
				y += 22.0
		if not ok:
			_txt(Vector2(r.position.x + 16, r.end.y - 14), tr("Créditos insuficientes"), 14, Color("ff7a7a"))
	_txt(Vector2(70, 792), tr("Mouse: passe por cima para ver o efeito e clique para escolher   ←/→ + F também funcionam"), 14, Color("8aa0d8"))


func _draw_spectator() -> void:
	var n: int = clampi(MissionState.plan_cml, 1, 9)
	var owners: Array = MissionState.plan_owners
	var who := ""
	if n == 1:
		who = tr("Todos estão votando.")
	elif n - 1 < owners.size():
		who = tr("Vez de: %s") % tr(ROLE_SHORT.get(int(owners[n - 1]), ""))
	_txt(Vector2(70, 430), who, 28, Color("ffd86a"))
	_txt(Vector2(70, 470), tr("Aguarde: a decisão aparece aqui quando for tomada."), 16, Color("8aa0d8"))
	var y := 520.0
	var list: Array = MissionState.decisions
	for k in range(maxi(0, list.size() - 6), list.size()):
		var d: Dictionary = list[k]
		_txt(Vector2(70, y), "CML %d: %s" % [int(d["cml"]), tr(String(d["label"]))], 18, Color("c9d6ff"), VIEW.x - 140.0)
		y += 30.0


func _draw_gauges() -> void:
	var prev := _preview_params()
	var x0 := 70.0
	var y0 := 842.0
	var colw := 340.0
	_txt(Vector2(x0, y0 - 16.0), tr("O PROJETO"), 16, Color("8aa0d8"))
	for i in GAUGES.size():
		var g: Dictionary = GAUGES[i]
		var col := i % 4
		var row := i / 4
		var gx := x0 + col * colw
		var gy := y0 + row * 62.0
		var k: String = g["k"]
		var lo: float = g["lo"]
		var hi: float = g["hi"]
		var cur := float(MissionState.params.get(k, 0.0))
		var nv := float(prev.get(k, cur))
		var bw := 300.0
		_txt(Vector2(gx, gy + 10), tr(g["n"]), 14, Color("c9d6ff"))
		var shown := "%d%%" % int(round(cur * 100.0)) if k == "energy_mult" else str(int(round(cur)))
		if k == "mass" and float(MissionState.params.get("mass_cap", 999.0)) < 900.0:
			shown += " / %d" % int(MissionState.params["mass_cap"])
		_txt(Vector2(gx, gy + 10), shown, 14, Color("ffffff"), bw, HORIZONTAL_ALIGNMENT_RIGHT)
		draw_rect(Rect2(gx, gy + 20, bw, 16), Color("1d2d5c"))
		var f0 := clampf((cur - lo) / (hi - lo), 0.0, 1.0)
		var f1 := clampf((nv - lo) / (hi - lo), 0.0, 1.0)
		draw_rect(Rect2(gx, gy + 20, bw * f0, 16), Color("5a8aff"))
		if not is_equal_approx(f0, f1):
			var better: bool = (nv > cur) == bool(g["up"])
			var c2 := Color("7dff95") if better else Color("ff8a6a")
			var a := minf(f0, f1)
			var b := maxf(f0, f1)
			draw_rect(Rect2(gx + bw * a, gy + 20, bw * (b - a), 16), Color(c2.r, c2.g, c2.b, 0.55 + 0.35 * sin(_t * 8.0)))
		if k == "mass":
			var cap := float(MissionState.params.get("mass_cap", 999.0))
			if cap < 900.0:
				var fc := clampf((cap - lo) / (hi - lo), 0.0, 1.0)
				draw_line(Vector2(gx + bw * fc, gy + 16), Vector2(gx + bw * fc, gy + 40), Color("ffd86a"), 3.0)
		draw_rect(Rect2(gx, gy + 20, bw, 16), Color("30467f"), false, 2.0)
