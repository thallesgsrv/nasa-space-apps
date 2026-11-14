extends Area2D
## Zona de passagem entre salas. Quando o jogador encosta, avisa o jogo para trocar de sala.
## Posicione/redimensione a CollisionShape2D no editor para ajustar onde a porta dispara.

signal used(target_room: String, target_spawn: String)

## Cena da sala de destino (ex.: res://scenes/rooms/dormitorio.tscn)
@export_file("*.tscn") var target_room: String = ""
## Nome do Marker2D (dentro de "Spawns" da sala de destino) onde o jogador aparece
@export var target_spawn: String = ""


func _ready() -> void:
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		used.emit(target_room, target_spawn)
