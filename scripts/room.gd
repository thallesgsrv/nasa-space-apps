extends Node2D
## Raiz de cada sala. Estrutura esperada:
##   Fundo (Sprite2D) | Colisoes (StaticBody2D) | Portas (Area2D com door.gd)
##   Interativos (Area2D com interactable.gd) | Spawns (Marker2D)
## Cada Marker2D em "Spawns" e um ponto de chegada, normalmente chamado "from_<sala de origem>".
## A sala tambem guia o jogador: marca o objetivo da missao (ou a porta no caminho) com um "!" azul.

const FALLBACK_SPAWN := Vector2(768, 512)

## Nome mostrado ao chegar na sala
@export var place_name: String = ""


func _ready() -> void:
	Missions.changed.connect(refresh_guide)
	GameState.inventory_changed.connect(refresh_guide)
	refresh_guide()


func room_id() -> String:
	return scene_file_path.get_file().get_basename()


func get_spawn_position(spawn_name: String) -> Vector2:
	var marker := get_node_or_null("Spawns/" + spawn_name) as Marker2D
	if marker == null:
		push_warning("Spawn '%s' nao existe em %s" % [spawn_name, name])
		return FALLBACK_SPAWN
	return marker.global_position


## Marca o objetivo atual: na sala certa, a zona do objeto; nas outras, a porta que leva a ele.
## (Todas as salas da estacao ligam pela cafeteria; a Terra e outro "mundo".)
func refresh_guide() -> void:
	var tgt: Dictionary = Missions.current_target()
	var here := room_id()
	var same_world: bool = not tgt.is_empty() and (tgt["room"] == "laboratorio") == (here == "laboratorio")
	var door_name := ""
	if same_world and tgt["room"] != here:
		door_name = "Porta_" + String(tgt["room"] if here == "cafeteria" else "cafeteria")
	var inter := get_node_or_null("Interativos")
	if inter != null:
		for it in inter.get_children():
			if it.has_method("set_highlight"):
				it.set_highlight(same_world and tgt["room"] == here and it.action == tgt["action"])
	var doors := get_node_or_null("Portas")
	if doors != null:
		for d in doors.get_children():
			if d.has_method("set_guided"):
				d.set_guided(String(d.name) == door_name)
