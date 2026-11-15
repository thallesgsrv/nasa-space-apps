extends Node
## Teste de integracao do multiplayer em LAN: dois processos Godot conversando por localhost.
##   godot --headless res://tests/net_integration.tscn -- host     (terminal 1)
##   godot --headless res://tests/net_integration.tscn -- client   (terminal 2, logo depois)
## Partida de 4 jogadores (host + 3 clientes + 1 extra que deve ser recusado), por ENet ou WebSocket:
##   godot --headless res://tests/net_integration.tscn -- host4 ws        (ou enet)
##   godot --headless res://tests/net_integration.tscn -- crew 0 ws       (0 = cientista, 1 = engenheiro,
##                                                                          2 = astronauta 2, 3 = recusado)
## Use tools/run_net_tests.sh para subir tudo de uma vez.
## Cada lado imprime "HOST OK" / "CLIENT OK" e sai com codigo 0; qualquer falha sai com 1.

var _fails := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		_fails += 1
		print("  FALHOU: ", msg)


func _wait_until(cond: Callable, timeout: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().create_timer(0.05).timeout
		t += 0.05
		if t > timeout:
			return false
	return true


func _ready() -> void:
	var role := "host"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		role = args[0]
	if role == "host":
		await _host()
	elif role == "browse":
		await _browse()
	elif role == "host4":
		await _host4(args[1] if args.size() > 1 else "enet")
	elif role == "planhost":
		await _plan_host()
	elif role == "plancrew":
		await _plan_crew()
	elif role == "seehost":
		await _see_host()
	elif role == "seeclient":
		await _see_client()
	elif role == "crew":
		await _crew(int(args[1]), args[2] if args.size() > 2 else "enet")
	else:
		await _client()
	print("%s %s" % [role.to_upper(), "OK" if _fails == 0 else "FALHOU"])
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(1 if _fails > 0 else 0)


func _host() -> void:
	check(Net.host_game() == OK, "criar sala")
	check(await _wait_until(func(): return Net.partner_connected, 30.0), "cliente conectou")
	Net.begin_game()
	GameState.reset()
	GameState.running = true
	Missions.start("bionutrientes")
	GameState.food = 77.0
	GameState.add_item("cafe")
	check(await _wait_until(func(): return Net.partner_room == "Laboratório (Terra)", 20.0), "recebeu a sala do cliente")
	check(await _wait_until(func(): return Missions.analyzed, 20.0), "analise pedida pelo cliente rodou no host")
	check(Missions.sample_color != "", "host tem a cor da amostra")
	# o cliente pediu o veredito: o host aplicou as regras
	check(await _wait_until(func(): return Missions.flags.has("energia_extra") or Missions.flags.has("nave_leve") or Missions.flags.has("envenenamento") or Missions.result_lines.size() > 0, 20.0), "veredito executado no host")
	await get_tree().create_timer(1.0).timeout


# ---------------------------------------------------------------- planejamento em equipe (CML)
## Confirma sozinho a alternativa 0 sempre que a prancheta pede uma decisao (nos dois lados).
func _auto_confirm(secs: float) -> void:
	var t := 0.0
	while t < secs:
		await get_tree().create_timer(0.1).timeout
		t += 0.1
		var b: Control = MissionState._board
		if is_instance_valid(b) and b.is_deciding():
			b._sel = 0
			b._confirm()


func _plan_host() -> void:
	check(Net.host_game(Net.WS_PORT, true) == OK, "criar sala (ws)")
	check(await _wait_until(func(): return Net.roster.size() == 2, 30.0), "1 cliente entrou")
	Net.begin_game()
	GameState.reset()
	GameState.running = false
	_auto_confirm(40.0)
	MissionState._begin_planning()
	await MissionState._cml1()          # voto: os dois jogadores votam
	check(MissionState.cml_done == 1 and MissionState.objective != "", "CML 1 votado e resolvido (%s)" % MissionState.objective)
	check(MissionState.plan_owners.size() == 9, "9 donos de CML replicados")
	await MissionState._cml2()          # cada conjunto tem um dono; um deles e o cliente
	await MissionState._cml4()
	check(MissionState.cml_done == 4, "CML 2 a 4 concluidos (um deles decidido pelo outro jogador)")
	check(MissionState.decisions.size() >= 3, "decisoes registradas (%d)" % MissionState.decisions.size())
	MissionState._planning = false
	MissionState.planning_active = false
	MissionState.changed.emit()
	await get_tree().create_timer(2.0).timeout


func _plan_crew() -> void:
	check(Net.join_url("ws://127.0.0.1:%d" % Net.WS_PORT) == OK, "criar cliente")
	check(await _wait_until(func(): return Net.roster.size() == 2 and Net.roster.has(multiplayer.get_unique_id()), 30.0), "roster chegou")
	Net.begin_game()
	_auto_confirm(40.0)
	check(await _wait_until(func(): return MissionState.planning_active, 20.0), "prancheta aberta no cliente pelo host")
	check(await _wait_until(func(): return MissionState.cml_done >= 4, 30.0), "cliente acompanhou ate o CML 4")
	check(MissionState.decisions.size() >= 3, "decisoes replicadas no cliente")
	check(await _wait_until(func(): return not MissionState.planning_active, 20.0), "planejamento encerrado no cliente")
	await get_tree().create_timer(1.0).timeout


func _client() -> void:
	check(Net.join_game("127.0.0.1") == OK, "criar cliente")
	var connected := await _wait_until(func(): return Net.mode == Net.Mode.CLIENT and multiplayer.multiplayer_peer != null and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED, 20.0)
	check(connected, "conectou ao host")
	Net.begin_game()
	check(await _wait_until(func(): return Missions.active == "bionutrientes" and is_equal_approx(GameState.inventory.size(), 1), 20.0), "snapshot chegou (missao + mochila)")
	check(GameState.inventory == ["cafe"], "mochila espelhada")
	check(GameState.food <= 77.0 and GameState.food > 0.0, "comida espelhada")
	check(Net.has_partner(), "has_partner no cliente")
	# a simulacao do cliente nao roda sozinha: o estado so muda por snapshot
	var food_before := GameState.food
	GameState._process(5.0)
	check(GameState.food == food_before, "GameState do cliente nao simula")
	# chamada remota permitida
	var color = await Net.call_host("Missions", "analyze_sample", [], "")
	check(color is String and color != "", "analyze_sample devolveu a cor")
	check(Missions.analyzed and Missions.sample_color == color, "estado ja espelhado quando a chamada volta")
	# chamada fora da lista e recusada
	var denied = await Net.call_host("GameState", "reset", [], "recusado")
	check(denied == "recusado", "chamada fora da lista recusada")
	check(GameState.inventory == ["cafe"] or GameState.inventory.size() == 1, "reset nao rodou no host")
	var lines = await Net.call_host("Missions", "verdict", [true], [])
	check(lines is Array and lines.size() == 2, "verdict devolveu as linhas")
	Net.send_room("Laboratório (Terra)")
	await get_tree().create_timer(1.0).timeout


## Descoberta automatica: com um host rodando (papel "host"), o navegador acha a sala por broadcast UDP.
func _browse() -> void:
	Net.start_browsing()
	check(Net.mode == Net.Mode.OFFLINE, "navegar nao muda o modo")
	var found := await _wait_until(func(): return not Net.hosts.is_empty(), 15.0)
	check(found, "sala encontrada por broadcast")
	if found:
		var ip: String = Net.hosts.keys()[0]
		print("  sala: ", ip, " -> ", Net.hosts[ip])
		check(int(Net.hosts[ip]["port"]) == Net.PORT, "porta anunciada")


# ---------------------------------------------------------------- 4 jogadores
func _host4(kind: String) -> void:
	var ws := kind == "ws"
	check(Net.host_game(Net.WS_PORT if ws else Net.PORT, ws) == OK, "criar sala (%s)" % kind)
	check(await _wait_until(func(): return Net.roster.size() == 4, 30.0), "3 clientes entraram")
	check(Net.roster[1]["role"] == Net.Role.ASTRONAUT, "host e o comandante")
	var roles := {}
	for id in Net.roster:
		roles[int(Net.roster[id]["role"])] = true
	check(roles.size() == 4, "4 papeis diferentes")
	Net.begin_game()
	GameState.reset()
	GameState.running = false   # o calor nao muda sozinho: o teste controla
	GameState.heat = 80.0
	Net.report_pose("res://scenes/rooms/cafeteria.tscn", Vector2(11, 22), 0)
	# posicoes dos 3 clientes chegam ao host
	check(await _wait_until(func(): return Net.others().size() == 3 and Net.others().all(func(o): return String(o["scene"]) != ""), 20.0), "host recebeu a posicao dos 3 clientes")
	var sci_scene := ""
	for o in Net.others():
		if int(o["role"]) == Net.Role.SCIENTIST:
			sci_scene = String(o["scene"])
	check(sci_scene == "res://scenes/rooms/laboratorio.tscn", "posicao do cientista replicada")
	# o engenheiro resfria o nucleo; o pedido do cientista foi recusado antes
	check(await _wait_until(func(): return GameState.heat <= 31.0, 30.0), "engenheiro resfriou o nucleo (host)")
	check(GameState.heat > 29.0, "so um resfriamento (o do cientista foi negado)")
	check(await _wait_until(func(): return Net.roster.size() == 4, 5.0), "5o cliente nao entrou")
	await get_tree().create_timer(9.0).timeout   # deixa os clientes terminarem antes de fechar a sala


func _crew(idx: int, kind: String) -> void:
	var ws := kind == "ws"
	await get_tree().create_timer(0.6 * idx).timeout   # entram em ordem: papeis previsiveis
	var err := Net.join_url("ws://127.0.0.1:%d" % Net.WS_PORT) if ws else Net.join_game("127.0.0.1")
	check(err == OK, "criar cliente")
	if idx == 3:
		# a sala esta cheia: o host derruba a conexao
		var dropped := await _wait_until(func(): return Net.mode == Net.Mode.OFFLINE, 20.0)
		check(dropped, "5o jogador foi recusado")
		return
	check(await _wait_until(func(): return Net.roster.size() == 4 and Net.roster.has(multiplayer.get_unique_id()), 30.0), "roster completo chegou")
	var expected: int = [Net.Role.SCIENTIST, Net.Role.ENGINEER, Net.Role.ASTRONAUT2][idx]
	check(Net.my_role == expected, "papel atribuido na ordem de entrada")
	check(Net.is_crew_client() == (idx != 0), "is_crew_client coerente com o papel")
	Net.begin_game()
	var scenes := ["res://scenes/rooms/laboratorio.tscn", "res://scenes/rooms/sala_reator.tscn", "res://scenes/rooms/dormitorio.tscn"]
	Net.report_pose(scenes[idx], Vector2(100 * (idx + 1), 50), 0)
	# o cliente ve a posicao do host
	var host_seen := await _wait_until(func():
		for o in Net.others():
			if int(o["id"]) == 1 and String(o["scene"]) == "res://scenes/rooms/cafeteria.tscn" and (o["pos"] as Vector2).is_equal_approx(Vector2(11, 22)):
				return true
		return false, 20.0)
	check(host_seen, "cliente recebeu a posicao do host")
	check(Net.others().size() == 3, "cada cliente ve os outros 3")
	check(await _wait_until(func(): return is_equal_approx(GameState.heat, 80.0), 10.0), "estado do host espelhado")
	if idx == 0:
		# cientista nao pode resfriar o nucleo
		await Net.call_host("GameState", "crew_cool_core", [], null)
		check(is_equal_approx(GameState.heat, 80.0), "cientista nao resfria o nucleo")
		var v = await Net.call_host("Missions", "analyze_sample", [], "")
		check(v is String, "cientista pode analisar amostra")
	elif idx == 1:
		await get_tree().create_timer(2.0).timeout   # depois da tentativa negada do cientista
		await Net.call_host("GameState", "crew_cool_core", [], null)
		check(await _wait_until(func(): return GameState.heat <= 31.0, 10.0), "engenheiro resfria o nucleo")
		# engenheiro nao decide pela base
		await Net.call_host("Solar", "decide", [true], [])
		check(not Solar.decided, "engenheiro nao decide o alerta solar")
	await get_tree().create_timer(3.0).timeout


# ---------------------------------------------------------------- fantasmas na cena de jogo real
## Dois processos com game.tscn de verdade: o engenheiro e o comandante, na mesma sala, precisam se enxergar.
func _ghost_visible(game: Node, role: int) -> bool:
	for id in game._ghosts:
		var g: Node2D = game._ghosts[id]
		var anim: String = g.current_animation()
		if g.get_parent() != null and g.is_inside_tree() and g.role == role and (anim.begins_with("idle") or anim.begins_with("run")):
			return true
	return false


func _see_host() -> void:
	check(Net.host_game() == OK, "criar sala")
	check(await _wait_until(func(): return Net.partner_connected and Net.roster.size() == 2, 30.0), "cliente entrou")
	check(await _wait_until(func(): return int(Net.roster.values().filter(func(e): return int(e["role"]) == Net.Role.ENGINEER).size()) == 1, 20.0), "cliente virou engenheiro")
	Net.begin_game()
	GameState.reset()
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	check(await _wait_until(func(): return _ghost_visible(game, Net.Role.ENGINEER), 25.0), "HOST ve o fantasma laranja do engenheiro")
	await get_tree().create_timer(4.0).timeout


func _see_client() -> void:
	check(Net.join_game("127.0.0.1") == OK, "entrar")
	check(await _wait_until(func(): return Net.roster.size() == 2, 20.0), "roster")
	Net.request_role(Net.Role.ENGINEER)
	check(await _wait_until(func(): return Net.my_role == Net.Role.ENGINEER, 10.0), "trocou para engenheiro")
	Net.begin_game()
	GameState.reset()
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	check(await _wait_until(func(): return _ghost_visible(game, Net.Role.ASTRONAUT), 25.0), "ENGENHEIRO ve o astronauta do host")
	await get_tree().create_timer(2.0).timeout
