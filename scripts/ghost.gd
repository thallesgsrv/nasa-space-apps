extends Node2D
## Fantasma de outro jogador (multiplayer): boneco animado + nome, so aparece na mesma sala que voce.
## A posicao vem de Net.roster (replicada ~12x/s); aqui suavizamos o movimento e escolhemos a animacao
## (parado / correndo, de frente / costas / lado) a partir do deslocamento, igual ao player.gd.

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const BASE_FRAMES := preload("res://assets/player/player_frames.tres")
const SCIENTIST_FRAMES := preload("res://assets/scientist/scientist_frames.tres")
const TEX_ASTRONAUT := preload("res://assets/player/player_down.png")
const SCIENTIST_TEX := {
	"up": preload("res://assets/scientist/scientist_up.png"),
	"down": preload("res://assets/scientist/scientist_down.png"),
	"side": preload("res://assets/scientist/scientist_side.png"),
}
## Astronautas de cores diferentes: azul (comandante, original), laranja (engenheiro) e verde (astronauta 2).
const SUIT := {
	Net.Role.ENGINEER: "laranja",
	Net.Role.ASTRONAUT2: "verde",
}
const MOVE_THRESHOLD := 6.0     # px de distancia ate o alvo para contar como "correndo"
const FOLLOW := 14.0            # suavizacao da posicao
## Hitbox dos pes: IGUAL a do player.tscn (44x22, subida de 11 px), para os bonecos se barrarem de
## verdade. So fica solida quando o jogador local NAO esta em cima dela (ninguem fica preso no spawn).
const FEET := Vector2(44, 22)
const FEET_Y := -11.0

var peer_id := 0
var role := 0
var _anim: AnimatedSprite2D     # astronautas
var _label: Label
var _target := Vector2.ZERO
var _placed := false
var _facing := "down"
var _left := false              # olhando para a esquerda (so vale em "side")
var _moving := false
var _body: StaticBody2D         # hitbox (camada 1, como as paredes das salas)
var _shape: CollisionShape2D
var _solid := false


func setup(id: int, player_role: int, display_name: String) -> void:
	peer_id = id
	role = player_role
	z_index = 50
	_anim = AnimatedSprite2D.new()
	_anim.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if role == Net.Role.SCIENTIST:
		_anim.sprite_frames = SCIENTIST_FRAMES
		_anim.scale = Vector2(1.45, 1.45)         # mesmos valores do cientista em scientist.tscn
		_anim.offset = Vector2(0, -42)
	else:
		_anim.sprite_frames = frames_for(role) if SUIT.has(role) else BASE_FRAMES
		_anim.scale = Vector2(3.5, 3.5)           # mesmos valores do astronauta em player.tscn
		_anim.offset = Vector2(1.5, -18)
	add_child(_anim)
	_body = StaticBody2D.new()
	_body.name = "Hitbox"
	_shape = CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = FEET
	_shape.shape = rect
	_shape.position = Vector2(0, FEET_Y)
	_shape.disabled = true
	_body.add_child(_shape)
	add_child(_body)
	_label = Label.new()
	_label.text = display_name
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color("dfe9ff"))
	_label.add_theme_color_override("font_outline_color", Color("1b2a5c"))
	_label.add_theme_constant_override("outline_size", 6)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.size = Vector2(240, 24)
	_label.position = Vector2(-120, -150)
	add_child(_label)
	_refresh_visual()


func set_target(pos: Vector2) -> void:
	_target = pos
	if not _placed:
		global_position = pos
		_placed = true


func is_moving() -> bool:
	return _moving


func current_animation() -> String:
	return String(_anim.animation) if _anim != null else ""


func _process(delta: float) -> void:
	if not _placed:
		return
	var to_target := _target - global_position
	_moving = to_target.length() > MOVE_THRESHOLD
	if _moving:
		# diagonal: o eixo horizontal vence o empate (como no player.gd)
		if absf(to_target.x) >= absf(to_target.y):
			_facing = "side"
			_left = to_target.x < 0.0
		else:
			_facing = "up" if to_target.y < 0.0 else "down"
	global_position = global_position.lerp(_target, clampf(delta * FOLLOW, 0.0, 1.0))
	_update_solid()
	_refresh_visual()


func is_solid() -> bool:
	return _solid


# Solido quando o jogador local esta fora da hitbox; transparente enquanto os dois se sobrepoem.
func _update_solid() -> void:
	var overlap := false
	var lim := Vector2(40.0, 18.0) if _solid else Vector2(FEET.x + 6.0, FEET.y + 6.0)
	for n in get_tree().get_nodes_in_group("player"):
		var me := n as Node2D
		if me == null or not me.is_inside_tree():
			continue
		var d := me.global_position - global_position
		if absf(d.x) < lim.x and absf(d.y) < lim.y:
			overlap = true
	var want := not overlap
	if want != _solid:
		_solid = want
		_shape.set_deferred("disabled", not want)


func _refresh_visual() -> void:
	if _anim != null:
		var anim := "%s_%s" % ["run" if _moving else "idle", _facing]
		_anim.flip_h = _left and _facing == "side"
		if _anim.animation != anim or not _anim.is_playing():
			_anim.play(anim)



## Imagem parada (de frente) do astronauta na cor do papel.
static func texture_for(r: int) -> Texture2D:
	if r == Net.Role.SCIENTIST:
		return SCIENTIST_TEX["down"]
	if SUIT.has(r):
		return load("res://assets/player/variants/player_down_%s.png" % SUIT[r]) as Texture2D
	return TEX_ASTRONAUT


## Animacoes do astronauta na cor do papel (null = cor original).
static func frames_for(r: int) -> SpriteFrames:
	if SUIT.has(r):
		return load("res://assets/player/variants/player_frames_%s.tres" % SUIT[r]) as SpriteFrames
	return null
