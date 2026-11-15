extends Node
## Testes automatizados (headless). Rode da raiz do projeto:
##   godot --headless res://tests/run_tests.tscn
## Sai com codigo 0 se tudo passou e 1 se algo falhou. Os autoloads (GameState, Voyage...) sao os reais.

var _fails := 0
var _checks := 0


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if cond:
		return
	_fails += 1
	print("  FALHOU: ", msg)


func section(name: String) -> void:
	print("# ", name)


func _ready() -> void:
	seed(12345)
	await _test_scenes_load()
	_test_restart_clears_state()
	_test_death_by_zero_health()
	await _test_dismiss_all_unblocks_menu()
	_test_mission1_flow()
	_test_voyage_arrival()
	_test_voyage_failures()
	_test_reactor_heat_never_cools()
	_test_solar_flow()
	_test_translations()
	_test_assets_referenced_exist()
	await _test_every_interaction_and_minigame()
	await _test_game_over_flow_in_game_scene()
	print("\n%d verificacoes, %d falhas" % [_checks, _fails])
	get_tree().quit(1 if _fails > 0 else 0)


# ---------------------------------------------------------------- cenas
func _test_scenes_load() -> void:
	section("todas as cenas carregam e instanciam")
	var stack: Array = ["res://scenes"]
	while stack.size() > 0:
		var d: String = stack.pop_back()
		for f in DirAccess.get_files_at(d):
			if not f.ends_with(".tscn"):
				continue
			var scene := load(d + "/" + f) as PackedScene
			check(scene != null, "carregar " + f)
			if scene == null:
				continue
			var n := scene.instantiate()
			check(n != null, "instanciar " + f)
			if n != null:
				n.free()
		for sd in DirAccess.get_directories_at(d):
			stack.append(d + "/" + sd)
	await get_tree().process_frame


# ---------------------------------------------------------------- reinicio
func _test_restart_clears_state() -> void:
	section("GameState.reset() limpa o que sobrevive entre partidas")
	Voyage.start("Lua")
	UI.realtime = true
	UI.lock()
	GameState.food = 3.0
	Missions.start("bionutrientes")
	GameState.reset()
	check(not Voyage.active, "viagem zerada")
	check(not UI.realtime, "UI.realtime desligado")
	check(not UI.busy, "UI sem travas")
	check(GameState.food == 100.0, "necessidades restauradas")
	check(Missions.active == "", "missao zerada")


func _test_death_by_zero_health() -> void:
	section("vida zerada causa game over")
	GameState.reset()
	var got: Array = []
	var cb := func(reason: String): got.append(reason)
	GameState.failed.connect(cb)
	GameState.running = true
	GameState.health = 0.0
	GameState._process(0.1)
	GameState.failed.disconnect(cb)
	check(got.size() == 1, "failed emitido uma vez (veio %d)" % got.size())
	check(not GameState.running, "relogio do jogo parado")
	GameState.running = false
	GameState.reset()


func _test_dismiss_all_unblocks_menu() -> void:
	section("UI.dismiss_all() libera menu e dialogo pendentes")
	GameState.reset()
	var result := {"menu": 99, "said": false}
	var open_menu := func():
		result["menu"] = await UI.choose(["A", "B"], "teste")
	var open_say := func():
		await UI.say(["um", "dois", "tres"])
		result["said"] = true
	open_menu.call()
	check(UI.busy, "menu aberto trava a UI")
	UI.dismiss_all()
	await get_tree().process_frame
	check(result["menu"] == -1, "menu devolveu -1")
	check(not UI.busy, "UI livre apos dismiss (locks=%d)" % UI._locks)
	open_say.call()
	UI.dismiss_all()
	await get_tree().process_frame
	check(result["said"], "dialogo terminou")
	check(not UI.busy, "UI livre apos fechar dialogo")


