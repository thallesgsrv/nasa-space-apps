extends Node
## Cena principal: mantem o jogador, carrega uma sala por vez e faz a transicao com fade.

const START_ROOM := "res://scenes/rooms/cafeteria.tscn"
const START_SPAWN := "start"
const EARTH_ROOM := "res://scenes/rooms/laboratorio.tscn"
const EARTH_SPAWN := "from_station"
const SCIENTIST_SCENE := preload("res://scenes/scientist.tscn")
const GHOST := preload("res://scripts/ghost.gd")

@export var fade_time: float = 0.35

@onready var world: Node2D = $World
@onready var astronaut: CharacterBody2D = $World/Player
@onready var fade: ColorRect = $FadeLayer/Fade

var player: CharacterBody2D   # personagem controlado agora (astronauta na estacao, cientista na Terra)
var scientist: CharacterBody2D
var _room: Node2D
var _busy := false
var _game_over := false
var _on_earth := false
var _saved_room := ""         # sala da estacao onde o astronauta ficou
var _saved_pos := Vector2.ZERO
var _partner_label: Label   # multiplayer: quem e o parceiro e onde ele esta
var _report_shown := false
var _ghosts: Dictionary = {}   # id do peer -> fantasma (outro jogador na mesma sala)


func _ready() -> void:
	player = astronaut
	scientist = SCIENTIST_SCENE.instantiate()
	fade.color.a = 1.0 # comeca preto e clareia
	GameState.exploded.connect(_on_exploded)
	GameState.failed.connect(_on_failed)
	UI.fade_to(0.0, 0.0) # tira o escurecimento do menu inicial
	UI.show_hud(true)
	GameState.running = true
	if Net.is_online():
		Net.begin_game()
		Net.partner_left.connect(_on_partner_left)
		Net.partner_room_changed.connect(_refresh_partner_label)
		Net.roster_changed.connect(_refresh_partner_label)
		_build_partner_label()
	if Net.is_crew_client():
		# engenheiro / astronauta 2: o proprio astronauta tambem usa a cor do papel
		var suit := GHOST.frames_for(Net.my_role)
		var anim := astronaut.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
		if suit != null and anim != null:
			anim.sprite_frames = suit
	if Net.is_client() and not Net.is_crew_client():
		# multiplayer: a BASE na Terra (cientista); o host e o astronauta na estacao
		world.remove_child(astronaut)
		player = scientist
		world.add_child(scientist)
		_on_earth = true
		_load_room(EARTH_ROOM, EARTH_SPAWN)
	else:
		_load_room(START_ROOM, START_SPAWN)
	await _fade_to(0.0)
	if Net.is_client():
		if Net.is_crew_client():
			UI.toast(tr("Você é %s na estação. Núcleo e escudos são com você; o comandante conduz a missão.") % Net.role_name(Net.my_role), 6.0)
		else:
			UI.toast(tr("Você é a BASE na Terra (cientista). Seu parceiro é o astronauta na estação."), 6.0)
		MissionState.changed.connect(_show_report_for_client)
		return   # tutorial e missoes sao conduzidos pelo host
	if not GameState.tutorial_done:
		GameState.tutorial_done = true
		player.locked = true
		await Interactions.show_tutorial()
		if not MissionState.planned and not MissionState.planning_disabled:
			await MissionState.run_planning()   # fase na Terra: CML 1 a 9 (ou plano padrao)
		player.locked = false
		if Missions.active == "" and Missions.finished.is_empty():
			Missions.start("bionutrientes")


func _process(_delta: float) -> void:
	if not Net.is_online() or _room == null:
		return
	Net.report_pose(_room.scene_file_path, player.global_position, 0)
	_update_ghosts()


func _update_ghosts() -> void:
	var seen := {}
	for o in Net.others():
		var id := int(o["id"])
		seen[id] = true
		if not _ghosts.has(id):
			var g := Node2D.new()
			g.set_script(GHOST)
			g.setup(id, int(o["role"]), String(o["name"]))
			_ghosts[id] = g
		var ghost: Node2D = _ghosts[id]
		var here: bool = String(o["scene"]) == _room.scene_file_path and not _busy
		if here and ghost.get_parent() == null:
			world.add_child(ghost)
		elif not here and ghost.get_parent() != null:
			world.remove_child(ghost)
		if here:
			ghost.set_target(o["pos"])
	for id in _ghosts.keys():
		if not seen.has(id):
			var gone: Node2D = _ghosts[id]
			if gone.get_parent() != null:
				world.remove_child(gone)
			gone.queue_free()
			_ghosts.erase(id)


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
	Audio.play_room(_room.room_id())   # ambiente da sala (fade)
	world.move_child(_room, 0) # sala atras, jogador na frente
	for door in _room.find_children("*", "Area2D", true, false):
		if door.has_signal("used"):
			door.used.connect(change_room)
	if spawn_name != "":
		player.global_position = _room.get_spawn_position(spawn_name)
	player.velocity = Vector2.ZERO
	var place = _room.get("place_name")
	if place != null and String(place) != "":
		UI.toast(tr(String(place)), 2.2)
		Net.send_room(String(place))   # multiplayer: o parceiro ve onde voce esta


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fade, "color:a", alpha, fade_time)
	await tween.finished


