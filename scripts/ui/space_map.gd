extends Control
## Mapa espacial. Modo "select": escolher o destino (Lua, Marte, Jupiter) e iniciar a viagem; a nave
## aparece no destino escolhido. Modo "view": acompanhar a viagem (a nave anda pela rota).
## Setas escolhem (ou mouse), F confirma, Esc volta. Emite closed(rota) ("" = voltou sem escolher).
## Um radar animado (assets/ui/radar_frames.tres) varre o canto da tela.

signal closed(route: String)

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const VIEW := Vector2(1536, 1024)
const ICONS := {
	"Lua": preload("res://assets/ui/mapa/lua.png"),
	"Marte": preload("res://assets/ui/mapa/marte.png"),
	"Júpiter": preload("res://assets/ui/mapa/jupiter.png"),
}
const SHIP := preload("res://assets/ui/mapa/nave.png")
const SCALES := {"Lua": 7.0, "Marte": 6.0, "Júpiter": 4.0}      # pixel art em escala inteira
const EARTH := Vector2(210, 520)
const POS := {"Lua": Vector2(560, 360), "Marte": Vector2(930, 600), "Júpiter": Vector2(1290, 380)}
const BEND := {"Lua": -110.0, "Marte": 130.0, "Júpiter": -190.0}   # curvatura da rota

var mode := "select"
var routes: Array = []
var _sel := 0
var _t := 0.0
var _radar: RadarView
var _stars: Array = []


func configure(map_mode: String, current_route: String = "") -> void:
	mode = map_mode
	routes = Voyage.ROUTES.keys()
	_sel = maxi(0, routes.find(current_route))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 130:
		_stars.append({"p": Vector2(rng.randf_range(60, VIEW.x - 60), rng.randf_range(160, VIEW.y - 80)), "s": rng.randf_range(2.0, 5.0), "ph": rng.randf() * TAU})
	_radar = RadarView.new()
	_radar.position = Vector2(VIEW.x - 170.0, 150.0)
	add_child(_radar)
	_radar.setup(6.0)


# ---------------------------------------------------------------- entrada
func _hit(i: int) -> Rect2:
	var r: String = routes[i]
	var tex: Texture2D = ICONS[r]
	var sz := Vector2(tex.get_size()) * float(SCALES[r]) + Vector2(40, 40)
	return Rect2(POS[r] - sz / 2.0, sz)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		closed.emit("")
		return
	if mode == "view":
		if event.is_action_pressed("interact") and not event.is_echo():
			get_viewport().set_input_as_handled()
			closed.emit("")
		return
	if event is InputEventMouseMotion:
		var p: Vector2 = (make_input_local(event) as InputEventMouseMotion).position
		for i in routes.size():
			if _hit(i).has_point(p):
				_sel = i
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var p2: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		for i in routes.size():
			if _hit(i).has_point(p2):
				_sel = i
				_confirm()
				return
	elif event.is_action_pressed("move_right") and not event.is_echo():
		_sel = (_sel + 1) % routes.size()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_left") and not event.is_echo():
		_sel = (_sel - 1 + routes.size()) % routes.size()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_confirm()


func _confirm() -> void:
	Audio.sfx("select", 1.35, 0.5)
	closed.emit(String(routes[_sel]))


func _process(delta: float) -> void:
	_t += delta
	var rs := RadarView.from_voyage()
	_radar.set_state(bool(rs["active"]), float(rs["dist"]), float(rs["angle"]))
	queue_redraw()


