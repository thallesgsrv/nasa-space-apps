extends Node2D
## Raiz de cada sala. Estrutura esperada:
##   Fundo (Sprite2D) | Colisoes (StaticBody2D) | Portas (Area2D com door.gd) | Spawns (Marker2D)
## Cada Marker2D em "Spawns" e um ponto de chegada, normalmente chamado "from_<sala de origem>".

const FALLBACK_SPAWN := Vector2(768, 512)


func get_spawn_position(spawn_name: String) -> Vector2:
	var marker := get_node_or_null("Spawns/" + spawn_name) as Marker2D
	if marker == null:
		push_warning("Spawn '%s' nao existe em %s" % [spawn_name, name])
		return FALLBACK_SPAWN
	return marker.global_position
