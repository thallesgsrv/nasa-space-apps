extends Node
## Teste de integracao do multiplayer em LAN: dois processos Godot conversando por localhost.
##   godot --headless res://tests/net_integration.tscn -- host     (terminal 1)
##   godot --headless res://tests/net_integration.tscn -- client   (terminal 2, logo depois)
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
