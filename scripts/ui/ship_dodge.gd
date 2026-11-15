extends Control
## Minigame da viagem: a nave pequena desvia de asteroides e meteoros (fundo de estrelas com parallax).
## W/S ou setas movem a nave (A/D tambem, um pouco). Esc sai (conta como nao concluido).
## Terminar sem nenhum dano (hits == 0) libera o minigame para jogar quando quiser (cabine).
## Emite closed quando acaba; leia finished (sobreviveu o tempo todo) e hits.

signal closed

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const SHIP := preload("res://assets/vehicles/nave_pequena.png")
const ROCK := preload("res://assets/minigame/asteroide.png")
const STARS := preload("res://assets/minigame/estrelas.png")

const VIEW := Vector2(1536, 1024)
const DURATION := 32.0
const MAX_HITS := 3
const SHIP_SCALE := 0.5
const SHIP_SPEED := 440.0
const LAYERS := [   # velocidade (px/s), escala, transparencia, deslocamento
	{"speed": 36.0, "scale": 3.9, "alpha": 1.0, "off": 0.0, "add": false},
	{"speed": 110.0, "scale": 3.9, "alpha": 0.55, "off": 700.0, "add": true},
	{"speed": 240.0, "scale": 5.2, "alpha": 0.4, "off": 300.0, "add": true},
]

var finished := false          # sobreviveu o tempo todo
var hits := 0
var free_play := false         # jogado pela cabine (sem texto de desbloqueio)

var _t := 0.0
var _over := false
var _over_t := 0.0
var _spawn_in := 1.0
var _layers: Array = []        # [{nodes: [Sprite2D, Sprite2D], speed, w}]
var _ship: Sprite2D
var _vy := 0.0
var _vx := 0.0
var _invuln := 0.0
var _rocks: Array = []         # [{node, vel, r, spin}]
var _exhaust: CPUParticles2D
var _hud: Label
var _msg: Label
var _exit_btn: Button
var _bar: ColorRect
var _bar_bg: ColorRect


func configure(play_free: bool = false) -> void:
	free_play = play_free
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color("000003")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	for L in LAYERS:
		var w: float = STARS.get_width() * float(L["scale"])
		var nodes: Array = []
		for k in 2:
			var s := Sprite2D.new()
			s.texture = STARS
			s.centered = false
			s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			s.scale = Vector2.ONE * float(L["scale"])
			s.modulate.a = float(L["alpha"])
			s.position = Vector2(float(k) * w - float(L["off"]), 0)
			if bool(L["add"]):
				var m := CanvasItemMaterial.new()
				m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				s.material = m
			add_child(s)
			nodes.append(s)
		_layers.append({"nodes": nodes, "speed": float(L["speed"]), "w": w})

	_ship = Sprite2D.new()
	_ship.texture = SHIP
	_ship.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ship.scale = Vector2.ONE * SHIP_SCALE
	_ship.position = Vector2(260, VIEW.y / 2.0)
	_ship.z_index = 5
	add_child(_ship)
	_exhaust = CPUParticles2D.new()
	_exhaust.position = Vector2(-112, 6)          # bocal do motor (a nave olha para a direita)
	_exhaust.amount = 40
	_exhaust.lifetime = 0.32
	_exhaust.local_coords = true                   # a chama acompanha a nave (nao vira um fio no ar)
	_exhaust.direction = Vector2(-1, 0)
	_exhaust.spread = 7.0
	_exhaust.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_exhaust.emission_sphere_radius = 9.0
	_exhaust.initial_velocity_min = 260.0
	_exhaust.initial_velocity_max = 380.0
	_exhaust.damping_min = 40.0
	_exhaust.damping_max = 90.0
	_exhaust.scale_amount_min = 24.0
	_exhaust.scale_amount_max = 34.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.15))
	_exhaust.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color("fff6c8"), Color("ffb02e"), Color("e0481c"), Color(0.55, 0.1, 0.1, 0.0)])
	ramp.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	_exhaust.color_ramp = ramp
	_exhaust.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_exhaust.z_index = -1
	_ship.add_child(_exhaust)

	_hud = _label("", 22, Color("eef3ff"))
	_hud.position = Vector2(24, 18)
	add_child(_hud)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(1, 1, 1, 0.18)
	_bar_bg.position = Vector2(24, 64)
	_bar_bg.size = Vector2(VIEW.x - 48.0, 10)
	add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = Color("2a6bff")
	_bar.position = _bar_bg.position
	_bar.size = Vector2(0, 10)
	add_child(_bar)
	var hint := _label(tr("W/S ou setas: desviar"), 16, Color("c9d6ff"))
	hint.position = Vector2(24, 980)
	add_child(hint)
	_exit_btn = Button.new()
	_exit_btn.text = tr("Sair do minigame (Esc)")
	_exit_btn.add_theme_font_override("font", FONT)
	_exit_btn.add_theme_font_size_override("font_size", 16)
	_exit_btn.position = Vector2(VIEW.x - 340.0, 14)
	_exit_btn.size = Vector2(316, 40)
	_exit_btn.focus_mode = Control.FOCUS_NONE
	_exit_btn.pressed.connect(func(): closed.emit())
	add_child(_exit_btn)
	_msg = _label("", 30, Color("ffffff"))
	_msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.position = Vector2(168, 420)
	_msg.size = Vector2(VIEW.x - 336.0, 220)
	_msg.add_theme_color_override("font_outline_color", Color("0b1030"))
	_msg.add_theme_constant_override("outline_size", 10)
	add_child(_msg)
	_refresh_hud()


