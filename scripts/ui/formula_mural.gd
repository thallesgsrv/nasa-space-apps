class_name FormulaMural
extends Control
## Terminal do mural de formulas (laboratorio, lado da Terra).
## Uma formula aparece com os valores de um problema; arraste o cartao com a resposta certa ate o
## campo "?" (ou use setas + F). Modos sorteados: dado o valor -> achar o RESULTADO, ou dado o
## resultado -> achar a variavel X. No modo DIFICIL, antes, arraste os valores do enunciado para as
## variaveis certas da formula. Errar tira tempo e troca os numeros (a formula continua).
## Acertos dao bonus no recurso ligado a formula (tempo, comunicacao, energia, massa).
## Esc sai.  O resultado fica em `result` (solved, total, bonuses).

signal closed

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const VIEW := Vector2(1536, 1024)
const ROUNDS := 3
const ERROR_PENALTY := 8.0
const BOX := Vector2(230, 120)

# op "mul": v0 = v1 x v2    |    op "div": v0 = v1 / v2    (v0 e sempre o resultado)
const FORMULAS := [
	{"id": "vel", "op": "div", "kind": "time", "amount": 12.0, "res": "tempo",
	 "vars": [["v", "Velocidade", "km/h"], ["d", "Distância", "km"], ["t", "Tempo", "h"]]},
	{"id": "com", "op": "div", "kind": "comms", "amount": 6.0, "res": "comunicações",
	 "vars": [["t", "Tempo do sinal", "s"], ["d", "Distância", "mil km"], ["c", "Velocidade do sinal", "mil km/s"]]},
	{"id": "ene", "op": "mul", "kind": "energy", "amount": 8.0, "res": "energia",
	 "vars": [["E", "Energia", "kWh"], ["P", "Potência", "kW"], ["t", "Tempo", "h"]]},
	{"id": "dad", "op": "mul", "kind": "comms", "amount": 6.0, "res": "comunicações",
	 "vars": [["D", "Dados", "MB"], ["r", "Taxa", "MB/s"], ["t", "Tempo", "s"]]},
	{"id": "for", "op": "mul", "kind": "mass", "amount": 2.0, "res": "massa",
	 "vars": [["F", "Força", "N"], ["m", "Massa", "kg"], ["a", "Aceleração", "m/s²"]]},
]
const KIND_TEXT := {"time": "+%d s de tempo", "comms": "-%d s de apagão (comunicação)", "energy": "+%d%% de energia", "mass": "-%d%% de massa (menos combustível gasto)"}

var hard := false
var result: Dictionary = {}

var _time_left := 80.0
var _order: Array = []
var _round := 0
var _solved := 0
var _bonuses: Array = []
var _f: Dictionary
var _vals: Array = [0, 0, 0]
var _hidden := 0                 # indice da variavel desconhecida (0 = resultado)
var _items: Array = []           # chips e cartoes
var _slots: Array = []           # indice de variavel -> {rect, filled(bool), is_answer}
var _drag := -1
var _drag_off := Vector2.ZERO
var _sel := 0                    # item selecionado (teclado)
var _slot_sel := 0               # slot destacado (teclado)
var _msg := ""
var _msg_t := 0.0
var _msg_ok := true
var _next_in := -1.0
var _over := false
var _shake := 0.0
var _statement: Label


func configure(hard_mode: bool = false) -> void:
	hard = hard_mode
	_time_left = 100.0 if hard else 80.0
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var idx := [0, 1, 2, 3, 4]
	idx.shuffle()
	for i in ROUNDS:
		_order.append(FORMULAS[idx[i]])
	_statement = Label.new()
	_statement.add_theme_font_override("font", FONT)
	_statement.add_theme_font_size_override("font_size", 24)
	_statement.add_theme_color_override("font_color", Color("d8e4ff"))
	_statement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_statement.position = Vector2(180, 170)
	_statement.size = Vector2(VIEW.x - 360.0, 110)
	_statement.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_statement.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_statement)
	_new_problem(_order[0])


# ---------------------------------------------------------------- problemas
func _new_problem(f: Dictionary) -> void:
	_f = f
	var a := 0
	var b := 0
	match f["id"]:
		"vel":
			b = [2, 3, 4, 5][randi() % 4]; a = [15, 20, 25, 30, 40][randi() % 5]
			_vals = [a, a * b, b]
		"com":
			b = [100, 200, 300][randi() % 3]; a = [2, 3, 4, 5][randi() % 4]
			_vals = [a, a * b, b]
		"ene":
			a = [2, 3, 4, 5, 6][randi() % 5]; b = [2, 3, 4, 5, 6, 8][randi() % 6]
			_vals = [a * b, a, b]
		"dad":
			a = [5, 8, 10, 12][randi() % 4]; b = [3, 4, 5, 6][randi() % 4]
			_vals = [a * b, a, b]
		_:
			a = [2, 3, 4, 5, 10][randi() % 5]; b = [2, 3, 4, 5][randi() % 4]
			_vals = [a * b, a, b]
	_hidden = 0 if randf() < 0.5 else (1 + randi() % 2)
	_build_layout()


