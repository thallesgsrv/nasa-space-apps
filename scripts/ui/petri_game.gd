extends Control
## Minigame da placa de Petri (mesa de analise do laboratorio, lado da Terra).
## 1) arraste o fungo (mouse) ate a placa;  2) corte ao meio;  3) a metade branca mostra a COR;
## 4) clique na metade colorida para ver o NOME da cor (para quem nao distingue cores).
## Esc sai. Teclado: F avanca cada etapa (para quem nao usa o mouse).
## O fungo "amassa e volta" (boing) ao clicar/segurar/soltar, com particulas.
## Ao cortar, a cor da amostra e definida (Missions.analyze_sample).

signal closed

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const INK := Color("1b2a5c")
const TABLE := preload("res://assets/minigame/petri_mesa.png")
const FUNGO := preload("res://assets/minigame/fungo.png")
const FUNGO_CUT := preload("res://assets/minigame/fungo_cortado.png")

const VIEW := Vector2(1536, 1024)
const TABLE_POS := Vector2(0, 83)                 # a imagem da mesa (1536x858) fica centralizada
const DISH_CENTER := Vector2(768, 83 + 420)       # centro da placa de Petri na tela
const DISH_RADIUS := 200.0
const START_POS := Vector2(260, 770)
const BASE_SCALE := Vector2(0.9, 0.9)
const COLORS := {
	"Azul": Color("2f6fe0"), "Verde": Color("3fb04a"),
	"Marrom": Color("7a4a22"), "Amarelo": Color("f2d02a"),
}

var stage := 0              # 0 arrastar, 1 na placa, 2 cortado
var _fungus: Sprite2D
var _dragging := false
var _drag_offset := Vector2.ZERO
var _t := 0.0
var _hint: Label
var _cut_btn: Button
var _color_label: Label
var _swatch: ColorRect
var _tinted: ImageTexture
var _scale_tween: Tween
var _name_shown := false


