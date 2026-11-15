extends Control
## Relatorio pos-missao em 3 paginas: Resumo (nota e barras), Eventos (linha do tempo com selos) e
## Decisoes (causas e planejamento). Setas navegam, F avanca (na ultima pagina fecha), Esc fecha.
## Os dados vem de MissionState.report (montado em build_report).

signal closed

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const VIEW := Vector2(1536, 1024)
const GRADE_COLORS := {"A": Color("7dff95"), "B": Color("5ad0c0"), "C": Color("ffd86a"), "D": Color("e0883a"), "E": Color("ff6a5a")}
const TAG_COLORS := {"REAL": Color("4a8aff"), "RISCO": Color("e0883a"), "FICT": Color("a870e0")}
const PAGES := 3

var _page := 0
var _t := 0.0
var _anim := 0.0       # 0..1: barras e nota "enchem" ao abrir a pagina


func configure() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		closed.emit()
	elif event.is_action_pressed("move_right") and not event.is_echo():
		_go(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left") and not event.is_echo():
		_go(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if _page >= PAGES - 1:
			closed.emit()
		else:
			_go(1)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		if p.x > VIEW.x / 2.0:
			if _page >= PAGES - 1:
				closed.emit()
			else:
				_go(1)
		else:
			_go(-1)


func _go(d: int) -> void:
	var n := clampi(_page + d, 0, PAGES - 1)
	if n != _page:
		_page = n
		_anim = 0.0
		Audio.sfx("select", 1.0, 0.3)


func _process(delta: float) -> void:
	_t += delta
	_anim = minf(1.0, _anim + delta * 1.6)
	queue_redraw()


func _txt(pos: Vector2, text: String, size: int, color: Color, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(FONT, pos, text, align, width, size, color)


func _wrap(pos: Vector2, text: String, size: int, color: Color, width: float, lines: int = -1) -> void:
	draw_multiline_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, size, lines, color)


func _draw() -> void:
	var rep: Dictionary = MissionState.report
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0a0e1a"))
	draw_rect(Rect2(Vector2(40, 30), VIEW - Vector2(80, 60)), Color("101a33"))
	draw_rect(Rect2(Vector2(40, 30), VIEW - Vector2(80, 60)), Color("4a6bff"), false, 4.0)
	_txt(Vector2(80, 92), tr("RELATÓRIO PÓS-MISSÃO"), 30, Color("8fe0a0"))
	var titles := [tr("Resumo"), tr("Eventos da missão"), tr("Suas decisões")]
	_txt(Vector2(80, 130), "%d/%d  %s" % [_page + 1, PAGES, titles[_page]], 18, Color("c9d6ff"))
	if rep.is_empty():
		return
	match _page:
		0:
			_page_summary(rep)
		1:
			_page_events(rep)
		2:
			_page_decisions(rep)
	# rodape: bolinhas de pagina e dicas
	for k in PAGES:
		draw_circle(Vector2(VIEW.x / 2.0 - 30.0 + k * 30.0, 975), 8.0, Color("ffd86a") if k == _page else Color("30467f"))
	_txt(Vector2(80, 982), tr("←/→ página     F: continuar     Esc: fechar"), 14, Color("8aa0d8"))
	if _page < PAGES - 1:
		_txt(Vector2(VIEW.x - 380.0, 982), tr("F: próxima página"), 14, Color("ffd86a"), 300.0, HORIZONTAL_ALIGNMENT_RIGHT)
	else:
		_txt(Vector2(VIEW.x - 380.0, 982), tr("F: fechar o relatório"), 14, Color("ffd86a"), 300.0, HORIZONTAL_ALIGNMENT_RIGHT)


func _page_summary(rep: Dictionary) -> void:
	var grade := String(rep.get("grade", "E"))
	var col: Color = GRADE_COLORS.get(grade, Color("ffffff"))
	var score := float(rep.get("score", 0.0))
	# medalha
	var m := Rect2(110, 210, 360, 380)
	draw_rect(m, Color("16264d"))
	draw_rect(m, col, false, 6.0)
	_txt(m.position + Vector2(0, 54), tr("NOTA FINAL"), 22, Color("c9d6ff"), m.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	var bob := 4.0 * sin(_t * 3.0)
	_txt(m.position + Vector2(0, 260 + bob), grade, 190, col, m.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_txt(m.position + Vector2(0, 345), "%d / 100" % int(round(score * _anim)), 30, Color("ffffff"), m.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# objetivo e creditos
	_txt(Vector2(110, 640), tr("OBJETIVO"), 16, Color("ffd86a"))
	_wrap(Vector2(110, 672), String(rep.get("objective", "")), 22, Color("ffffff"), 380.0, 2)
	var cr := Rect2(110, 750, 360, 86)
	draw_rect(cr, Color("1d2d5c"))
	draw_rect(cr, Color("ffd86a"), false, 3.0)
	_txt(cr.position + Vector2(18, 34), tr("CRÉDITOS QUE SOBRARAM"), 16, Color("c9d6ff"))
	_txt(cr.position + Vector2(18, 72), str(int(rep.get("credits", 0))), 30, Color("ffd86a"))
	# barras
	var sc: Dictionary = rep.get("scores", {})
	var rows := [
		["sci", tr("Ciência"), Color("5ad0c0"), 30],
		["ship", tr("Nave"), Color("5a8aff"), 20],
		["dec", tr("Decisões"), Color("a870e0"), 15],
		["eff", tr("Eficiência"), Color("e8c23a"), 10],
		["bud", tr("Orçamento"), Color("e0883a"), 10],
	]
	if bool(rep.get("has_coop", false)):
		rows.append(["coop", tr("Cooperação com a base"), Color("7dff95"), 15])
	var y := 220.0
	for r in rows:
		var v := float(sc.get(r[0], 0.0))
		_txt(Vector2(560, y), String(r[1]), 22, Color("ffffff"))
		_txt(Vector2(560, y), "%d" % int(round(v * _anim)), 22, r[2], 760.0, HORIZONTAL_ALIGNMENT_RIGHT)
		_txt(Vector2(1330, y), tr("peso %d%%") % int(r[3]), 14, Color("8aa0d8"), 110.0, HORIZONTAL_ALIGNMENT_RIGHT)
		draw_rect(Rect2(560, y + 14, 760, 26), Color("1d2d5c"))
		draw_rect(Rect2(560, y + 14, 760.0 * clampf(v * _anim / 100.0, 0.0, 1.0), 26), r[2])
		draw_rect(Rect2(560, y + 14, 760, 26), Color("30467f"), false, 2.0)
		y += 100.0
	if bool(rep.get("has_coop", false)):
		_txt(Vector2(560, y - 40), tr("Ações da base: %d") % int(rep.get("coop_actions", 0)), 14, Color("8aa0d8"))


func _page_events(rep: Dictionary) -> void:
	var events: Array = rep.get("events", [])
	var y := 190.0
	if events.is_empty():
		_txt(Vector2(80, 300), tr("Nenhum evento relevante."), 26, Color("c9d6ff"))
	for e in events:
		var tag := String(e.get("tag", ""))
		var tcol: Color = TAG_COLORS.get(tag, Color("5a74c8"))
		var row := Rect2(80, y, VIEW.x - 160.0, 92)
		draw_rect(row, Color("16264d"))
		draw_rect(row, Color("30467f"), false, 2.0)
		var chip := Rect2(row.position + Vector2(16, 24), Vector2(120, 42))
		draw_rect(chip, tcol)
		_txt(chip.position + Vector2(0, 29), tag, 18, Color("0a0e1a"), chip.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_wrap(row.position + Vector2(160, 42), String(e.get("label", "")), 24, Color("ffffff"), 900.0, 1)
		var cause := String(e.get("cause", ""))
		if cause != "":
			_wrap(row.position + Vector2(160, 72), cause, 15, Color("ffb04a"), 960.0, 1)
		var ok = e.get("ok", null)
		var oc := row.position + Vector2(row.size.x - 120.0, 46)
		if ok == true:
			draw_polyline(PackedVector2Array([oc + Vector2(-18, 0), oc + Vector2(-6, 14), oc + Vector2(18, -14)]), Color("7dff95"), 7.0)
			_txt(oc + Vector2(-70, 40), tr("superado"), 14, Color("7dff95"), 140.0, HORIZONTAL_ALIGNMENT_CENTER)
		elif ok == false:
			draw_line(oc + Vector2(-14, -14), oc + Vector2(14, 14), Color("ff6a5a"), 7.0)
			draw_line(oc + Vector2(-14, 14), oc + Vector2(14, -14), Color("ff6a5a"), 7.0)
			_txt(oc + Vector2(-70, 40), tr("falhou"), 14, Color("ff6a5a"), 140.0, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			_txt(oc + Vector2(-70, 8), "-", 26, Color("8aa0d8"), 140.0, HORIZONTAL_ALIGNMENT_CENTER)
		y += 106.0
		if y > 760.0:
			break
	# legenda dos selos
	var items := [["REAL", tr("registro científico real")], ["RISCO", tr("fenômeno real, ocorrência simulada")], ["FICT", tr("desafio fictício do jogo")]]
	var ly := 770.0
	for it in items:
		var c: Color = TAG_COLORS[it[0]]
		draw_rect(Rect2(80, ly, 110, 34), c)
		_txt(Vector2(80, ly + 24), String(it[0]), 16, Color("0a0e1a"), 110.0, HORIZONTAL_ALIGNMENT_CENTER)
		_txt(Vector2(206, ly + 24), String(it[1]), 16, Color("c9d6ff"))
		ly += 46.0


func _page_decisions(rep: Dictionary) -> void:
	_txt(Vector2(80, 200), tr("O QUE SUAS DECISÕES CAUSARAM"), 20, Color("ffd86a"))
	var causal: Array = rep.get("causal", [])
	var y := 240.0
	if causal.is_empty():
		_txt(Vector2(80, y + 30), tr("Nada a destacar."), 18, Color("c9d6ff"))
	for c in causal:
		draw_polyline(PackedVector2Array([Vector2(86, y + 8), Vector2(100, y + 20), Vector2(86, y + 32)]), Color("ffd86a"), 4.0)
		_wrap(Vector2(118, y + 26), String(c), 17, Color("dfe9ff"), 640.0, 3)
		y += 92.0
		if y > 880.0:
			break
	_txt(Vector2(840, 200), tr("PLANEJAMENTO (CML)"), 20, Color("ffd86a"))
	var plan: Array = rep.get("plan", [])
	var py := 240.0
	for d in plan:
		var r := Rect2(840, py, 616, 40)
		draw_rect(r, Color("16264d"))
		_txt(r.position + Vector2(12, 28), "CML %d" % int(d["cml"]), 16, Color("5a8aff"), 90.0)
		_wrap(r.position + Vector2(110, 28), String(d["label"]), 16, Color("ffffff"), 490.0, 1)
		py += 48.0
		if py > 900.0:
			break