func _build_layout() -> void:
	_items.clear()
	_slots.clear()
	_drag = -1
	_sel = 0
	var total := BOX.x * 3.0 + 160.0
	var x0 := (VIEW.x - total) / 2.0
	var xs := [x0, x0 + BOX.x + 80.0, x0 + BOX.x * 2.0 + 160.0]   # v0 = v1 op v2
	var vars: Array = _f["vars"]
	for i in 3:
		_slots.append({"rect": Rect2(Vector2(xs[i], 380), BOX), "filled": false, "answer": i == _hidden})
	# o enunciado
	var parts: Array = []
	for i in 3:
		if i != _hidden:
			parts.append("%s = %s %s" % [tr(vars[i][1]), _vals[i], tr(vars[i][2])])
	_statement.text = tr("Dados: %s. Calcule: %s (%s).") % ["; ".join(PackedStringArray(parts)), tr(vars[_hidden][1]), vars[_hidden][0]]
	if hard:
		_statement.text += "\n" + tr("Primeiro arraste cada valor para a variável certa da fórmula.")
		var givens: Array = []
		for i in 3:
			if i != _hidden:
				givens.append(i)
		givens.shuffle()
		var cx := (VIEW.x - (givens.size() * 250.0 - 20.0)) / 2.0
		for k in givens.size():
			var i: int = givens[k]
			var p := Vector2(cx + k * 250.0, 590)
			_items.append({"kind": "chip", "var": i, "text": "%s %s" % [_vals[i], tr(vars[i][2])], "home": p, "pos": p, "size": Vector2(230, 80), "used": false})
		for i in 3:
			if i != _hidden:
				_slots[i]["filled"] = false
	else:
		for i in 3:
			if i != _hidden:
				_slots[i]["filled"] = true
	# cartoes de resposta
	var ans: int = _vals[_hidden]
	var opts: Array = [ans]
	var cand: Array = [ans + 1, maxi(1, ans - 1), ans * 2, ans + 2, ans + 3, maxi(1, ans - 2), ans + 5, maxi(1, ans / 2), ans * 3]
	var others: Array = []
	for i in 3:
		if i != _hidden:
			others.append(_vals[i])
	cand.append(others[0] + others[1])
	cand.append(absi(others[0] - others[1]))
	cand.shuffle()
	for c in cand:
		if opts.size() >= 4:
			break
		if c > 0 and not opts.has(c):
			opts.append(c)
	opts.shuffle()
	var cw := 200.0
	var ox := (VIEW.x - (opts.size() * (cw + 30.0) - 30.0)) / 2.0
	for k in opts.size():
		var p := Vector2(ox + k * (cw + 30.0), 790)
		_items.append({"kind": "card", "value": opts[k], "text": "%s %s" % [opts[k], tr(vars[_hidden][2])], "home": p, "pos": p, "size": Vector2(cw, 90), "used": false})
	_slot_sel = _first_open_slot()


func _first_open_slot() -> int:
	for i in 3:
		if i != _hidden and not _slots[i]["filled"]:
			return i
	return _hidden


func _cards_enabled() -> bool:
	for i in 3:
		if i != _hidden and not _slots[i]["filled"]:
			return false
	return true


