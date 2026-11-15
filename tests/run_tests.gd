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
	MissionState.planning_disabled = true   # os testes de cena nao abrem o planejamento (CML)
	await _test_scenes_load()
	_test_restart_clears_state()
	_test_death_by_zero_health()
	await _test_dismiss_all_unblocks_menu()
	_test_mission1_flow()
	_test_voyage_arrival()
	_test_voyage_failures()
	_test_reactor_heat_never_cools()
	_test_solar_flow()
	_test_net_snapshot_roundtrip()
	_test_nasa_feed()
	await _test_planning_changes_voyage()
	_test_quick_plan_keeps_old_behavior()
	await _test_return_and_report()
	_test_net_snapshot_has_mission_state()
	await _test_net_client_is_mirror()
	await _test_net_client_game_scene()
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


# ---------------------------------------------------------------- planejamento, feed, retorno, relatorio
func _test_nasa_feed() -> void:
	section("feed NASA: arquivo local carrega e vira selo REAL")
	check(NasaFeed.events.size() > 0, "ha eventos no arquivo de fallback")
	var ev := NasaFeed.pick_flare()
	check(ev.get("tag", "") == MissionState.TAG_REAL, "evento do feed tem selo REAL")
	check(String(ev.get("label", "")).contains(String(ev.get("date", "?"))), "o selo mostra a data do registro")
	check(NasaFeed.flux_for("X9.3") >= Solar.HIT_FLUX, "erupcao X e perigosa no jogo")
	check(NasaFeed.flux_for("M5.0") < Solar.HIT_FLUX, "erupcao M nao passa do limite")
	check(NasaFeed._parse("lixo") == false and NasaFeed.events.size() > 0, "feed invalido e ignorado")
	Solar.generate()
	check(Solar.source_tag != "", "CME gerada tem selo de origem")
	GameState.reset()


func _plan(picks: Array) -> void:
	GameState.reset()
	GameState.running = false
	MissionState.auto_mode = true
	MissionState.auto_picks = picks.duplicate()
	await MissionState.run_planning()
	MissionState.auto_mode = false


func _test_planning_changes_voyage() -> void:
	section("planejamento CML 1-9 grava parametros que mudam a viagem")
	# 0 planejar | CML1 obj | CML2 foguete pequeno | CML3 energia, casco | CML4 kit | CML5 sem reserva | CML6 .. | CML7 nada (concluir)
	await _plan([0, 1, 0, 0, 0, 0, 2, 0, 1, 1, 1, 1, 1, 1, 1, 0])
	check(MissionState.planned and MissionState.cml_done == 9, "os 9 CMLs foram concluidos")
	check(MissionState.objective == "radiation", "objetivo do CML 1 gravado")
	check(MissionState.decisions.size() >= 9, "cada CML registrou decisao")
	check(MissionState.p("credits") >= 0.0, "creditos nunca ficam negativos")
	check(MissionState.p("mass_cap") == 105.0, "foguete pequeno do CML 2 vale no resto do jogo")
	check(not MissionState.accepted_risks.is_empty() or MissionState.mitigated.size() == 3, "riscos aceitos/mitigados definidos no CML 7")
	var mass_plan: float = MissionState.p("mass")
	var mult_plan: float = MissionState.p("energy_mult")
	Voyage.start("Lua")
	check(is_equal_approx(Voyage.mass, minf(mass_plan, 90.0) if Missions.flags.get("nave_leve", false) else mass_plan), "viagem usa a massa do projeto")
	check(is_equal_approx(Voyage.energy_mult, mult_plan), "viagem usa o consumo de energia do projeto")
	# riscos aceitos aumentam o peso do evento correspondente
	MissionState.accepted_risks = ["thermal"]
	check(MissionState.event_weights()["reactor"] > MissionState.event_weights()["comm"], "risco termico aceito deixa o reator mais provavel")
	check(MissionState.cause_for("reactor") != "", "o evento explica a causa (CML 7)")
	MissionState.accepted_risks = []
	check(MissionState.cause_for("reactor") == "", "sem risco aceito nao ha causa inventada")
	# peca reserva reduz o salto de temperatura do reator
	MissionState.params["parts"] = 1.0
	GameState.heat = 20.0
	Voyage.force_event("reactor")
	var with_part: float = GameState.heat
	check(MissionState.p("parts") == 0.0, "reparo gastou a peca reserva")
	GameState.reset()
	Voyage.start("Lua")
	GameState.heat = 20.0
	Voyage.force_event("reactor")
	check(with_part < GameState.heat, "com peca o salto de temperatura e menor")
	GameState.reset()
	# credito insuficiente: opcao cara e trocada por uma barata no modo automatico
	MissionState.params["credits"] = 3.0
	check(not MissionState._can_afford({"credits": -10.0}), "nao pode gastar o que nao tem")
	GameState.reset()


func _test_quick_plan_keeps_old_behavior() -> void:
	section("missao rapida = jogo antigo")
	GameState.reset()
	check(is_equal_approx(MissionState.event_chance(), 0.15), "chance de evento padrao 15%")
	check(is_equal_approx(MissionState.blackout_mult(), 1.0), "blecaute padrao")
	GameState.running = false
	Voyage.start("Marte")
	check(Voyage.mass == 100.0 and Voyage.fuel == 100.0 and is_equal_approx(Voyage.energy_mult, 1.0), "viagem sem planejamento = valores antigos")
	check(is_equal_approx(Voyage.time_left, Voyage.ROUTES["Marte"]["limit"]), "tempo antigo")
	GameState.reset()


