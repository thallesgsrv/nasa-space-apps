extends CharacterBody2D
## Personagem controlado pelo jogador (WASD ou setas). Serve para o astronauta e para o cientista.
## - Astronauta: AnimatedSprite2D com assets/player/player_frames.tres (idle/run/hit em down, up e side;
##   roll e death so em side, a direita e o lado "natural" do sprite, a esquerda usa flip_h).
## - Cientista (ou qualquer personagem sem animacao): Sprite2D com as imagens tex_up/tex_down/tex_side.
## F / Enter / Espaco interage com o objeto mais proximo; I / Tab abre a mochila; M / J abre as missoes.

@export var speed: float = 300.0
@export var roll_speed: float = 520.0
## Imagens fixas (so usadas quando a cena tem um Sprite2D em vez do AnimatedSprite2D).
@export var tex_up: Texture2D = preload("res://assets/player/player_up.png")
@export var tex_down: Texture2D = preload("res://assets/player/player_down.png")
@export var tex_side: Texture2D = preload("res://assets/player/player_side.png")
## true: a imagem lateral original olha para a ESQUERDA; false: olha para a DIREITA (cientista)
@export var side_faces_left: bool = true

@onready var anim_sprite: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D")
@onready var sprite: Sprite2D = get_node_or_null("Sprite2D")
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var sensor: Area2D = $InteractSensor

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")

var locked := false          # em interacao (menu/dialogo)
var seated := false          # sentado na cadeira de comando
var _target: Area2D
var _prompt: Label

var _facing := "down"        # "down" | "up" | "side"
var _flip := false           # true = olhando para a esquerda (so vale em "side")
var _last_dir := Vector2.DOWN
var _anim_locked := false    # hit/roll tocando: sem controle
var _dead := false
var _roll_dir := Vector2.ZERO


func _ready() -> void:
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
	if anim_sprite != null:
		anim_sprite.animation_finished.connect(_on_animation_finished)
	_refresh_visual(false)


func _physics_process(_delta: float) -> void:
	if _dead:
		return
	if _anim_locked:
		velocity = _roll_dir * roll_speed
		move_and_slide()
		return
	if locked or seated or UI.busy:
		velocity = Vector2.ZERO
		_prompt.visible = false
		_refresh_visual(false)
		return

	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if Solar.inverted_left > 0.0:
		dir = -dir   # interferencia da tempestade solar
	velocity = dir * speed
	move_and_slide()

	if dir != Vector2.ZERO:
		_last_dir = dir
		# Diagonal: o eixo horizontal vence o empate.
		if absf(dir.x) >= absf(dir.y):
			_facing = "side"
			_flip = dir.x < 0.0
		elif dir.y < 0.0:
			_facing = "up"
		else:
			_facing = "down"
	_refresh_visual(dir != Vector2.ZERO)
	_update_target()


# ---------------------------------------------------------------- animacao
## Toca a animacao de dano (o jogador perde o controle ate ela terminar). So astronauta animado.
func hit() -> void:
	if anim_sprite == null or _dead or _anim_locked:
		return
	_anim_locked = true
	_roll_dir = Vector2.ZERO
	_play("hit", true)


## Rolamento na ultima direcao andada. So astronauta animado.
func roll() -> void:
	if anim_sprite == null or _dead or _anim_locked:
		return
	_anim_locked = true
	_roll_dir = _last_dir.normalized()
	if absf(_roll_dir.x) > 0.1:
		_flip = _roll_dir.x < 0.0
	anim_sprite.flip_h = _flip
	anim_sprite.play("roll_side")


## Animacao de morte; o personagem fica deitado no ultimo frame. So astronauta animado.
func die() -> void:
	if anim_sprite == null or _dead:
		return
	_dead = true
	_anim_locked = true
	velocity = Vector2.ZERO
	anim_sprite.flip_h = _flip
	anim_sprite.play("death_side")


func _refresh_visual(moving: bool) -> void:
	if anim_sprite != null:
		_play("run" if moving else "idle")
	elif sprite != null:
		var tex := tex_down
		var flip := false
		match _facing:
			"up":
				tex = tex_up
			"side":
				tex = tex_side
				# _flip = olhando para a esquerda; a imagem original olha para um lado so
				flip = (not _flip) if side_faces_left else _flip
		sprite.texture = tex
		sprite.flip_h = flip
		# Origem do personagem = pes (centro da base da imagem).
		sprite.offset = Vector2(0, -tex.get_height() / 2.0)


func _play(base: String, restart: bool = false) -> void:
	if sprite == null:
		_show_still()
		return
	var anim := "%s_%s" % [base, _facing]
	anim_sprite.flip_h = _flip and _facing == "side"
	if restart or anim_sprite.animation != anim:
		anim_sprite.play(anim)


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
	var anim := String(anim_sprite.animation)
	if anim.begins_with("hit") or anim.begins_with("roll"):
		_anim_locked = false
		_roll_dir = Vector2.ZERO
		_play("idle", true)


# ---------------------------------------------------------------- interacao
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
	elif event.is_action_pressed("missions") and not event.is_echo():
		get_viewport().set_input_as_handled()
		_run_locked(Interactions.open_missions)


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
		_prompt.text = "[F] " + tr(str(_target.display_name))


## Senta numa posicao (cadeira de comando): sem colisao e sem andar, olhando para a esquerda.
func sit(pos: Vector2) -> void:
	seated = true
	velocity = Vector2.ZERO
	body_shape.set_deferred("disabled", true)
	global_position = pos
	_facing = "side"
	_flip = true
	_refresh_visual(false)


func stand(pos: Vector2) -> void:
	seated = false
	global_position = pos
	body_shape.set_deferred("disabled", false)