# Tecla 1: alterna entre a estacao (astronauta) e a Terra (cientista).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("switch_world") and not event.is_echo():
		toggle_world()


func toggle_world() -> void:
	if Net.has_partner():
		UI.toast(tr("No multiplayer cada jogador tem o seu papel: astronauta (host) e cientista (cliente)."), 3.5)
		return
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
		UI.toast(tr("Terra: você controla o cientista. Aperte 1 para voltar à estação."), 4.0)
	else:
		_swap_player(astronaut)
		_load_room(_saved_room, "")
		player.global_position = _saved_pos
		_on_earth = false
		UI.toast(tr("Estação: você controla o astronauta."), 3.0)
	await _fade_to(0.0)
	player.set_physics_process(true)
	_busy = false


# Quem nao esta em jogo sai da arvore (sem colisao nem portas) e volta intacto depois.
func _swap_player(next: CharacterBody2D) -> void:
	if player.get_parent() == world:
		world.remove_child(player)
	player = next
	world.add_child(player)
	player.velocity = Vector2.ZERO


# O nucleo ficou 12 s em 100%: a nave explode.
func _on_exploded() -> void:
	if not _begin_game_over():
		return
	Audio.stop_music(0.2)   # o som da explosao ja tocou durante a contagem
	UI.lock()
	await UI.flash_white()
	UI.unlock()
	await _finish_game_over([tr("BOOM!"), tr("O núcleo do reator superaqueceu e a nave explodiu.")])


# A missao falhou (colisao, tempo, energia, combustivel ou vida zerada): game over.
func _on_failed(reason: String) -> void:
	if not _begin_game_over():
		return
	UI.lock()
	await UI.fade_to(1.0, 0.8)
	UI.unlock()
	await _finish_game_over([tr("MISSÃO FALHOU"), reason])


## Comeca o game over (so uma vez, mesmo que explosao e falha cheguem juntas):
## para o relogio do jogo e fecha qualquer menu/dialogo aberto.
func _begin_game_over() -> bool:
	if _game_over:
		return false
	_game_over = true
	GameState.running = false
	player.locked = true
	UI.dismiss_all()
	return true


func _finish_game_over(lines: Array) -> void:
	lines.append(tr("Fim de jogo."))
	await UI.say(lines)
	var i: int
	if Net.is_client():
		# multiplayer: quem decide e o host; o cliente espera a escolha dele
		UI.toast(tr("Aguardando o host decidir..."), 600.0)
		i = await Net.wait_restart_decision()
	else:
		i = await UI.choose([tr("Recomeçar"), tr("Menu inicial")], tr("Game over"))
		if Net.has_partner():
			Net.send_restart_decision(i)
			await get_tree().create_timer(0.3).timeout   # deixa a mensagem sair antes de trocar de cena
	GameState.reset()
	if Net.is_online() and i != 0:
		Net.leave()
	get_tree().change_scene_to_file("res://scenes/game.tscn" if i == 0 else "res://scenes/start_menu.tscn")


# ---------------------------------------------------------------- multiplayer
func _build_partner_label() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_partner_label = Label.new()
	_partner_label.add_theme_font_override("font", preload("res://assets/fonts/PixelOperator8.ttf"))
	_partner_label.add_theme_font_size_override("font_size", 20)
	_partner_label.add_theme_color_override("font_color", Color("dfe9ff"))
	_partner_label.add_theme_color_override("font_outline_color", Color("1b2a5c"))
	_partner_label.add_theme_constant_override("outline_size", 6)
	_partner_label.position = Vector2(24, 96)
	layer.add_child(_partner_label)
	_refresh_partner_label()


func _refresh_partner_label() -> void:
	if _partner_label == null:
		return
	var lines: Array[String] = []
	for o in Net.others():
		var where := tr(String(o["room"])) if String(o["room"]) != "" else tr("conectado")
		lines.append("%s (%s): %s" % [Net.role_name(int(o["role"])), o["name"], where])
	_partner_label.text = "\n".join(lines)
	_partner_label.visible = Net.has_partner() and not lines.is_empty()


# multiplayer: o relatorio final tambem aparece para a base (o host o gera e ele chega pelo espelho).
func _show_report_for_client() -> void:
	if _report_shown or MissionState.report.is_empty():
		return
	_report_shown = true
	await UI.show_panel(String(MissionState.report.get("text", "")))


func _on_partner_left() -> void:
	_refresh_partner_label()
	if Net.partner_connected:
		UI.toast(tr("Um jogador saiu da partida. A missão continua com os demais."), 5.0)
	else:
		UI.toast(tr("Todos os outros saíram. Modo solo: aperte 1 para alternar entre os papéis."), 6.0)
