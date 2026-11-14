extends CharacterBody2D
## Astronauta controlado pelo jogador: anda para cima, baixo, esquerda e direita (WASD ou setas).
## Sem animacao por enquanto: so troca a imagem conforme a direcao.
## F / Enter / Espaco interage com o objeto mais proximo; I / Tab abre a mochila.

@export var speed: float = 300.0
## Imagens do personagem (cima / baixo / lado). Cada personagem tem a sua cena.
@export var tex_up: Texture2D = preload("res://assets/player/player_up.png")
@export var tex_down: Texture2D = preload("res://assets/player/player_down.png")
@export var tex_side: Texture2D = preload("res://assets/player/player_side.png")
## true: a imagem lateral original olha para a ESQUERDA (astronauta); false: olha para a DIREITA (cientista)
@export var side_faces_left: bool = true

@onready var sprite: Sprite2D = $Sprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var sensor: Area2D = $InteractSensor

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")

var locked := false  # em interacao (menu/dialogo)
var seated := false  # sentado na cadeira de comando
var _target: Area2D
var _prompt: Label


func _ready() -> void:
	_show_sprite(tex_down, false)
	_prompt = Label.new()
	_prompt.add_theme_font_override("font", FONT)
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_color", Color("1b2a5c"))
	_prompt.add_theme_color_override("font_outline_color", Color("eef3ff"))
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.size = Vector2(320, 30)
	_prompt.position = Vector2(-160, -150)
	_prompt.z_index = 100
	_prompt.visible = false
	add_child(_prompt)


func _physics_process(_delta: float) -> void:
	if locked or seated or UI.busy:
		velocity = Vector2.ZERO
		_prompt.visible = false
		return

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed
	move_and_slide()

	if dir != Vector2.ZERO:
		# Diagonal: o eixo horizontal vence o empate.
		if absf(dir.x) >= absf(dir.y):
			_show_sprite(tex_side, (dir.x > 0.0) if side_faces_left else (dir.x < 0.0)) # espelha para o lado oposto ao da imagem
		elif dir.y < 0.0:
			_show_sprite(tex_up, false)
		else:
			_show_sprite(tex_down, false)

	_update_target()


func _unhandled_input(event: InputEvent) -> void:
	if locked or UI.busy:
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		if seated:
			return
		if _target != null:
			get_viewport().set_input_as_handled()
			_interact_with(_target)
	elif event.is_action_pressed("inventory") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_run_locked(Interactions.open_inventory)


func _interact_with(t: Area2D) -> void:
	locked = true
	UI.lock()
	await Interactions.run(t.action, t, self)
	UI.unlock()
	locked = false


func _run_locked(fn: Callable) -> void:
	locked = true
	UI.lock()
	await fn.call()
	UI.unlock()
	locked = false


func _update_target() -> void:
	var best: Area2D = null
	var best_d := INF
	for a in sensor.get_overlapping_areas():
		if a.get("action") == null:
			continue  # so zonas de interacao (interactable.gd)
		var d := global_position.distance_squared_to(a.global_position)
		if d < best_d:
			best_d = d
			best = a
	_target = best
	_prompt.visible = _target != null
	if _target != null:
		_prompt.text = "[F] " + str(_target.display_name)


## Senta numa posicao (cadeira de comando): sem colisao e sem andar.
func sit(pos: Vector2) -> void:
	seated = true
	velocity = Vector2.ZERO
	body_shape.set_deferred("disabled", true)
	global_position = pos
	_show_sprite(tex_side, not side_faces_left)


func stand(pos: Vector2) -> void:
	seated = false
	global_position = pos
	body_shape.set_deferred("disabled", false)


func _show_sprite(tex: Texture2D, flip: bool) -> void:
	sprite.texture = tex
	sprite.flip_h = flip
	# Origem do personagem = pes (centro da base da imagem).
	sprite.offset = Vector2(0, -tex.get_height() / 2.0)
