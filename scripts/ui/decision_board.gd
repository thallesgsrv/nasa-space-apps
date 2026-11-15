extends Control
## Telas graficas da BASE (cientista na Terra), no mesmo estilo da prancheta do planejamento:
## "hub" (painel da base), "solar" (terminal da CME), "monitor" (nave), "forecast" (previsao de perigos)
## e "asteroid" (calculo do impacto). Cartoes com simbolos em vez de menus de texto; mouse (clique)
## ou setas + F. As telas de informacao (monitor/previsao) tem um cartao "Fechar".
## choose(cards) devolve o indice escolhido (-1 = Esc).

signal picked(index: int)

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const VIEW := Vector2(1536, 1024)
const TAG_COLORS := {"REAL": Color("4a8aff"), "RISCO": Color("e0883a"), "FICT": Color("a870e0")}

var kind := "hub"
var _cards: Array = []
var _sel := 0
var _hover := -1
var _t := 0.0
var _info: Dictionary = {}        # dados fixos da tela (asteroide, etc.)


func configure(screen_kind: String, info: Dictionary = {}) -> void:
	kind = screen_kind
	_info = info
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func choose(cards: Array) -> int:
	_cards = cards
	_sel = 0
	for i in cards.size():
		if bool(cards[i].get("ok", true)):
			_sel = i
			break
	return await picked


