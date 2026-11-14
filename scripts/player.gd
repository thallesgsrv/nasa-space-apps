extends CharacterBody2D
## Astronauta controlado pelo jogador: anda para cima, baixo, esquerda e direita.
## Teclas: WASD ou setas.
## Animacoes (assets/player/player_frames.tres): idle/run/hit em down, up e side;
## roll e death existem so em side (a direita e o lado "natural" do sprite, a esquerda usa flip_h).

@export var speed: float = 300.0
@export var roll_speed: float = 520.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

var _facing := "down"        # "down" | "up" | "side"
var _flip := false           # true = olhando para a esquerda (so vale em "side")
var _last_dir := Vector2.DOWN
var _locked := false         # hit/roll tocando: sem controle
var _dead := false
var _roll_dir := Vector2.ZERO


func _ready() -> void:
	_setup_input()
	sprite.animation_finished.connect(_on_animation_finished)
	_play("idle")


func _physics_process(_delta: float) -> void:
	if _dead:
		return
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
	if _dead or _locked:
		return
	_locked = true
	_roll_dir = Vector2.ZERO
	_play("hit", true)


## Rolamento na ultima direcao andada.
func roll() -> void:
	if _dead or _locked:
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
	sprite.flip_h = _flip
	sprite.play("death_side")


func _play(base: String, restart: bool = false) -> void:
	var anim := "%s_%s" % [base, _facing]
	sprite.flip_h = _flip and _facing == "side"
	if restart or sprite.animation != anim:
		sprite.play(anim)


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