# ---------------------------------------------------------------- missao 1
func _test_mission1_flow() -> void:
	section("missao 1 (bionutrientes) do comeco ao fim")
	GameState.reset()
	Missions.start("bionutrientes")
	var order := ["pacotes", "aquecer", "centrifugar", "enviar", "veredito", "retirar"]
	check(Missions.is_step("pacotes"), "comeca em pacotes")
	Missions.complete("aquecer")   # fora de ordem: ignorado
	check(Missions.is_step("pacotes"), "etapa fora de ordem ignorada")
	for i in order.size():
		check(Missions.is_step(order[i]), "etapa " + order[i])
		match order[i]:
			"enviar":
				GameState.add_item("amostra")
				check(GameState.send_to_earth("amostra", true), "enviar amostra para a Terra")
				Missions.send_data()
			"veredito":
				Missions.analyze_sample()
				Missions.verdict(Missions.sample_ok)
				check(not GameState.capsule_hold, "veredito libera a capsula")
				GameState.capsule_left = 0.0
				GameState._capsule_arrived()
				check(GameState.capsule_ready == "amostra", "amostra voltou na capsula")
			"retirar":
				check(GameState.collect_capsule(), "retirar a amostra")
				check(not Missions.take_result().is_empty(), "resultado da base")
			_:
				Missions.complete(order[i])
	check(Missions.finished.has("bionutrientes"), "missao 1 concluida")
	check(Missions.active == "viagem", "proxima missao comeca sozinha (%s)" % Missions.active)
	check(Missions.current_target().get("action", "") == "assento", "guia aponta para a cadeira")
	GameState.reset()


# ---------------------------------------------------------------- viagem
func _tick_trip(max_seconds: float) -> void:
	var t := 0.0
	while Voyage.active and t < max_seconds:
		if Voyage.event == "asteroid" and Voyage.maneuver_available():
			Voyage.maneuver()
		elif Voyage.event == "reactor":
			_solve_reactor()
		Voyage._tick(0.5)
		t += 0.5


## Busca em largura: acha uma sequencia de jogadas que deixa as 5 valvulas certas.
func _solve_reactor() -> void:
	var start: Array = Voyage.reactor["state"].duplicate()
	var seen := {str(start): []}
	var queue: Array = [start]
	while queue.size() > 0:
		var cur: Array = queue.pop_front()
		var path: Array = seen[str(cur)]
		var ok := true
		for i in 5:
			var t: int = Voyage.reactor["targets"][i]
			var good: bool = cur[i] == t or (bool(Voyage.reactor["two"][i]) and cur[i] == (t + 2) % 4)
			if not good:
				ok = false
		if ok:
			for m in path:
				Voyage.press(m)
			return
		for m in 5:
			var nxt: Array = cur.duplicate()
			Voyage._rotate(nxt, m)
			if not seen.has(str(nxt)):
				seen[str(nxt)] = path + [m]
				queue.append(nxt)


func _test_voyage_arrival() -> void:
	section("viagem: chega ao destino tratando os eventos")
	for kind in ["comm", "asteroid", "reactor"]:
		GameState.reset()
		GameState.running = false   # o relogio real nao interfere; a viagem e avancada na mao
		Missions.start("viagem")
		Voyage.start("Lua")
		Missions.complete("rota")
		var failed: Array = []
		var cb := func(r: String): failed.append(r)
		GameState.failed.connect(cb)
		Voyage.next_event = ""
		Voyage.force_event(kind)
		check(Voyage.event == kind, "evento %s disparado" % kind)
		_tick_trip(600.0)
		GameState.failed.disconnect(cb)
		check(failed.is_empty(), "sem falha com evento %s (%s)" % [kind, failed])
		check(Missions.finished.has("viagem"), "viagem concluida apos evento %s" % kind)
	GameState.reset()


func _test_voyage_failures() -> void:
	section("viagem: falhas viram game over")
	var cases := {
		"energia": func(): Voyage.energy = 0.05,
		"combustivel": func(): Voyage.fuel = 0.05,
		"tempo": func(): Voyage.time_left = 0.2,
	}
	for name in cases:
		GameState.reset()
		GameState.running = false
		Voyage.start("Marte")
		cases[name].call()
		var got: Array = []
		var cb := func(r: String): got.append(r)
		GameState.failed.connect(cb)
		Voyage._tick(1.0)
		GameState.failed.disconnect(cb)
		check(got.size() == 1, "falha por %s emitida" % name)
		check(not Voyage.active, "viagem parou por %s" % name)
	GameState.reset()