func _test_return_and_report() -> void:
	section("retorno a Terra gera relatorio com selos e causas")
	await _plan([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	GameState.running = false
	Voyage.start("Lua")
	Voyage.force_event("reactor")
	Voyage._reactor_stable()
	Voyage.force_event("comm")
	Voyage.blackout_left = 0.0
	Missions.finished.assign(["bionutrientes", "viagem", "cme"])
	Missions.start("retorno")
	check(Missions.is_step("retorno"), "missao de retorno comeca")
	MissionState.auto_mode = true
	MissionState.auto_picks = [0, 1]
	await MissionState.run_return()
	MissionState.auto_mode = false
	check(Missions.finished.has("retorno"), "retorno concluido")
	check(not MissionState.report.is_empty(), "relatorio gerado")
	var text: String = MissionState.report["text"]
	check(text.contains("[FICT]") and text.contains("[RISCO]"), "eventos aparecem com selos")
	check(text.contains("CML 1:") and text.contains("CML 9:"), "relatorio lista as decisoes do planejamento")
	check(["A", "B", "C", "D", "E"].has(MissionState.report["grade"]), "ha uma nota")
	check(float(MissionState.report["score"]) >= 0.0 and float(MissionState.report["score"]) <= 100.0, "nota entre 0 e 100")
	check(FileAccess.file_exists("user://last_report.json"), "relatorio salvo em user://")
	GameState.reset()
	check(MissionState.report.is_empty() and not MissionState.planned, "reiniciar limpa o estado da missao")


func _test_net_snapshot_has_mission_state() -> void:
	section("multiplayer: MissionState entra no snapshot")
	GameState.reset()
	MissionState.params["credits"] = 77.0
	MissionState.objective = "bio"
	MissionState.log_event("reactor", MissionState.TAG_FICT, "x")
	var snap: Dictionary = Net.snapshot()
	check(snap.has("MissionState"), "snapshot inclui MissionState")
	MissionState.reset()
	Net.apply_snapshot(snap)
	check(MissionState.p("credits") == 77.0 and MissionState.objective == "bio" and MissionState.log.size() == 1, "espelho recebe o estado da missao")
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
	dynamic.append_array(MissionState.TAG_NAMES.values())
	for r in MissionState.RISKS.values():
		dynamic.append(r["name"])
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


# ---------------------------------------------------------------- multiplayer (LAN)
func _test_net_snapshot_roundtrip() -> void:
	section("multiplayer: snapshot do host recria o estado no espelho")
	GameState.reset()
	GameState.food = 42.0
	GameState.inventory.append("cafe")
	Missions.start("bionutrientes")
	Voyage.start("Lua")
	Solar.real = true
	var snap: Dictionary = Net.snapshot()
	GameState.reset()
	check(GameState.food == 100.0 and Missions.active == "" and not Voyage.active, "estado zerado antes de aplicar")
	var seen: Array = []
	var cb := func(): seen.append(1)
	Missions.changed.connect(cb)
	Net.apply_snapshot(snap)
	Missions.changed.disconnect(cb)
	check(GameState.food == 42.0, "comida espelhada")
	check(GameState.inventory == ["cafe"], "mochila espelhada")
	check(GameState.inventory.get_typed_builtin() == TYPE_STRING, "mochila continua Array[String]")
	check(Missions.active == "bionutrientes", "missao espelhada")
	check(Voyage.active and Voyage.route == "Lua", "viagem espelhada")
	check(Solar.real, "solar espelhado")
	check(seen.size() == 1, "Missions.changed emitido ao aplicar (veio %d)" % seen.size())
	# aplicar o mesmo snapshot de novo nao dispara avisos a toa
	seen.clear()
	Missions.changed.connect(cb)
	Net.apply_snapshot(snap)
	Missions.changed.disconnect(cb)
	check(seen.is_empty(), "snapshot igual nao emite changed")
	Net._last_snap = {}
	GameState.reset()


func _test_net_client_is_mirror() -> void:
	section("multiplayer: o cliente nao simula, so espelha; offline segue igual")
	GameState.reset()
	GameState.running = true
	GameState.food = 50.0
	Voyage.start("Lua")
	var t0: float = Voyage.time_left
	Net.mode = Net.Mode.CLIENT
	GameState._process(5.0)
	Voyage._process(5.0)
	Missions._process(5.0)
	var inverted_ok: bool = not Net.has_partner() or Net.is_client()
	Net.mode = Net.Mode.OFFLINE
	check(GameState.food == 50.0, "GameState do cliente nao desgasta necessidades")
	check(Voyage.time_left == t0, "Voyage do cliente nao corre")
	check(inverted_ok, "papeis coerentes")
	# offline: call_host executa direto e a base funciona como antes
	var c = await Missions.analyze_sample()
	check(c is String and c != "", "offline: analyze_sample direto")
	GameState.running = false
	GameState.reset()


func _test_net_client_game_scene() -> void:
	section("multiplayer: cliente entra na Terra como cientista; host fica na estacao")
	GameState.reset()
	Net.mode = Net.Mode.CLIENT
	var game := (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	check(game.player == game.scientist, "cliente controla o cientista")
	check(game._room != null and game._room.room_id() == "laboratorio", "cliente comeca no laboratorio")
	check(game._on_earth, "cliente marcado como na Terra")
	game.toggle_world()   # sem parceiro de verdade nao deve travar nem trocar
	game.queue_free()
	await get_tree().process_frame
	Net.mode = Net.Mode.OFFLINE
	GameState.running = false
	GameState.reset()
	var lobby := (load("res://scenes/lobby.tscn") as PackedScene).instantiate()
	add_child(lobby)
	await get_tree().process_frame
	check(lobby._state == lobby.S.MAIN and lobby._items.size() == 4, "lobby abre no menu principal")
	lobby.queue_free()
	await get_tree().process_frame