# ---------------------------------------------------------------- desenho
func _txt(pos: Vector2, text: String, size: int, color: Color, width: float = -1.0, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	draw_string(FONT, pos, text, align, width, size, color)


func _curve(route: String, t: float) -> Vector2:
	var a := EARTH + Vector2(70, 0)
	var b: Vector2 = POS[route] - Vector2(40, 0)
	var c := (a + b) / 2.0 + Vector2(0, float(BEND[route]))
	return a.lerp(c, t).lerp(c.lerp(b, t), t)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW), Color("05070f"))
	for s in _stars:
		var a := 0.4 + 0.6 * (0.5 + 0.5 * sin(_t * 1.5 + float(s["ph"])))
		draw_rect(Rect2(s["p"], Vector2(s["s"], s["s"])), Color(0.8, 0.88, 1.0, a))
	draw_rect(Rect2(Vector2(40, 30), VIEW - Vector2(80, 60)), Color("4a6bff"), false, 4.0)
	_txt(Vector2(80, 92), tr("MAPA ESPACIAL"), 30, Color("8fe0a0"))
	var sub := tr("Escolha o destino da viagem.") if mode == "select" else tr("Acompanhe a nave pela rota.")
	_txt(Vector2(80, 130), sub, 18, Color("c9d6ff"))
	# radar
	draw_rect(Rect2(VIEW.x - 240.0, 80.0, 140.0, 140.0), Color(0.04, 0.08, 0.2, 0.9))
	_txt(Vector2(VIEW.x - 240.0, 244.0), tr("RADAR"), 16, Color("8aa0d8"), 140.0, HORIZONTAL_ALIGNMENT_CENTER)
	# rotas
	for r: String in routes:
		var on: bool = routes[_sel] == r
		for k in range(0, 41):
			if k % 2 == 0:
				draw_circle(_curve(r, float(k) / 40.0), 3.5 if on else 2.5, Color("ffd86a") if on else Color("5a74c8"))
	# Terra
	draw_circle(EARTH, 74.0, Color("0b1f4a"))
	draw_circle(EARTH, 68.0, Color("2f78e0"))
	for blob in [[Vector2(-20, -24), 26.0], [Vector2(26, -6), 20.0], [Vector2(-6, 30), 18.0], [Vector2(-36, 12), 12.0]]:
		draw_circle(EARTH + (blob[0] as Vector2), float(blob[1]), Color("3fb04a"))
	draw_arc(EARTH, 68.0, 0.0, TAU, 40, Color("9ad0ff"), 3.0)
	_txt(EARTH + Vector2(-80, 112), tr("TERRA"), 20, Color("dfe9ff"), 160.0, HORIZONTAL_ALIGNMENT_CENTER)
	# destinos
	for i in routes.size():
		var r2: String = routes[i]
		var tex: Texture2D = ICONS[r2]
		var k := float(SCALES[r2])
		var sz := Vector2(tex.get_size()) * k
		draw_texture_rect(tex, Rect2(POS[r2] - sz / 2.0, sz), false)
		var sel := i == _sel
		if sel:
			draw_arc(POS[r2], maxf(sz.x, sz.y) / 2.0 + 18.0 + 3.0 * sin(_t * 5.0), 0.0, TAU, 40, Color("ffd86a"), 4.0)
		_txt(POS[r2] + Vector2(-100, sz.y / 2.0 + 44.0), tr(r2).to_upper(), 22, Color("ffd86a") if sel else Color("dfe9ff"), 200.0, HORIZONTAL_ALIGNMENT_CENTER)
	# nave
	var ship_pos := Vector2.ZERO
	if mode == "view" and Voyage.active and routes.has(Voyage.route):
		ship_pos = _curve(Voyage.route, clampf(Voyage.progress / 100.0, 0.0, 1.0))
	else:
		var rr: String = routes[_sel]
		ship_pos = POS[rr] + Vector2(-90.0, -80.0) + Vector2(0, sin(_t * 3.0) * 6.0)
	var ssz := Vector2(SHIP.get_size()) * 3.0
	draw_texture_rect(SHIP, Rect2(ship_pos - ssz / 2.0, ssz), false)
	_draw_info()


func _draw_info() -> void:
	var rname: String = routes[_sel]
	if mode == "view" and Voyage.active:
		rname = Voyage.route
	var info: Dictionary = Voyage.ROUTES[rname]
	var box := Rect2(80, 760, VIEW.x - 160.0, 200)
	draw_rect(box, Color("101a33"))
	draw_rect(box, Color("5a74c8"), false, 3.0)
	_txt(box.position + Vector2(30, 56), tr(rname).to_upper(), 30, Color("ffd86a"))
	_txt(box.position + Vector2(30, 100), tr("Tempo de viagem: %d s") % int(info["travel"]), 20, Color("ffffff"))
	_txt(box.position + Vector2(30, 134), tr("Limite da missão: %d s") % int(info["limit"]), 20, Color("ffffff"))
	_txt(box.position + Vector2(30, 168), tr("Perigos possíveis: comunicação, asteroide, reator"), 16, Color("c9d6ff"))
	if mode == "view":
		var f := clampf(Voyage.progress / 100.0, 0.0, 1.0)
		draw_rect(Rect2(box.position + Vector2(760, 80), Vector2(560, 30)), Color("1d2d5c"))
		draw_rect(Rect2(box.position + Vector2(760, 80), Vector2(560.0 * f, 30)), Color("3ac28a"))
		draw_rect(Rect2(box.position + Vector2(760, 80), Vector2(560, 30)), Color("30467f"), false, 2.0)
		_txt(box.position + Vector2(760, 70), tr("PROGRESSO %d%%") % int(Voyage.progress), 18, Color("c9d6ff"))
		_txt(box.position + Vector2(760, 160), tr("F ou Esc: fechar"), 16, Color("8aa0d8"))
	else:
		var btn := Rect2(box.position + Vector2(box.size.x - 560.0, 60), Vector2(520, 80))
		draw_rect(btn, Color("27407f"))
		draw_rect(btn, Color("ffd86a"), false, 4.0)
		_txt(btn.position + Vector2(0, 50), tr("F: escolher este destino"), 24, Color("ffffff"), btn.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		_txt(box.position + Vector2(box.size.x - 560.0, 170), tr("←/→ ou mouse: trocar de destino     Esc: voltar"), 14, Color("8aa0d8"))