func _test_reactor_heat_never_cools() -> void:
	section("falha do reator nao esfria o nucleo")
	GameState.reset()
	Voyage.start("Lua")
	GameState.heat = 99.0
	Voyage.force_event("reactor")
	check(GameState.heat >= 99.0, "calor %.1f >= 99" % GameState.heat)
	GameState.heat = 40.0
	Voyage.event = ""
	Voyage.force_event("reactor")
	check(is_equal_approx(GameState.heat, 65.0), "calor sobe 25 (%.1f)" % GameState.heat)
	GameState.reset()


# ---------------------------------------------------------------- CME
func _test_solar_flow() -> void:
	section("missao 3 (CME): decisoes e resultado")
	for send_alert in [true, false]:
		GameState.reset()
		GameState.running = false
		Missions.start("cme")
		check(Missions.is_step("solar"), "comeca no terminal solar")
		Solar.decide(send_alert)
		if send_alert:
			check(Solar.alert_sent and Missions.is_step("escudos"), "alerta enviado, falta ativar escudos")
			Solar.activate_shield()
			Solar._process(Solar.CME_COUNTDOWN + 1.0)
		check(Solar.resolved, "tempestade resolvida (alerta=%s)" % send_alert)
		check(Missions.finished.has("cme"), "missao CME concluida (alerta=%s)" % send_alert)
		check(Solar.last_result != "", "resultado explicado")
	GameState.reset()


# ---------------------------------------------------------------- idioma
func _test_translations() -> void:
	section("textos dinamicos tem traducao em ingles")
	Lang.set_language("en")
	var dynamic: Array = []
	for id in Missions.DEFS:
		dynamic.append(Missions.DEFS[id]["title"])
		for s in Missions.DEFS[id]["steps"]:
			dynamic.append(s["text"])
			dynamic.append(s["side"])
	dynamic.append_array(Missions.COLORS_OK)
	dynamic.append_array(Missions.COLORS_FAIL)
	dynamic.append_array(Missions.EVENTS)
	dynamic.append_array(Voyage.KIND_NAMES.values())
	dynamic.append_array(Voyage.ROUTES.keys())
	dynamic.append_array(Voyage.POS_NAMES)
	dynamic.append_array(Interactions.ROUTES)
	for id in GameState.ITEMS:
		dynamic.append(GameState.ITEMS[id]["name"])
	var missing: Array = []
	for t in dynamic:
		if tr(t) == t and t.length() > 3:   # nomes curtos iguais nas duas linguas (N, L, S) ficam de fora
			missing.append(t)
	check(missing.is_empty(), "sem traducao: %s" % [missing])
	Lang.set_language("pt")


# ---------------------------------------------------------------- arquivos
func _test_assets_referenced_exist() -> void:
	section("videos e musicas usados pelo codigo existem")
	for path in [Interactions.PLANET_TRANSITION, "res://assets/videos/spaceshiplaunch.ogv"]:
		check(ResourceLoader.exists(path), "video existe: " + path)
		check(load(path) is VideoStream, "video carrega: " + path)
	for room in Audio.ROOM_MUSIC:
		# salas sem arquivo ficam em silencio de proposito (ver audio.gd); so conferimos o que existe
		if ResourceLoader.exists(Audio.ROOM_MUSIC[room]):
			check(load(Audio.ROOM_MUSIC[room]) is AudioStreamMP3, "musica carrega: " + room)
	for sfx in Audio.SFX:
		check(ResourceLoader.exists(Audio.SFX[sfx]), "efeito existe: " + sfx)


