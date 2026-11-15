extends Area2D
## Zona de interacao (tecla F). O jogador encosta na zona e aparece "[F] <nome>".
## "action" diz o que acontece (veja scripts/interactions.gd).
## A CollisionShape2D filha e a area onde o jogador pode ficar para interagir:
## cubra o objeto E um pedaco do chao na frente dele.
## Ao chegar perto aparece um brilho animado (assets/ui/brilho_frames.tres); se for o objetivo da missao, ele fica sempre visivel e ganha um "!".

@export var action: String = ""
@export var display_name: String = "Usar"
## id de um item (ItemIcons): mostra a imagem dele flutuando sobre o objeto (ex.: cafe animado)
@export var item_icon: String = ""

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const BLUE := Color(0.25, 0.55, 1.0)

var highlighted := false
var _shape: CollisionShape2D
var _marker: Sprite2D
var _spark: AnimatedSprite2D     # brilho animado (gif do grupo) que aparece quando o jogador chega perto
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
	_spark = AnimatedSprite2D.new()
	_spark.sprite_frames = preload("res://assets/ui/brilho_frames.tres")
	_spark.scale = Vector2(1.6, 1.6)
	_spark.z_index = 55
	_spark.visible = false
	add_child(_spark)
	_spark.play("default")


## Chamado pela sala: marca esta zona como o objetivo atual da missao.
func set_highlight(v: bool) -> void:
	highlighted = v
	if v and _marker == null:
		_marker = Sprite2D.new()
		_marker.texture = preload("res://assets/ui/alerta.png")
		_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	if _spark != null:
		var r0 := _rect()
		var player := get_tree().get_first_node_in_group("player") as Node2D
		var near := false
		if player != null and r0.size != Vector2.ZERO:
			var c := global_position + r0.position + r0.size / 2.0
			near = absf(player.global_position.x - c.x) < r0.size.x / 2.0 + 150.0 and absf(player.global_position.y - c.y) < r0.size.y / 2.0 + 150.0
		_spark.visible = near or highlighted
		_spark.position = r0.position + r0.size / 2.0 + Vector2(0, sin(_t * 3.0) * 4.0)
	if _marker != null and _marker.visible:
		var r := _rect()
		_marker.position = Vector2(r.position.x + r.size.x / 2.0, r.position.y - 44.0 + sin(_t * 3.0) * 8.0)


func _draw() -> void:
	var r := _rect()
	if r.size == Vector2.ZERO:
		return
	if item_icon != "":
		var tex := ItemIcons.frame_at(item_icon, _t)
		if tex != null:
			var k := 76.0 / maxf(tex.get_width(), tex.get_height())
			var sz := Vector2(tex.get_width(), tex.get_height()) * k
			var pos := Vector2(r.position.x + r.size.x / 2.0 - sz.x / 2.0, r.position.y + 16.0 + sin(_t * 2.0) * 4.0)  # sobre o objeto
			draw_texture_rect(tex, Rect2(pos, sz), false)