# ---------------------------------------------------------------- entrada
func _card_rect(i: int) -> Rect2:
	var n := _cards.size()
	var top := 740.0
	var h := 230.0
	if kind == "hub":
		top = 250.0
		h = 360.0
	var w := minf(340.0, (VIEW.x - 160.0 - float(n - 1) * 24.0) / float(maxi(n, 1)))
	var total := w * n + 24.0 * (n - 1)
	return Rect2((VIEW.x - total) / 2.0 + float(i) * (w + 24.0), top, w, h)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var p: Vector2 = (make_input_local(event) as InputEventMouseMotion).position
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
		_sel = (_sel + 1) % maxi(_cards.size(), 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left") and not event.is_echo():
		_sel = (_sel - 1 + _cards.size()) % maxi(_cards.size(), 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_confirm()
	elif event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		picked.emit(-1)


func _confirm() -> void:
	if _sel < 0 or _sel >= _cards.size() or not bool(_cards[_sel].get("ok", true)):
		return
	Audio.sfx("select", 1.35, 0.5)
	picked.emit(_sel)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


# ---------------------------------------------------------------- desenho base
func _txt(pos: Vector2, text: String, size: int, color: Color, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(FONT, pos, text, align, width, size, color)


func _wrap(pos: Vector2, text: String, size: int, color: Color, width: float, lines: int = -1) -> void:
	draw_multiline_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, size, lines, color)


func _titles() -> Array:
	match kind:
		"solar":
			return [tr("TERMINAL SOLAR - CME"), tr("Compare as leituras com o manual de limite seguro e decida.")]
		"monitor":
			return [tr("MONITOR DA NAVE"), tr("Acompanhe a viagem em tempo real.")]
		"forecast":
			return [tr("PREVISÃO DE PERIGOS"), tr("Só a base sabe o que o próximo sorteio reserva.")]
		"asteroid":
			return [tr("OBJETO DETECTADO"), tr("Calcule: tempo = distância ÷ velocidade.")]
	return [tr("PAINEL DA BASE"), tr("Escolha o que fazer.")]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0a0e1a"))
	draw_rect(Rect2(Vector2(40, 30), VIEW - Vector2(80, 60)), Color("101a33"))
	draw_rect(Rect2(Vector2(40, 30), VIEW - Vector2(80, 60)), Color("4a6bff"), false, 4.0)
	var ts := _titles()
	_txt(Vector2(80, 92), String(ts[0]), 30, Color("8fe0a0"))
	_txt(Vector2(80, 130), String(ts[1]), 18, Color("c9d6ff"))
	# selo "BASE - TERRA"
	var r := Rect2(VIEW.x - 380.0, 56.0, 300.0, 50.0)
	draw_rect(r, Color("1d2d5c"))
	draw_rect(r, Color("5a8aff"), false, 3.0)
	_txt(r.position + Vector2(0, 33), tr("BASE · TERRA"), 20, Color("dfe9ff"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	match kind:
		"solar":
			_draw_solar()
		"monitor":
			_draw_monitor()
		"forecast":
			_draw_forecast()
		"asteroid":
			_draw_asteroid()
	_draw_cards()
	_txt(Vector2(80, 990), tr("Mouse: passe por cima e clique   ←/→ + F também funcionam   Esc: fechar"), 14, Color("8aa0d8"))


func _draw_cards() -> void:
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var r := _card_rect(i)
		var ok := bool(c.get("ok", true))
		var sel := i == _sel
		if sel:
			r.position.y -= 8.0
		var bg := Color("27407f") if (sel and ok) else (Color("1b2a5c") if ok else Color("221c30"))
		draw_rect(r, bg)
		draw_rect(r, Color("ffd86a") if (sel and ok) else Color("5a74c8"), false, 4.0 if sel else 2.0)
		var gl: String = String(c.get("glyph", ""))
		var gh := 0.0
		if gl != "":
			_glyph(gl, r.position + Vector2(r.size.x / 2.0, 70.0 if kind == "hub" else 50.0), 56.0 if kind == "hub" else 44.0, Color(c.get("color", Color("ffd86a"))))
			gh = 120.0 if kind == "hub" else 84.0
		_wrap(r.position + Vector2(16, gh + 30.0), String(c.get("label", "")), 22, Color("ffffff") if ok else Color("8a8a9a"), r.size.x - 32.0, 2)
		_wrap(r.position + Vector2(16, gh + 96.0), String(c.get("desc", "")), 16, Color("c9d6ff") if ok else Color("7a7a8a"), r.size.x - 32.0, 4)


# simbolos desenhados com formas (sem imagens)
func _glyph(g: String, c: Vector2, s: float, col: Color) -> void:
	match g:
		"monitor":
			draw_rect(Rect2(c - Vector2(s * 0.6, s * 0.45), Vector2(s * 1.2, s * 0.8)), col, false, 4.0)
			for k in 3:
				var h := s * (0.2 + 0.18 * k)
				draw_rect(Rect2(c + Vector2(-s * 0.4 + k * s * 0.3, s * 0.25 - h), Vector2(s * 0.18, h)), col)
			draw_line(c + Vector2(-s * 0.3, s * 0.55), c + Vector2(s * 0.3, s * 0.55), col, 4.0)
		"forecast":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.55), c + Vector2(s * 0.6, s * 0.45), c + Vector2(-s * 0.6, s * 0.45)]), col)
			draw_rect(Rect2(c + Vector2(-3, -s * 0.2), Vector2(6, s * 0.3)), Color("101a33"))
			draw_rect(Rect2(c + Vector2(-3, s * 0.18), Vector2(6, 6)), Color("101a33"))
		"alert":
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.15), c + Vector2(s * 0.25, -s * 0.5), c + Vector2(s * 0.25, s * 0.5), c + Vector2(-s * 0.5, s * 0.15)]), col)
			for k in 2:
				draw_arc(c + Vector2(s * 0.25, 0), s * (0.3 + 0.22 * k), -0.9, 0.9, 12, col, 4.0)
		"sun":
			draw_circle(c, s * 0.32, col)
			for k in 8:
				var a := float(k) * TAU / 8.0 + _t
				draw_line(c + Vector2(cos(a), sin(a)) * s * 0.46, c + Vector2(cos(a), sin(a)) * s * 0.66, col, 4.0)
		"close":
			draw_line(c + Vector2(-s * 0.35, -s * 0.35), c + Vector2(s * 0.35, s * 0.35), col, 6.0)
			draw_line(c + Vector2(-s * 0.35, s * 0.35), c + Vector2(s * 0.35, -s * 0.35), col, 6.0)
		"ok":
			draw_polyline(PackedVector2Array([c + Vector2(-s * 0.4, 0), c + Vector2(-s * 0.1, s * 0.3), c + Vector2(s * 0.45, -s * 0.35)]), col, 7.0)
		"comm":
			draw_line(c + Vector2(0, s * 0.5), c + Vector2(0, -s * 0.2), col, 5.0)
			draw_circle(c + Vector2(0, -s * 0.25), s * 0.1, col)
			for k in 3:
				draw_arc(c + Vector2(0, -s * 0.25), s * (0.28 + 0.2 * k), -2.2, -0.9, 10, col, 4.0)
		"asteroid":
			draw_circle(c, s * 0.5, col)
			draw_circle(c + Vector2(-s * 0.15, -s * 0.1), s * 0.12, col.darkened(0.35))
			draw_circle(c + Vector2(s * 0.18, s * 0.15), s * 0.09, col.darkened(0.35))
		"reactor":
			draw_arc(c, s * 0.5, 0.0, TAU, 28, col, 5.0)
			draw_circle(c, s * 0.14, col)
			for k in 3:
				var a2 := float(k) * TAU / 3.0 + _t * 0.8
				draw_circle(c + Vector2(cos(a2), sin(a2)) * s * 0.5, s * 0.07, col)
		"clock":
			draw_arc(c, s * 0.5, 0.0, TAU, 28, col, 4.0)
			draw_line(c, c + Vector2(0, -s * 0.35), col, 4.0)
			draw_line(c, c + Vector2(s * 0.25, 0), col, 4.0)