# ---------------------------------------------------------------- salas, objetos e minigames
func _test_every_interaction_and_minigame() -> void:
	section("cada sala, cada objeto interativo e cada minigame abre e fecha sem travar")
	GameState.reset()
	GameState.running = false
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	await get_tree().create_timer(0.7).timeout   # espera o fade e o menu do tutorial abrirem
	UI.dismiss_all()   # fecha o tutorial
	await get_tree().create_timer(0.1).timeout
	var rooms: Array = []
	for f in DirAccess.get_files_at("res://scenes/rooms"):
		if f.ends_with(".tscn"):
			rooms.append("res://scenes/rooms/" + f)
	check(rooms.size() >= 7, "salas encontradas (%d)" % rooms.size())
	var actions := 0
	for path in rooms:
		game._load_room(path, "")
		await get_tree().process_frame
		var room: Node = game._room
		check(room != null and room.room_id() == path.get_file().get_basename(), "sala carregada: " + path.get_file())
		for it in room.find_children("*", "Area2D", true, false):
			if it.get("action") == null or String(it.action) == "":
				continue
			actions += 1
			Interactions.run(it.action, it, game.player)   # coroutine: fica esperando o jogador
			await get_tree().process_frame
			await get_tree().process_frame
			UI.dismiss_all()
			await get_tree().create_timer(0.05).timeout
			check(not UI.busy, "%s/%s fecha sem deixar a UI travada (locks=%d)" % [path.get_file(), it.action, UI._locks])
			UI.reset()
			game.player.stand(game.player.global_position)
	check(actions >= 10, "objetos interativos testados: %d" % actions)
	# minigames
	var opens := {
		"petri": func(): return UI.open_petri(),
		"mochila": func(): return UI.open_grid("inventory"),
		"armario": func(): return UI.open_grid("storage"),
	}
	for name in opens:
		var g: Control = opens[name].call()
		await get_tree().create_timer(0.3).timeout
		check(is_instance_valid(g) and g.is_inside_tree(), "minigame " + name + " abriu")
		UI.dismiss_all()
		await get_tree().process_frame
		g.queue_free()
		await get_tree().process_frame
	# troca estacao <-> Terra
	game.toggle_world()
	await get_tree().create_timer(1.0).timeout
	check(game._on_earth, "foi para a Terra")
	game.toggle_world()
	await get_tree().create_timer(1.0).timeout
	check(not game._on_earth, "voltou para a estacao")
	game.queue_free()
	await get_tree().process_frame
	UI.reset()


# ---------------------------------------------------------------- game over de verdade
func _press(action: String) -> void:
	for pressed in [true, false]:
		var e := InputEventAction.new()
		e.action = action
		e.pressed = pressed
		Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _test_game_over_flow_in_game_scene() -> void:
	section("game over com menu aberto: sem travar e reiniciando limpo")
	GameState.reset()
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(game)
	get_tree().current_scene = game   # o reinicio troca ESTA cena, nao o runner dos testes
	await get_tree().create_timer(0.6).timeout
	check(GameState.running, "partida em andamento")
	check(UI._menu_active, "menu do tutorial aberto (sera interrompido pela falha)")
	GameState.failed.emit("Teste: falha com menu aberto.")
	await get_tree().create_timer(0.3).timeout
	check(not GameState.running, "relogio parado")
	await get_tree().create_timer(1.2).timeout   # fade
	check(UI._dialog_active, "dialogo do game over aberto")
	for k in 8:   # avanca as falas: um F completa o texto, outro passa para a proxima
		if UI._menu_active:
			break
		await _press("interact")
	check(UI._menu_active, "menu Recomecar/Menu inicial apareceu")
	GameState.exploded.emit()   # outro game over ao mesmo tempo deve ser ignorado
	await get_tree().process_frame
	check(UI._menu_active, "segundo game over nao reabriu nada")
	await _press("interact")   # escolhe "Recomecar"
	await get_tree().create_timer(1.0).timeout
	var cur := get_tree().current_scene
	check(cur != null and cur != game and cur.scene_file_path == "res://scenes/game.tscn", "cena do jogo recarregada")
	check(not UI.busy or UI._menu_active, "sem trava de UI vazada (locks=%d)" % UI._locks)
	check(not UI.realtime, "tempo normal")
	check(GameState.health == 100.0 and GameState.food > 95.0, "necessidades restauradas")
	check(GameState.running, "nova partida em andamento")
