extends Area2D
## Zona de interacao (tecla F). O jogador encosta na zona e aparece "[F] <nome>".
## "action" diz o que acontece (veja scripts/interactions.gd).
## A CollisionShape2D filha e a area onde o jogador pode ficar para interagir:
## cubra o objeto E um pedaco do chao na frente dele.

@export var action: String = ""
@export var display_name: String = "Usar"


func _ready() -> void:
	# camada 2 = interativos (o sensor do jogador olha so para ela)
	collision_layer = 2
	collision_mask = 0
	monitoring = false
	monitorable = true