func _bar(pos: Vector2, w: float, frac: float, col: Color, label: String, value: String) -> void:
	_txt(pos + Vector2(0, -8), label, 16, Color("c9d6ff"))
	_txt(pos + Vector2(0, -8), value, 16, Color("ffffff"), w, HORIZONTAL_ALIGNMENT_RIGHT)
	draw_rect(Rect2(pos, Vector2(w, 22)), Color("1d2d5c"))
	draw_rect(Rect2(pos, Vector2(w * clampf(frac, 0.0, 1.0), 22)), col)
	draw_rect(Rect2(pos, Vector2(w, 22)), Color("30467f"), false, 2.0)


# ---------------------------------------------------------------- telas
func _draw_solar() -> void:
	var flux := Solar.live_flux()
	var ang := Solar.live_angle()
	# fluxo de raios-X (barra com a zona de perigo do manual)
	var x := 100.0
	var y := 260.0
	var w := 520.0
	var maxv := 12.0
	_txt(Vector2(x, y - 40), tr("FLUXO DE RAIOS-X"), 20, Color("ffd86a"))
	draw_rect(Rect2(x, y, w, 44), Color("1d2d5c"))
	var lim := w * Solar.HIT_FLUX / maxv
	draw_rect(Rect2(x + lim, y, w - lim, 44), Color(0.9, 0.25, 0.2, 0.35))
	draw_rect(Rect2(x, y, w * clampf(flux / maxv, 0.0, 1.0), 44), Color("e8c23a"))
	draw_line(Vector2(x + lim, y - 10), Vector2(x + lim, y + 54), Color("ff6a5a"), 4.0)
	_txt(Vector2(x + lim - 90, y + 80), tr("limite %.1f") % Solar.HIT_FLUX, 16, Color("ff8a7a"), 180.0, HORIZONTAL_ALIGNMENT_CENTER)
	draw_rect(Rect2(x, y, w, 44), Color("30467f"), false, 3.0)
	_txt(Vector2(x, y + 100), "%.1f" % flux, 44, Color("ffffff"))
	# angulo da trajetoria (mostrador com o cone que atinge a rota da nave)
	var c := Vector2(930, 430)
	var R := 190.0
	_txt(Vector2(c.x - 200, 214), tr("ÂNGULO DA TRAJETÓRIA"), 20, Color("ffd86a"), 400.0, HORIZONTAL_ALIGNMENT_CENTER)
	draw_arc(c, R, -PI, 0.0, 40, Color("30467f"), 6.0)
	var a0 := -PI / 2.0 - deg_to_rad(Solar.HIT_ANGLE)
	var a1 := -PI / 2.0 + deg_to_rad(Solar.HIT_ANGLE)
	draw_arc(c, R - 3.0, a0, a1, 16, Color(0.95, 0.3, 0.25, 0.9), 14.0)
	for k in range(-9, 10):
		var a := -PI / 2.0 + deg_to_rad(float(k) * 10.0)
		draw_line(c + Vector2(cos(a), sin(a)) * (R - 14.0), c + Vector2(cos(a), sin(a)) * (R + 8.0), Color("8aa0d8"), 2.0)
	var na := -PI / 2.0 + deg_to_rad(clampf(ang, -90.0, 90.0))
	draw_line(c, c + Vector2(cos(na), sin(na)) * (R - 20.0), Color("ffffff"), 5.0)
	draw_circle(c, 10.0, Color("ffffff"))
	# a nave (triangulo) na base do mostrador
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -26), c + Vector2(14, 8), c + Vector2(-14, 8)]), Color("5a8aff"))
	_txt(Vector2(c.x - 280, c.y + 50), tr("%+.0f graus  (0 = direto na rota da nave)") % ang, 18, Color("ffffff"), 560.0, HORIZONTAL_ALIGNMENT_CENTER)
	# origem do dado (selo colorido) e manual
	var tag := String(Solar.source_tag)
	var tcol: Color = TAG_COLORS.get(tag, Color("5a74c8"))
	var br := Rect2(100, 600, 140, 38)
	draw_rect(br, tcol)
	_txt(br.position + Vector2(0, 26), tag if tag != "" else "-", 20, Color("0a0e1a"), br.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_wrap(Vector2(260, 618), Solar.source_label, 16, Color("c9d6ff"), 520.0, 3)
	draw_rect(Rect2(1150, 250, 330, 300), Color("16264d"))
	draw_rect(Rect2(1150, 250, 330, 300), Color("5a74c8"), false, 2.0)
	_txt(Vector2(1170, 286), tr("MANUAL DE LIMITE SEGURO"), 16, Color("ffd86a"))
	_wrap(Vector2(1170, 322), tr("A tempestade atinge a nave se o fluxo for MAIOR OU IGUAL a %.1f E o ângulo estiver entre -%d e +%d graus. Fora disso, a ejeção passa longe ou é fraca demais.") % [Solar.HIT_FLUX, int(Solar.HIT_ANGLE), int(Solar.HIT_ANGLE)], 16, Color("dfe9ff"), 290.0, 10)


func _draw_monitor() -> void:
	var s := maxi(0, int(ceil(Voyage.time_left)))
	_glyph("clock", Vector2(140, 280), 70.0, Color("ffd86a"))
	_txt(Vector2(210, 270), "%02d:%02d" % [s / 60, s % 60], 52, Color("ffffff"))
	_txt(Vector2(210, 306), tr("tempo restante   Rota: %s") % tr(Voyage.route), 18, Color("c9d6ff"))
	_bar(Vector2(100, 420), 640.0, Voyage.progress / 100.0, Color("3ac28a"), tr("PROGRESSO"), "%d%%" % int(Voyage.progress))
	_bar(Vector2(100, 500), 640.0, Voyage.energy / 100.0, Color("e8c23a"), tr("ENERGIA"), "%d%%" % int(Voyage.energy))
	_bar(Vector2(100, 580), 640.0, Voyage.fuel / 100.0, Color("e07a3a"), tr("COMBUSTÍVEL"), "%d%%" % int(Voyage.fuel))
	_bar(Vector2(100, 660), 640.0, (Voyage.mass - 80.0) / 60.0, Color("5a8aff"), tr("MASSA"), "%d" % int(Voyage.mass))
	# evento em andamento
	var r := Rect2(850, 250, 590, 300)
	draw_rect(r, Color("16264d"))
	draw_rect(r, Color("5a74c8"), false, 2.0)
	_txt(r.position + Vector2(24, 40), tr("EVENTO EM ANDAMENTO"), 18, Color("ffd86a"))
	if Voyage.event == "":
		_glyph("ok", r.position + Vector2(r.size.x / 2.0, 150), 80.0, Color("7dff95"))
		_txt(r.position + Vector2(0, 250), tr("Tudo calmo por enquanto."), 20, Color("c9d6ff"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_glyph(_event_glyph(Voyage.event), r.position + Vector2(r.size.x / 2.0, 150), 90.0, Color("ff7a5a"))
		_wrap(r.position + Vector2(24, 250), tr(Voyage.KIND_NAMES[Voyage.event]), 20, Color("ffffff"), r.size.x - 48.0, 2)
	if not Voyage.comms_ok():
		_txt(Vector2(850, 600), tr("SEM CONTATO com a nave (%d s)") % ceili(Voyage.blackout_left), 22, Color("ff6a5a"))


func _event_glyph(ev: String) -> String:
	return {"comm": "comm", "asteroid": "asteroid", "reactor": "reactor"}.get(ev, "forecast")


func _draw_forecast() -> void:
	# proximo sorteio
	_glyph("clock", Vector2(140, 270), 70.0, Color("ffd86a"))
	_bar(Vector2(220, 270), 520.0, 1.0 - Voyage.next_in / Voyage.EVENT_INTERVAL, Color("5a8aff"), tr("PRÓXIMO SORTEIO"), "%d s" % int(ceil(Voyage.next_in)))
	var r := Rect2(100, 360, 640, 170)
	draw_rect(r, Color("16264d"))
	draw_rect(r, Color("5a74c8"), false, 2.0)
	if Voyage.next_event != "":
		_glyph(_event_glyph(Voyage.next_event), r.position + Vector2(90, 85), 80.0, Color("ffb04a"))
		_txt(r.position + Vector2(170, 56), tr("PREVISTO"), 16, Color("ffd86a"))
		_wrap(r.position + Vector2(170, 92), tr(Voyage.KIND_NAMES[Voyage.next_event]), 22, Color("ffffff"), 440.0, 3)
	else:
		_glyph("ok", r.position + Vector2(90, 85), 80.0, Color("7dff95"))
		_wrap(r.position + Vector2(170, 76), tr("Nada de perigoso no próximo intervalo."), 22, Color("ffffff"), 440.0, 3)
	# em andamento
	var q := Rect2(790, 250, 650, 460)
	draw_rect(q, Color("16264d"))
	draw_rect(q, Color("5a74c8"), false, 2.0)
	_txt(q.position + Vector2(24, 40), tr("EM ANDAMENTO"), 18, Color("ffd86a"))
	if Voyage.event == "asteroid":
		_glyph("asteroid", q.position + Vector2(100, 150), 90.0, Color("c8b0a0"))
		var speed := float(Voyage.asteroid["speed"])
		_txt(q.position + Vector2(190, 120), tr("velocidade: %.1f km/s") % speed, 22, Color("ffffff"))
		_txt(q.position + Vector2(190, 160), tr("distância: %d km") % int(speed * float(Voyage.asteroid["eta"])), 22, Color("ffffff"))
		draw_rect(Rect2(q.position + Vector2(40, 230), Vector2(570, 64)), Color("27407f"))
		_txt(q.position + Vector2(40, 270), tr("tempo = distância ÷ velocidade"), 22, Color("ffd86a"), 570.0, HORIZONTAL_ALIGNMENT_CENTER)
	elif Voyage.event == "reactor":
		_glyph("reactor", q.position + Vector2(100, 130), 90.0, Color("ff7a5a"))
		_txt(q.position + Vector2(190, 110), tr("Alvos das válvulas"), 20, Color("ffffff"))
		_txt(q.position + Vector2(190, 140), tr("(N, L, S, O)"), 16, Color("c9d6ff"))
		for i in 5:
			var t: int = Voyage.reactor["targets"][i]
			var cx := q.position.x + 80.0 + float(i) * 118.0
			var cy := q.position.y + 300.0
			draw_arc(Vector2(cx, cy), 40.0, 0.0, TAU, 24, Color("5a74c8"), 4.0)
			var dirs := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
			var dir: Vector2 = dirs[t]
			draw_line(Vector2(cx, cy), Vector2(cx, cy) + dir * 36.0, Color("ffd86a"), 6.0)
			if bool(Voyage.reactor["two"][i]):
				draw_line(Vector2(cx, cy), Vector2(cx, cy) - dir * 36.0, Color("ffd86a"), 6.0)
			_txt(Vector2(cx - 40, cy + 70), "V%d  %s" % [i + 1, tr(Voyage.POS_NAMES[t])], 16, Color("c9d6ff"), 80.0, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		_glyph("ok", q.position + Vector2(q.size.x / 2.0, 180), 90.0, Color("7dff95"))
		_txt(q.position + Vector2(0, 330), tr("Nenhum evento em andamento."), 20, Color("c9d6ff"), q.size.x, HORIZONTAL_ALIGNMENT_CENTER)


func _draw_asteroid() -> void:
	var speed: float = float(_info.get("speed", 0.0))
	var dist: int = int(_info.get("dist", 0))
	_glyph("asteroid", Vector2(200, 330), 150.0, Color("c8b0a0"))
	_txt(Vector2(380, 290), tr("velocidade: %.1f km/s") % speed, 32, Color("ffffff"))
	_txt(Vector2(380, 346), tr("distância: %d km") % dist, 32, Color("ffffff"))
	draw_rect(Rect2(380, 400, 700, 80), Color("27407f"))
	draw_rect(Rect2(380, 400, 700, 80), Color("ffd86a"), false, 3.0)
	_txt(Vector2(380, 452), tr("tempo = distância ÷ velocidade"), 28, Color("ffd86a"), 700.0, HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(100, 640), tr("Quando ele atinge a nave?"), 26, Color("7dff95"))
