extends Area2D
## Zona de interacao (tecla F). O jogador encosta na zona e aparece "[F] <nome>".
## "action" diz o que acontece (veja scripts/interactions.gd).
## A CollisionShape2D filha e a area onde o jogador pode ficar para interagir:
## cubra o objeto E um pedaco do chao na frente dele.
## A zona pisca devagar em azul; se for o objetivo da missao, pisca mais forte e ganha um "!".

@export var action: String = ""
@export var display_name: String = "Usar"
## id de um item (ItemIcons): mostra a imagem dele flutuando sobre o objeto (ex.: cafe animado)
@export var item_icon: String = ""

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const BLUE := Color(0.25, 0.55, 1.0)

var highlighted := false
var _shape: CollisionShape2D
var _marker: Label
var _t := 0.0


func _ready() -> void:
	# camada 2 = interativos (o sensor do jogador olha so para ela)
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
	_shape = get_node_or_null("CollisionShape2D")
	_t = randf() * 3.0  # cada zona pisca em uma fase diferente
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Chamado pela sala: marca esta zona como o objetivo atual da missao.
func set_highlight(v: bool) -> void:
	highlighted = v
	if v and _marker == null:
		_marker = Label.new()
		_marker.text = "!"
		_marker.add_theme_font_override("font", FONT)
		_marker.add_theme_font_size_override("font_size", 64)
		_marker.add_theme_color_override("font_color", Color("2a6bff"))
		_marker.add_theme_color_override("font_outline_color", Color("ffffff"))
		_marker.add_theme_constant_override("outline_size", 10)
		_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_marker.size = Vector2(60, 70)
		_marker.z_index = 60
		add_child(_marker)
	if _marker != null:
		_marker.visible = v


func _rect() -> Rect2:
	if _shape == null or not (_shape.shape is RectangleShape2D):
		return Rect2()
	var s: Vector2 = (_shape.shape as RectangleShape2D).size
	return Rect2(_shape.position - s / 2.0, s)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()
	if _marker != null and _marker.visible:
		var r := _rect()
		_marker.position = Vector2(r.position.x + r.size.x / 2.0 - 30.0, r.position.y - 78.0 + sin(_t * 3.0) * 8.0)


func _draw() -> void:
	var r := _rect()
	if r.size == Vector2.ZERO:
		return
	var wave := 0.5 + 0.5 * sin(_t * TAU / 3.4)   # ciclo lento (~3,4 s)
	var a := lerpf(0.10, 0.30, wave) if highlighted else lerpf(0.03, 0.13, wave)
	draw_rect(r, Color(BLUE, a))
	draw_rect(r, Color(BLUE, minf(a * 2.4, 0.7)), false, 2.0)
	if item_icon != "":
		var tex := ItemIcons.frame_at(item_icon, _t)
		if tex != null:
			var k := 76.0 / maxf(tex.get_width(), tex.get_height())
			var sz := Vector2(tex.get_width(), tex.get_height()) * k
			var pos := Vector2(r.position.x + r.size.x / 2.0 - sz.x / 2.0, r.position.y + 16.0 + sin(_t * 2.0) * 4.0)  # sobre o objeto
			draw_texture_rect(tex, Rect2(pos, sz), false)
