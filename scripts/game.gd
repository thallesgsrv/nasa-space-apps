extends Node
## Cena principal: mantem o jogador, carrega uma sala por vez e faz a transicao com fade.

const START_ROOM := "res://scenes/rooms/cafeteria.tscn"
const START_SPAWN := "start"
const EARTH_ROOM := "res://scenes/rooms/laboratorio.tscn"
const EARTH_SPAWN := "from_station"
const SCIENTIST_SCENE := preload("res://scenes/scientist.tscn")

@export var fade_time: float = 0.35

@onready var world: Node2D = $World
@onready var astronaut: CharacterBody2D = $World/Player
@onready var fade: ColorRect = $FadeLayer/Fade

var player: CharacterBody2D
var scientist: CharacterBody2D
var _room: Node2D
var _busy := false
var _on_earth := false
var _saved_room := ""
var _saved_pos := Vector2.ZERO


func _ready() -> void:
	player = astronaut
	scientist = SCIENTIST_SCENE.instantiate()
	fade.color.a = 1.0
	UI.fade_to(0.0, 0.0)
	UI.show_hud(true)
	GameState.running = true
	_load_room(START_ROOM, START_SPAWN)
	await _fade_to(0.0)
	if not GameState.tutorial_done:
		GameState.tutorial_done = true
		player.locked = true
		await Interactions.show_tutorial()
		player.locked = false


func change_room(room_path: String, spawn_name: String) -> void:
	if _busy or room_path.is_empty():
		return
	_busy = true
	player.set_physics_process(false)
	await _fade_to(1.0)
	_load_room(room_path, spawn_name)
	await _fade_to(0.0)
	player.set_physics_process(true)
	_busy = false


func _load_room(room_path: String, spawn_name: String) -> void:
	if _room != null:
		_room.queue_free()
		world.remove_child(_room)
	var scene := load(room_path) as PackedScene
	if scene == null:
		push_error("Sala nao encontrada: " + room_path)
		return
	_room = scene.instantiate()
	world.add_child(_room)
	world.move_child(_room, 0)
	_bind_room_doors()
	if spawn_name != "":
		player.global_position = _room.get_spawn_position(spawn_name)
	player.velocity = Vector2.ZERO


func _bind_room_doors() -> void:
	for door in _room.find_children("*", "Area2D", true, false):
		if door.has_signal("used"):
			door.used.connect(change_room)


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fade, "color:a", alpha, fade_time)
	await tween.finished


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_world") and not event.is_echo():
		toggle_world()


func toggle_world() -> void:
	if _busy or UI.busy or player.locked or player.seated:
		return
	_busy = true
	player.set_physics_process(false)
	await _fade_to(1.0)
	if not _on_earth:
		_saved_room = _room.scene_file_path
		_saved_pos = player.global_position
		_swap_player(scientist)
		_load_room(EARTH_ROOM, EARTH_SPAWN)
		_on_earth = true
		UI.toast("Terra: você controla o cientista. Aperte 1 para voltar à estação.", 4.0)
	else:
		_swap_player(astronaut)
		_load_room(_saved_room, "")
		player.global_position = _saved_pos
		_on_earth = false
		UI.toast("Estação: você controla o astronauta.", 3.0)
	await _fade_to(0.0)
	player.set_physics_process(true)
	_busy = false


func _swap_player(next: CharacterBody2D) -> void:
	if player.get_parent() == world:
		world.remove_child(player)
	player = next
	world.add_child(player)
	player.velocity = Vector2.ZERO
