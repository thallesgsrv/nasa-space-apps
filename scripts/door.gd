extends Area2D
## Zona de passagem entre salas. Quando o jogador encosta, avisa o jogo para trocar de sala.
## Posicione/redimensione a CollisionShape2D no editor para ajustar onde a porta dispara.
## Perto da porta aparece o nome do lugar para onde ela leva; se a porta leva ao objetivo
## da missao (ou ao caminho para ele), aparece um "!" azul em cima.

signal used(target_room: String, target_spawn: String)

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const SHOW_DISTANCE := 280.0

## Cena da sala de destino (ex.: res://scenes/rooms/dormitorio.tscn)
@export_file("*.tscn") var target_room: String = ""
## Nome do Marker2D (dentro de "Spawns" da sala de destino) onde o jogador aparece
@export var target_spawn: String = ""
## Nome do lugar para onde a porta leva (mostrado antes de entrar)
@export var place_name: String = ""

var guided := false
var _label: Label
var _marker: Sprite2D
var _t := 0.0
var _below := false


func _ready() -> void:
	monitorable = false
	body_entered.connect(_on_body_entered)
	_t = randf() * 3.0
	_label = _make_label(tr(place_name), 24, Color("ffffff"), Color("1b2a5c"), 8)
	_label.size = Vector2(340, 32)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.modulate.a = 0.0
	_label.z_index = 60
	add_child(_label)
	# portas no alto da tela: nome e "!" ficam ABAIXO da porta (acima ficariam atras da barra de avisos)
	_below = global_position.y < 260.0
	var label_y := global_position.y + (34.0 if _below else -54.0)
	_label.global_position = Vector2(clampf(global_position.x - 170.0, 8.0, 1536.0 - 348.0), label_y)
	_marker = Sprite2D.new()
	_marker.texture = preload("res://assets/ui/alerta.png")
	_marker.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_marker.z_index = 60
	_marker.visible = false
	add_child(_marker)


func set_guided(v: bool) -> void:
	guided = v
	if _marker != null:
		_marker.visible = v


func _process(delta: float) -> void:
	_t += delta
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var near := player != null and player.global_position.distance_to(global_position) < SHOW_DISTANCE
	_label.modulate.a = move_toward(_label.modulate.a, 1.0 if near else 0.0, delta * 3.0)
	if _marker.visible:
		var base_y := _label.global_position.y + (40.0 if _below else -74.0)
		_marker.global_position = Vector2(_label.global_position.x + 170.0, base_y + 34.0 + sin(_t * 3.0) * 8.0)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		used.emit(target_room, target_spawn)


func _make_label(text: String, size: int, color: Color, outline: Color, outline_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", outline_size)
	return l
