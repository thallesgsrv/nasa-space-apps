extends Node
## Cena principal: mantem o jogador, carrega uma sala por vez e faz a transicao com fade.

const START_ROOM := "res://scenes/rooms/cafeteria.tscn"
const START_SPAWN := "start"

@export var fade_time: float = 0.35

@onready var world: Node2D = $World
@onready var player: CharacterBody2D = $World/Player
@onready var fade: ColorRect = $FadeLayer/Fade

var _room: Node2D
var _busy := false


func _ready() -> void:
	fade.color.a = 1.0 # comeca preto e clareia
	_load_room(START_ROOM, START_SPAWN)
	await _fade_to(0.0)


func change_room(room_path: String, spawn_name: String) -> void:
	if _busy or room_path.is_empty():
		return
	_busy = true
	player.set_physics_process(false) # congela o jogador durante a troca
	await _fade_to(1.0)
	_load_room(room_path, spawn_name)
	await _fade_to(0.0)
	player.set_physics_process(true)
	_busy = false


func _load_room(room_path: String, spawn_name: String) -> void:
	if _room != null:
		_room.queue_free()
		world.remove_child(_room) # sai da arvore agora, evita portas antigas disparando
	var scene := load(room_path) as PackedScene
	if scene == null:
		push_error("Sala nao encontrada: " + room_path)
		return
	_room = scene.instantiate()
	world.add_child(_room)
	world.move_child(_room, 0) # sala atras, jogador na frente
	for door in _room.find_children("*", "Area2D", true, false):
		if door.has_signal("used"):
			door.used.connect(change_room)
	player.global_position = _room.get_spawn_position(spawn_name)
	player.velocity = Vector2.ZERO


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fade, "color:a", alpha, fade_time)
	await tween.finished
