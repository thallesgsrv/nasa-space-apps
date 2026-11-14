extends CharacterBody2D
## Astronauta controlado pelo jogador: anda para cima, baixo, esquerda e direita.
## Teclas: WASD ou setas.
## Animacoes (assets/player/player_frames.tres): idle/run/hit em down, up e side;
## roll e death existem so em side (a direita e o lado "natural" do sprite, a esquerda usa flip_h).

@export var speed: float = 300.0
@export var roll_speed: float = 520.0

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")

## Bloqueio externo (tutorial, cenas): o personagem fica parado e nao interage.
var locked := false
## Sentado na cadeira de comando (console de missao aberto).
var seated := false

## Personagem de imagem estatica (cientista): uma textura por direcao, sem AnimatedSprite2D.
@export var tex_up: Texture2D
@export var tex_down: Texture2D
@export var tex_side: Texture2D
@export var side_faces_left := false  # a arte "side" ja olha para a esquerda?

@onready var sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
@onready var still: Sprite2D = get_node_or_null("Sprite2D") as Sprite2D
@onready var sensor: Area2D = get_node_or_null("InteractSensor") as Area2D

var _prompt: Label
var _target: Area2D
var _interacting := false

var _facing := "down"        # "down" | "up" | "side"
var _flip := false           # true = olhando para a esquerda (so vale em "side")
var _last_dir := Vector2.DOWN
var _locked := false         # hit/roll tocando: sem controle
var _dead := false
var _roll_dir := Vector2.ZERO


func _ready() -> void:
	_setup_input()
	if sprite != null:
		sprite.animation_finished.connect(_on_animation_finished)
	_play("idle")
	_prompt = Label.new()
	_prompt.add_theme_font_override("font", FONT)
	_prompt.add_theme_font_size_override("font_size", 24)
	_prompt.add_theme_color_override("font_color", Color.WHITE)
	_prompt.add_theme_color_override("font_outline_color", Color.BLACK)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.position = Vector2(-160, -130)
	_prompt.size = Vector2(320, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	add_child(_prompt)


func _physics_process(_delta: float) -> void:
	if _dead:
		return
	if _is_frozen():
		velocity = Vector2.ZERO
		_play("idle")
		_update_prompt()
		return
	_update_prompt()
	if _locked:
		velocity = _roll_dir * roll_speed
		move_and_slide()
		return

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed
	move_and_slide()

	if dir == Vector2.ZERO:
		_play("idle")
		return

	_last_dir = dir
	# Diagonal: o eixo horizontal vence o empate.
	if absf(dir.x) >= absf(dir.y):
		_facing = "side"
		_flip = dir.x < 0.0
	elif dir.y < 0.0:
		_facing = "up"
	else:
		_facing = "down"
	_play("run")


## Toca a animacao de dano (o jogador perde o controle ate ela terminar).
func hit() -> void:
	if sprite == null or _dead or _locked:
		return
	_locked = true
	_roll_dir = Vector2.ZERO
	_play("hit", true)


## Rolamento na ultima direcao andada.
func roll() -> void:
	if sprite == null or _dead or _locked:
		return
	_locked = true
	_roll_dir = _last_dir.normalized()
	if absf(_roll_dir.x) > 0.1:
		_flip = _roll_dir.x < 0.0
	sprite.flip_h = _flip
	sprite.play("roll_side")


## Animacao de morte; o personagem fica deitado no ultimo frame.
func die() -> void:
	if _dead:
		return
	_dead = true
	_locked = true
	velocity = Vector2.ZERO
	if sprite != null:
		sprite.flip_h = _flip
		sprite.play("death_side")


func _play(base: String, restart: bool = false) -> void:
	if sprite == null:
		_show_still()
		return
	var anim := "%s_%s" % [base, _facing]
	sprite.flip_h = _flip and _facing == "side"
	if restart or sprite.animation != anim:
		sprite.play(anim)


func _show_still() -> void:
	if still == null:
		return
	match _facing:
		"up":
			still.texture = tex_up
			still.flip_h = false
		"down":
			still.texture = tex_down
			still.flip_h = false
		_:
			still.texture = tex_side
			still.flip_h = _flip != side_faces_left


func _on_animation_finished() -> void:
	var anim := String(sprite.animation)
	if anim.begins_with("hit") or anim.begins_with("roll"):
		_locked = false
		_roll_dir = Vector2.ZERO
		_play("idle", true)


## Cria as acoes de movimento no codigo (setas + WASD), sem mexer no project.godot.
func _setup_input() -> void:
	var binds := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action) # evita duplicar se o jogador for recriado
		for key in binds[action]:
			# Uma ligacao pela posicao fisica da tecla e outra pela tecla logica (layout do teclado).
			var physical := InputEventKey.new()
			physical.physical_keycode = key
			InputMap.action_add_event(action, physical)
			var logical := InputEventKey.new()
			logical.keycode = key
			InputMap.action_add_event(action, logical)


# ============================ interacao ============================
func _is_frozen() -> bool:
	return locked or seated or _interacting or UI.busy


## Escolhe a zona interativa mais proxima e mostra "[F] nome".
func _update_prompt() -> void:
	_target = null
	if sensor != null and not _is_frozen():
		var best := INF
		for area in sensor.get_overlapping_areas():
			if area is Area2D and area.get("action") != null and String(area.get("action")) != "":
				var d := global_position.distance_squared_to(area.global_position)
				if d < best:
					best = d
					_target = area
	if _target != null:
		_prompt.text = "[F] " + String(_target.get("display_name"))
	_prompt.visible = _target != null


func _unhandled_input(event: InputEvent) -> void:
	if _dead or event.is_echo() or _is_frozen():
		return
	if event.is_action_pressed("interact") and _target != null:
		get_viewport().set_input_as_handled()
		_interacting = true
		_prompt.visible = false
		await Interactions.run(String(_target.get("action")), _target, self)
		_interacting = false
	elif event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		_interacting = true
		await Interactions.open_inventory()
		_interacting = false


## Senta na cadeira (chamado pela sala de controle).
func sit(pos: Vector2) -> void:
	seated = true
	velocity = Vector2.ZERO
	global_position = pos
	_facing = "down"
	_play("idle", true)


func stand(pos: Vector2) -> void:
	global_position = pos
	seated = false