func configure() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color("14161c")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var table := TextureRect.new()
	table.texture = TABLE
	table.position = TABLE_POS
	table.size = TABLE.get_size()
	table.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(table)

	_fungus = Sprite2D.new()
	_fungus.texture = FUNGO
	_fungus.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_fungus.position = START_POS
	_fungus.scale = BASE_SCALE
	add_child(_fungus)

	_hint = _label("", 24, Color("eef3ff"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.position = Vector2(0, 975)
	_hint.size = Vector2(VIEW.x, 36)
	add_child(_hint)

	var esc := _label(tr("Esc: sair"), 16, Color("eef3ff"))
	esc.position = Vector2(20, 20)
	add_child(esc)

	_cut_btn = Button.new()
	_cut_btn.text = tr("Cortar ao meio")
	_cut_btn.add_theme_font_override("font", FONT)
	_cut_btn.add_theme_font_size_override("font_size", 24)
	_cut_btn.add_theme_color_override("font_color", INK)
	_cut_btn.add_theme_color_override("font_hover_color", INK)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("e6eeff") if st != "hover" else Color("ffffff")
		sb.border_color = INK
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(8)
		_cut_btn.add_theme_stylebox_override(st, sb)
	_cut_btn.position = Vector2(768 - 170, 900)
	_cut_btn.size = Vector2(340, 60)
	_cut_btn.visible = false
	_cut_btn.pressed.connect(_cut)
	add_child(_cut_btn)

	_color_label = _label("", 56, Color.WHITE)
	_color_label.add_theme_color_override("font_outline_color", INK)
	_color_label.add_theme_constant_override("outline_size", 14)
	_color_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_color_label.position = Vector2(0, 120)
	_color_label.size = Vector2(VIEW.x, 70)
	_color_label.pivot_offset = Vector2(VIEW.x / 2.0, 35)
	_color_label.visible = false
	add_child(_color_label)
	_swatch = ColorRect.new()          # quadrado com a cor, ao lado do nome
	_swatch.size = Vector2(70, 70)
	_swatch.position = Vector2(768 - 360, 120)
	_swatch.visible = false
	add_child(_swatch)
	_update_hint()


func _process(delta: float) -> void:
	_t += delta
	if _dragging:   # tremidinha enquanto segura
		var w := sin(_t * 22.0) * 0.05
		_fungus.scale = BASE_SCALE * Vector2(1.18 + w, 0.82 - w)


# ---------------------------------------------------------------- entrada
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		closed.emit()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var p: Vector2 = (make_input_local(event) as InputEventMouseButton).position
		if event.pressed:
			_on_press(p)
		else:
			_on_release()
	elif event is InputEventMouseMotion and _dragging:
		var m: Vector2 = (make_input_local(event) as InputEventMouseMotion).position
		_fungus.position = (m + _drag_offset).clamp(Vector2(60, 140), Vector2(VIEW.x - 60.0, 930))
	elif event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_next_step_by_key()


func _on_press(p: Vector2) -> void:
	if stage == 0 and _fungus_rect().has_point(p):
		_dragging = true
		_drag_offset = _fungus.position - p
		_squash()
		_burst(_fungus.position, Color("f2d02a"), Color("3fb04a"), 12)
	elif stage == 1 and _fungus_rect().has_point(p):
		_squash()   # cutucar o fungo: boing
		_boing()
		_burst(_fungus.position, Color("f2d02a"), Color("3fb04a"), 10)
	elif stage == 2 and _colored_half_rect().has_point(p):
		_reveal_name()


func _on_release() -> void:
	if not _dragging:
		return
	_dragging = false
	if _fungus.position.distance_to(DISH_CENTER) <= DISH_RADIUS:
		_place_in_dish()
	else:
		var tw := create_tween()
		tw.tween_property(_fungus, "position", START_POS, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_boing()


func _next_step_by_key() -> void:
	if stage == 0:
		_dragging = false
		_place_in_dish()
	elif stage == 1:
		_cut()
	elif stage == 2:
		_reveal_name()


# ---------------------------------------------------------------- etapas
func _place_in_dish() -> void:
	stage = 1
	var tw := create_tween()
	tw.tween_property(_fungus, "position", DISH_CENTER, 0.2).set_trans(Tween.TRANS_SINE)
	_boing()
	_burst(DISH_CENTER, Color("f2d02a"), Color("3fb04a"), 18)
	_cut_btn.visible = true
	_update_hint()


func _cut() -> void:
	if stage != 1:
		return
	stage = 2
	_cut_btn.visible = false
	if not Missions.analyzed:
		Missions.analyze_sample()   # a cor da amostra e definida ao cortar
	var c: Color = COLORS.get(Missions.sample_color, Color.WHITE)
	_tinted = _tint(c)
	_fungus.texture = _tinted
	_fungus.position = DISH_CENTER
	_fungus.scale = BASE_SCALE * 0.55
	_boing()
	_burst(DISH_CENTER, Color.WHITE, c, 24)
	_burst(DISH_CENTER + Vector2(40, -10), c, Color.WHITE, 14)
	_update_hint()


func _reveal_name() -> void:
	_name_shown = true
	var c: Color = COLORS.get(Missions.sample_color, Color.WHITE)
	_color_label.text = tr("Cor: %s") % tr(Missions.sample_color).to_upper()
	_color_label.add_theme_color_override("font_color", Color.WHITE)
	_swatch.color = c
	_swatch.visible = true
	_color_label.visible = true
	_color_label.scale = Vector2(0.4, 0.4)
	var tw := create_tween()
	tw.tween_property(_color_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_squash()
	_boing()
	_burst(_colored_half_rect().get_center(), c, Color.WHITE, 16)
	_update_hint()


# ---------------------------------------------------------------- animacoes
func _squash() -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(_fungus, "scale", BASE_SCALE * Vector2(1.3, 0.7), 0.08).set_trans(Tween.TRANS_SINE)


# volta ao normal com "mola" (boing)
func _boing() -> void:
	if _scale_tween:
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.tween_property(_fungus, "scale", BASE_SCALE, 0.7).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _burst(pos: Vector2, c1: Color, c2: Color, amount: int = 16) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 260.0
	p.gravity = Vector2(0, 520)
	p.scale_amount_min = 5.0
	p.scale_amount_max = 10.0
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([c1, Color(c2, 0.0)])
	p.color_ramp = g
	p.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	p.z_index = 5
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.4).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- util
func _fungus_rect() -> Rect2:
	var s: Vector2 = _fungus.texture.get_size() * BASE_SCALE
	return Rect2(_fungus.position - s / 2.0, s)


# a metade colorida (lado direito do fungo cortado)
func _colored_half_rect() -> Rect2:
	var r := _fungus_rect()
	return Rect2(r.position + Vector2(r.size.x * 0.5, 0), Vector2(r.size.x * 0.5, r.size.y))


# troca o branco da imagem pela cor da amostra
func _tint(c: Color) -> ImageTexture:
	var img: Image = FUNGO_CUT.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	for y in img.get_height():
		for x in img.get_width():
			var px := img.get_pixel(x, y)
			if px.a > 0.5 and minf(px.r, minf(px.g, px.b)) > 0.78:
				var v := (px.r + px.g + px.b) / 3.0
				img.set_pixel(x, y, Color(c.r * v, c.g * v, c.b * v, 1.0))
	return ImageTexture.create_from_image(img)


func _update_hint() -> void:
	match stage:
		0:
			_hint.text = tr("Arraste o fungo para a placa de Petri com o mouse (ou aperte F).")
		1:
			_hint.text = tr("Agora corte o fungo ao meio (botão ou F).")
		_:
			if _name_shown:
				_hint.text = tr("Esc: sair")
			else:
				_hint.text = tr("Clique na parte colorida para ver o nome da cor (ou F).")


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