# ---------------------------------------------------------------- desenho
func _draw() -> void:
	var sh := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("0a0e1a"))
	draw_rect(Rect2(Vector2(110, 90) + sh, Vector2(VIEW.x - 220.0, 850)), Color("101a33"))
	draw_rect(Rect2(Vector2(110, 90) + sh, Vector2(VIEW.x - 220.0, 850)), Color("4a6bd8"), false, 4.0)
	_txt(Vector2(140, 134) + sh, tr("MURAL DE FÓRMULAS"), 26, Color("8fe0a0"), -1)
	_txt(Vector2(VIEW.x - 700.0, 134) + sh, tr("Tempo: %d s    Resolvidos: %d/%d") % [int(ceil(_time_left)), _solved, ROUNDS], 22, Color("eef3ff"), 560, HORIZONTAL_ALIGNMENT_RIGHT)
	# formula: v0 = v1 op v2
	var vars: Array = _f["vars"]
	var title := ("%s = %s %s %s" % [vars[0][0], vars[1][0], "÷" if _f["op"] == "div" else "×", vars[2][0]])
	_txt(Vector2(0, 340) + sh, title, 34, Color("ffd86a"), VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
	var ops := ["=", "÷" if _f["op"] == "div" else "×"]
	for k in 2:
		var a: Rect2 = _slots[k]["rect"]
		var b: Rect2 = _slots[k + 1]["rect"]
		_txt(Vector2(a.end.x, 458) + sh, ops[k], 40, Color("eef3ff"), b.position.x - a.end.x, HORIZONTAL_ALIGNMENT_CENTER)
	for i in 3:
		var S: Dictionary = _slots[i]
		var r: Rect2 = S["rect"]
		r.position += sh
		var is_ans: bool = S["answer"]
		var filled: bool = S["filled"] or (is_ans and false)
		var col := Color("16264d")
		if is_ans:
			col = Color("2a3a14") if _cards_enabled() else Color("2a2230")
		draw_rect(r, col)
		var border := Color("8aa0ff")
		if is_ans:
			border = Color("ffd86a") if _cards_enabled() else Color("7a6a80")
		if i == _slot_sel and _drag < 0:
			border = Color("ffffff")
		draw_rect(r, border, false, 3.0 if not is_ans else 4.0)
		_txt(r.position + Vector2(0, 28), "%s  %s" % [vars[i][0], tr(vars[i][1])], 16, Color("a9bbff"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		if is_ans:
			_txt(r.position + Vector2(0, 82), "?", 40, Color("ffd86a"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		elif filled:
			_txt(r.position + Vector2(0, 86), "%s %s" % [_vals[i], tr(vars[i][2])], 28, Color("ffffff"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		else:
			_txt(r.position + Vector2(0, 82), "...", 34, Color("5a6aa0"), r.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	# itens
	var enabled := _cards_enabled()
	for n in _items.size():
		var it: Dictionary = _items[n]
		if it["used"]:
			continue
		var dim: bool = it["kind"] == "card" and not enabled
		var rr := Rect2(it["pos"], it["size"])
		var c1 := Color("2c4a9a") if it["kind"] == "chip" else Color("3a7a46")
		if dim:
			c1 = c1.darkened(0.5)
		if n == _drag:
			rr.position += Vector2(0, -6)
		draw_rect(rr, c1)
		draw_rect(rr, Color("ffffff") if n == _sel and _drag < 0 else Color("b8c8ff"), false, 4.0 if n == _sel else 2.0)
		_txt(rr.position + Vector2(0, rr.size.y * 0.62), it["text"], 22, Color("ffffff") if not dim else Color("8a8a9a"), rr.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	_txt(Vector2(140, 725), tr("Valores do enunciado") if hard else "", 16, Color("8aa0d8"), -1)
	_txt(Vector2(140, 770), tr("Respostas"), 16, Color("8aa0d8"), -1)
	var hint := tr("Arraste com o mouse (ou ←/→ escolhe, ↑/↓ muda o campo, F coloca)   Esc: sair")
	_txt(Vector2(140, 925), hint, 14, Color("8aa0d8"), VIEW.x - 280.0)
	if _msg_t > 0.0:
		_txt(Vector2(0, 300), _msg, 28, Color("7dff95") if _msg_ok else Color("ff7a7a"), VIEW.x, HORIZONTAL_ALIGNMENT_CENTER)
	if _over:
		draw_rect(Rect2(Vector2(170, 250), Vector2(VIEW.x - 340.0, 520)), Color(0.02, 0.04, 0.1, 0.96))
		draw_rect(Rect2(Vector2(170, 250), Vector2(VIEW.x - 340.0, 520)), Color("8aa0ff"), false, 4.0)
		var y := 320.0
		for line in _result_lines():
			_txt(Vector2(200, y), line, 24, Color("ffffff"), VIEW.x - 400.0, HORIZONTAL_ALIGNMENT_CENTER)
			y += 52.0


func _txt(pos: Vector2, text: String, size: int, color: Color, width: float, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(FONT, pos, text, align, width, size, color)


# ---------------------------------------------------------------- loop / entrada
func _process(delta: float) -> void:
	_shake = maxf(0.0, _shake - delta * 30.0)
	_msg_t = maxf(0.0, _msg_t - delta)
	if not _over:
		_time_left -= delta
		if _next_in >= 0.0:
			_next_in -= delta
			if _next_in < 0.0:
				_advance()
		if _time_left <= 0.0:
			_time_left = 0.0
			_finish()
	queue_redraw()


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
	if _next_in >= 0.0:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		if event.pressed:
			for n in range(_items.size() - 1, -1, -1):
				var it: Dictionary = _items[n]
				if not it["used"] and Rect2(it["pos"], it["size"]).has_point(p):
					if it["kind"] == "card" and not _cards_enabled():
						_say(tr("Primeiro coloque os valores do enunciado."), false)
						return
					_drag = n
					_sel = n
					_drag_off = (it["pos"] as Vector2) - p
					return
		elif _drag >= 0:
			_drop(p)
	elif event is InputEventMouseMotion and _drag >= 0:
		var m: Vector2 = (make_input_local(event) as InputEventMouseMotion).position
		_items[_drag]["pos"] = m + _drag_off
	elif event.is_action_pressed("move_right") and not event.is_echo():
		_move_sel(1)
	elif event.is_action_pressed("move_left") and not event.is_echo():
		_move_sel(-1)
	elif event.is_action_pressed("move_down") and not event.is_echo():
		_slot_sel = (_slot_sel + 1) % 3
	elif event.is_action_pressed("move_up") and not event.is_echo():
		_slot_sel = (_slot_sel + 2) % 3
	elif event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if _sel >= 0 and _sel < _items.size() and not _items[_sel]["used"]:
			if _items[_sel]["kind"] == "card" and not _cards_enabled():
				_say(tr("Primeiro coloque os valores do enunciado."), false)
			else:
				_place(_sel, _slot_sel)


func _move_sel(d: int) -> void:
	var n := _items.size()
	for k in n:
		_sel = (_sel + d + n) % n
		if not _items[_sel]["used"]:
			return


func _drop(p: Vector2) -> void:
	var n := _drag
	_drag = -1
	var center: Vector2 = (_items[n]["pos"] as Vector2) + (_items[n]["size"] as Vector2) / 2.0
	for i in 3:
		if (_slots[i]["rect"] as Rect2).grow(20.0).has_point(center) or (_slots[i]["rect"] as Rect2).has_point(p):
			_place(n, i)
			return
	_items[n]["pos"] = _items[n]["home"]


func _place(n: int, slot: int) -> void:
	var it: Dictionary = _items[n]
	if it["kind"] == "chip":
		if slot == int(it["var"]) and not _slots[slot]["filled"]:
			it["used"] = true
			_slots[slot]["filled"] = true
			_slot_sel = _first_open_slot()
			_move_sel(1)
			_say(tr("Certo!"), true, 0.6)
		else:
			it["pos"] = it["home"]
			_wrong(tr("Essa variável não combina com esse valor!"))
	else:
		if slot != _hidden:
			it["pos"] = it["home"]
			return
		if int(it["value"]) == _vals[_hidden]:
			it["used"] = true
			_solved += 1
			_bonuses.append({"kind": _f["kind"], "amount": float(_f["amount"]) * (1.5 if hard else 1.0), "res": _f["res"]})
			_say(tr("Resposta correta! Bônus: %s") % tr(_f["res"]), true, 1.2)
			_next_in = 1.2
		else:
			it["pos"] = it["home"]
			_wrong(tr("Resposta errada! -%d s. Novos valores.") % int(ERROR_PENALTY))
			_time_left -= ERROR_PENALTY
			_new_problem(_f)   # a mesma formula, com valores novos
			if _time_left <= 0.0:
				_time_left = 0.0
				_finish()


func _wrong(text: String) -> void:
	_shake = 10.0
	_say(text, false, 1.4)


func _say(text: String, ok: bool, t: float = 1.2) -> void:
	_msg = text
	_msg_ok = ok
	_msg_t = t


func _advance() -> void:
	_next_in = -1.0
	_round += 1
	if _round >= ROUNDS:
		_finish()
		return
	_new_problem(_order[_round])


func _finish() -> void:
	if _over:
		return
	_over = true
	_msg_t = 0.0
	result = {"solved": _solved, "total": ROUNDS, "bonuses": _bonuses, "hard": hard}


func _result_lines() -> Array:
	var lines: Array = [tr("Terminal encerrado"), tr("Problemas resolvidos: %d de %d") % [_solved, ROUNDS]]
	if _bonuses.is_empty():
		lines.append(tr("Nenhum bônus desta vez."))
	for b in _bonuses:
		lines.append(tr("Bônus: ") + tr(KIND_TEXT[b["kind"]]) % int(round(float(b["amount"]))))
	lines.append(tr("(F: continuar)"))
	return lines