func _process(delta: float) -> void:
	# fundo com parallax (continua rolando mesmo depois do fim)
	for L in _layers:
		for s: Sprite2D in L["nodes"]:
			s.position.x -= float(L["speed"]) * delta * (1.0 + _t * 0.012)
			if s.position.x <= -float(L["w"]):
				s.position.x += float(L["w"]) * 2.0
	if _over:
		_over_t += delta
		_ship.position.x += 260.0 * delta if finished else 0.0
		return
	_t += delta
	_invuln = maxf(0.0, _invuln - delta)
	_move_ship(delta)
	_spawn(delta)
	_move_rocks(delta)
	_bar.size.x = (VIEW.x - 48.0) * clampf(_t / DURATION, 0.0, 1.0)
	if _t >= DURATION:
		_end(true)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		closed.emit()
	elif _over and _over_t > 0.6 and ((event.is_action_pressed("interact") and not event.is_echo()) or (event is InputEventMouseButton and event.pressed)):
		get_viewport().set_input_as_handled()
		closed.emit()


func _move_ship(delta: float) -> void:
	var ay := Input.get_axis("move_up", "move_down")
	var ax := Input.get_axis("move_left", "move_right")
	_vy = lerpf(_vy, ay * SHIP_SPEED, clampf(delta * 9.0, 0.0, 1.0))
	_vx = lerpf(_vx, ax * SHIP_SPEED * 0.6, clampf(delta * 9.0, 0.0, 1.0))
	_ship.position += Vector2(_vx, _vy) * delta
	_ship.position.x = clampf(_ship.position.x, 120.0, 620.0)
	_ship.position.y = clampf(_ship.position.y, 120.0, VIEW.y - 90.0)
	# inclina para cima/baixo conforme a velocidade
	_ship.rotation = lerpf(_ship.rotation, clampf(_vy / SHIP_SPEED, -1.0, 1.0) * 0.38, clampf(delta * 10.0, 0.0, 1.0))
	if _invuln > 0.0:
		_ship.modulate.a = 0.45 + 0.55 * absf(sin(_t * 30.0))
	else:
		_ship.modulate.a = 1.0


