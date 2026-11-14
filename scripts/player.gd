extends CharacterBody2D
## Astronauta controlado pelo jogador: anda para cima, baixo, esquerda e direita.
## Sem animacao por enquanto: so troca a imagem conforme a direcao.
## Teclas: WASD ou setas.

@export var speed: float = 300.0

@onready var sprite: Sprite2D = $Sprite2D

const TEX_UP := preload("res://assets/player/player_up.png")
const TEX_DOWN := preload("res://assets/player/player_down.png")
const TEX_SIDE := preload("res://assets/player/player_side.png") # sprite original olha para a ESQUERDA


func _ready() -> void:
	_setup_input()
	_show_sprite(TEX_DOWN, false)


func _physics_process(_delta: float) -> void:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * speed
	move_and_slide()

	if dir == Vector2.ZERO:
		return # parado: mantem o ultimo sprite

	# Diagonal: o eixo horizontal vence o empate.
	if absf(dir.x) >= absf(dir.y):
		_show_sprite(TEX_SIDE, dir.x > 0.0) # direita = sprite da esquerda espelhado
	elif dir.y < 0.0:
		_show_sprite(TEX_UP, false)
	else:
		_show_sprite(TEX_DOWN, false)


func _show_sprite(tex: Texture2D, flip: bool) -> void:
	sprite.texture = tex
	sprite.flip_h = flip
	# Origem do personagem = pes (centro da base da imagem).
	sprite.offset = Vector2(0, -tex.get_height() / 2.0)


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