func _spawn(delta: float) -> void:
	_spawn_in -= delta
	if _spawn_in > 0.0:
		return
	var k := _t / DURATION
	_spawn_in = lerpf(1.0, 0.42, k) * randf_range(0.7, 1.2)
	var node := Sprite2D.new()
	node.texture = ROCK
	node.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	node.z_index = 3
	var small := randf() < 0.45
	var sc := randf_range(0.22, 0.4) if small else randf_range(0.7, 1.45)
	node.scale = Vector2.ONE * sc
	node.position = Vector2(VIEW.x + 140.0, randf_range(110.0, VIEW.y - 90.0))
	if small:
		node.modulate = Color(1.0, 0.8, 0.7)
	add_child(node)
	var spd := (randf_range(520.0, 760.0) if small else randf_range(260.0, 420.0)) * (1.0 + k * 0.4)
	var vy := randf_range(-150.0, 150.0) if small else randf_range(-50.0, 50.0)
	if small and randf() < 0.5:   # meteoros diagonais que "cortam" a tela
		vy = (1 if node.position.y < VIEW.y / 2.0 else -1) * randf_range(120.0, 260.0)
	_rocks.append({"node": node, "vel": Vector2(-spd, vy), "r": 56.0 * sc, "spin": randf_range(-2.0, 2.0)})


func _move_rocks(delta: float) -> void:
	var keep: Array = []
	for R in _rocks:
		var n: Sprite2D = R["node"]
		n.position += (R["vel"] as Vector2) * delta
		n.rotation += float(R["spin"]) * delta
		if n.position.x < -220.0 or n.position.y < -220.0 or n.position.y > VIEW.y + 220.0:
			n.queue_free()
			continue
		keep.append(R)
		if _invuln <= 0.0 and _hits_ship(n.position, float(R["r"])):
			_hit(n.position)
	_rocks = keep


func _hits_ship(p: Vector2, r: float) -> bool:
	var c := cos(_ship.rotation)
	var s := sin(_ship.rotation)
	for off in [Vector2(-38, 0), Vector2(6, 0), Vector2(44, 2)]:
		var q: Vector2 = _ship.position + Vector2(off.x * c - off.y * s, off.x * s + off.y * c)
		if q.distance_to(p) < r + 20.0:
			return true
	return false


func _hit(at: Vector2) -> void:
	hits += 1
	_invuln = 1.4
	_burst(at)
	var tw := create_tween()
	tw.tween_property(_ship, "modulate", Color(1.0, 0.3, 0.3), 0.05)
	tw.tween_property(_ship, "modulate", Color.WHITE, 0.25)
	var base := position
	var sh := create_tween()
	for i in 5:
		sh.tween_property(self, "position", base + Vector2(randf_range(-10, 10), randf_range(-10, 10)), 0.04)
	sh.tween_property(self, "position", base, 0.04)
	_refresh_hud()
	if hits >= MAX_HITS:
		_end(false)


func _burst(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.emitting = false
	p.one_shot = true
	p.amount = 24
	p.lifetime = 0.6
	p.explosiveness = 1.0
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 320.0
	p.scale_amount_min = 3.0
	p.scale_amount_max = 7.0
	p.color = Color("ffb04a")
	p.z_index = 8
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


func _end(ok: bool) -> void:
	_over = true
	_exit_btn.visible = false
	finished = ok
	_exhaust.amount = 80 if ok else 10
	if ok and hits == 0:
		_msg.text = tr("Percurso concluído sem nenhum dano!") + ("" if free_play else "\n" + tr("Minigame liberado na cabine."))
	elif ok:
		_msg.text = tr("Percurso concluído com %d impacto(s).") % hits
	else:
		_msg.text = tr("A nave foi muito danificada, mas segue viagem.")
	_msg.text += "\n\n" + tr("(F ou clique: continuar)")


func _refresh_hud() -> void:
	_hud.text = tr("Casco: %s") % "".join(PackedStringArray(_hearts()))


func _hearts() -> Array:
	var out: Array = []
	for i in MAX_HITS:
		out.append("#" if i >= hits else "-")
	return out


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
