extends Node
## Comportamento de cada objeto interativo (autoload "Interactions").
## Cada Interativo nas salas tem um "action"; run() executa a acao correspondente.
## Tudo aqui e PLACEHOLDER de jogabilidade: valores e textos ficam faceis de trocar.



func run(action: String, source: Node, player: Node) -> void:
	match action:
		"fridge":
			await _cafeteria_item(source, "refri", "Geladeira", "Beber agora")
		"coffee":
			await _cafeteria_item(source, "cafe", "Máquina de café", "Tomar agora")
		"croquete":
			await _cafeteria_item(source, "croquete", "Vitrine de croquetes", "Comer agora")
		"bunk":
			await _bunk()
		"terminal_saida":
			await _terminal_saida()
		"impressora":
			await _impressora()
		"armario":
			await _armario()
		"capsula":
			await _capsula()
		"nucleo":
			await _nucleo()
		"botiquim":
			await _botiquim()
		"propulsor":
			await UI.say(["Painel do propulsor.", "A escolha do lançador e da órbita é feita no console da sala de controle."])
		"assento":
			await _assento(source, player)
		_:
			push_warning("Acao de interacao desconhecida: " + action)


# ============================ tutorial ============================
func show_tutorial() -> void:
	await UI.say([
		"Use W A S D (ou as setas) para andar.",
		"Perto de um objeto interativo aparece [F]. Aperte F (ou Enter) para usar.",
		"Aperte I (ou Tab) para abrir a mochila. Esc cancela os menus.",
		"Sente na sala de controle para projetar a missão: objetivo, instrumentos, energia, lançador, órbita e solo.",
		"Aperte 1 para trocar entre o astronauta (estação) e o cientista (Terra).",
		"Fique de olho nas barras de comida, sono e água lá embaixo!",
	])


# ============================ inventario ============================
func open_inventory() -> void:
	while true:
		var ids := GameState.unique_ids(GameState.inventory)
		if ids.is_empty():
			await UI.say("A mochila está vazia. (%d espaços)" % GameState.INVENTORY_SLOTS)
			return
		var opts: Array = []
		for id in ids:
			opts.append("%s x%d" % [GameState.item_name(id), GameState.count_of(GameState.inventory, id)])
		opts.append("Fechar")
		var i := await UI.choose(opts, "Mochila %d/%d" % [GameState.inventory.size(), GameState.INVENTORY_SLOTS])
		if i < 0 or i >= ids.size():
			return
		var chosen := ids[i]
		var a := await UI.choose(["Usar", "Voltar"], GameState.item_name(chosen))
		if a == 0:
			await _consume(chosen)


func _consume(id: String) -> void:
	if GameState.remove_item(id):
		GameState.use_item(id)
		await UI.say("Você usou %s. %s" % [GameState.item_name(id), _effects_text(GameState.ITEMS[id]["effects"])])


func _effects_text(effects: Dictionary) -> String:
	var names := {"food": "Comida", "thirst": "Água", "sleep": "Sono", "health": "Vida"}
	var parts: Array[String] = []
	for k in effects:
		parts.append("%s %+d" % [names.get(k, k), int(effects[k])])
	return ", ".join(parts) + "."


# ============================ cafeteria ============================
func _cafeteria_item(_source: Node, id: String, title: String, now_label: String) -> void:
	var label := GameState.item_name(id)
	var i := await UI.choose([now_label, "Guardar na mochila", "Cancelar"], title)
	if i == 0:
		GameState.use_item(id)
		await UI.say("%s! %s" % [label, _effects_text(GameState.ITEMS[id]["effects"])])
	elif i == 1:
		if GameState.add_item(id):
			await UI.say("%s guardado na mochila." % label)
		else:
			await UI.say("A mochila está cheia! (%d espaços)" % GameState.INVENTORY_SLOTS)


# ============================ dormitorio ============================
func _bunk() -> void:
	var i := await UI.choose(["Dormir", "Cancelar"], "Beliche (2 vagas)")
	if i != 0:
		return
	UI.lock()  # mantem o tempo parado durante o fade
	await UI.blink(1.2, 0.8)
	UI.unlock()
	GameState.apply_effects({"sleep": 100.0, "food": -10.0, "thirst": -10.0})
	await UI.say(["Você dormiu um pouco.", "Sono restaurado, mas deu fome e sede. (Sistema com %d camas: em breve)" % GameState.BEDS])


# ============================ armazem ============================
func _impressora() -> void:
	var i := await UI.choose(["Produzir ração", "Fechar"], "Impressora de comida")
	if i != 0:
		return
	if GameState.output_rations >= 5:
		await UI.say("A saída já está cheia (5 rações). Retire no terminal ao lado esquerdo.")
		return
	UI.toast("Produzindo ração...", GameState.PRODUCE_TIME)
	await get_tree().create_timer(GameState.PRODUCE_TIME).timeout
	GameState.output_rations += 1
	GameState.inventory_changed.emit()
	await UI.say(["Ração pronta!", "Ela saiu no terminal grande da esquerda."])


func _terminal_saida() -> void:
	var n := GameState.output_rations
	if n <= 0:
		await UI.say("Nenhuma ração pronta. Produza uma na impressora de comida (máquina da direita).")
		return
	var i := await UI.choose(["Retirar ração (%d)" % n, "Fechar"], "Terminal de saída")
	if i != 0:
		return
	if not GameState.inventory_has_room():
		await UI.say("A mochila está cheia! (%d espaços)" % GameState.INVENTORY_SLOTS)
		return
	GameState.output_rations -= 1
	GameState.add_item("racao")
	await UI.say("Você pegou 1 ração.")


func _armario() -> void:
	while true:
		var title := "Armário %d/%d" % [GameState.storage.size(), GameState.STORAGE_SLOTS]
		var i := await UI.choose(["Guardar item", "Retirar item", "Ver conteúdo", "Fechar"], title)
		if i < 0 or i == 3:
			return
		if i == 0:
			await _armario_guardar()
		elif i == 1:
			await _armario_retirar()
		else:
			await _armario_ver()


func _armario_guardar() -> void:
	if not GameState.storage_has_room():
		await UI.say("O armário está cheio! (%d espaços)" % GameState.STORAGE_SLOTS)
		return
	var ids := GameState.unique_ids(GameState.inventory)
	if ids.is_empty():
		await UI.say("Você não tem nada na mochila para guardar.")
		return
	var opts: Array = []
	for id in ids:
		opts.append(GameState.item_name(id))
	opts.append("Voltar")
	var i := await UI.choose(opts, "Guardar qual item?")
	if i >= 0 and i < ids.size() and GameState.store_item(ids[i]):
		await UI.say("%s guardado no armário." % GameState.item_name(ids[i]))


func _armario_retirar() -> void:
	var ids := GameState.unique_ids(GameState.storage)
	if ids.is_empty():
		await UI.say("O armário está vazio.")
		return
	var opts: Array = []
	for id in ids:
		opts.append("%s x%d" % [GameState.item_name(id), GameState.count_of(GameState.storage, id)])
	opts.append("Voltar")
	var i := await UI.choose(opts, "Retirar qual item?")
	if i < 0 or i >= ids.size():
		return
	if GameState.take_from_storage(ids[i]):
		await UI.say("Você pegou %s." % GameState.item_name(ids[i]))
	else:
		await UI.say("A mochila está cheia! (%d espaços)" % GameState.INVENTORY_SLOTS)


func _armario_ver() -> void:
	if GameState.storage.is_empty():
		await UI.say("Armário vazio (0/%d espaços usados)." % GameState.STORAGE_SLOTS)
		return
	var parts: Array[String] = []
	for id in GameState.unique_ids(GameState.storage):
		parts.append("%s x%d" % [GameState.item_name(id), GameState.count_of(GameState.storage, id)])
	await UI.say("%d/%d espaços usados: %s" % [GameState.storage.size(), GameState.STORAGE_SLOTS, ", ".join(parts)])


func _capsula() -> void:
	if GameState.capsule_item != "":
		await UI.say("A cápsula está a caminho da Terra com %s. Volta em %d s." % [GameState.item_name(GameState.capsule_item), ceili(GameState.capsule_left)])
		return
	if GameState.capsule_ready != "":
		if GameState.collect_capsule():
			await UI.say("Você pegou o item que voltou da Terra.")
		else:
			await UI.say("Há um item esperando na cápsula, mas sua mochila está cheia!")
		return
	var ids := GameState.unique_ids(GameState.inventory)
	if ids.is_empty():
		await UI.say("Cápsula para a Terra. Leve um item da mochila para enviar.")
		return
	var opts: Array = []
	for id in ids:
		opts.append(GameState.item_name(id))
	opts.append("Cancelar")
	var i := await UI.choose(opts, "Enviar para a Terra")
	if i >= 0 and i < ids.size() and GameState.send_to_earth(ids[i]):
		await UI.say("%s enviado! Ele volta em %d segundos." % [GameState.item_name(ids[i]), int(GameState.CAPSULE_TIME)])


# ============================ sala do reator ============================
func _nucleo() -> void:
	while true:
		var title := "Núcleo %d%%" % int(round(GameState.heat))
		var i := await UI.choose(["Resfriar núcleo", "Ver temperatura", "Fechar"], title)
		if i == 0:
			GameState.cool_core(50.0)
			await UI.say("Sistema de resfriamento ativado. Núcleo em %d%%." % int(round(GameState.heat)))
		elif i == 1:
			var state := "estável"
			if GameState.heat >= GameState.HEAT_WARNING:
				state = "PERIGOSO"
			elif GameState.heat >= 60.0:
				state = "quente"
			await UI.say("Temperatura do núcleo: %d%% (%s)." % [int(round(GameState.heat)), state])
		else:
			return


func _botiquim() -> void:
	var i := await UI.choose(["Curar-se", "Fechar"], "Kit médico")
	if i != 0:
		return
	if GameState.health >= 100.0:
		await UI.say("Você já está com a vida cheia.")
		return
	GameState.heal(50.0)
	await UI.say("Você se curou. Vida: %d." % int(round(GameState.health)))


# ============================ sala de controle ============================
func _assento(source: Node, player: Node) -> void:
	var seat := source.get_node_or_null("Assento") as Marker2D
	if seat == null or not player.has_method("sit"):
		return
	var stand_pos: Vector2 = player.global_position
	player.sit(seat.global_position)
	await _mission_console()
	player.stand(stand_pos)


func _name_of(table: Dictionary, id: String) -> String:
	return table[id]["name"] if id != "" else "—"


func _mission_console() -> void:
	while true:
		var opts: Array = [
			"Dificuldade: " + Mission.DIFFICULTY_NAMES[Mission.difficulty],
			"1 Objetivo: " + _name_of(Mission.OBJECTIVES, Mission.objective),
			"2 Instrumentos (%d)" % Mission.instruments.size(),
			"3 Energia: " + _name_of(Mission.ARRAYS, Mission.array_id),
			"4 Lançador: " + _name_of(Mission.LAUNCHERS, Mission.launcher),
			"5 Órbita: " + _name_of(Mission.ORBITS, Mission.orbit),
			"6 Solo: " + _name_of(Mission.STATIONS, Mission.station),
			"Revisar projeto",
			"LANÇAR MISSÃO",
			"Levantar",
		]
		var i := await UI.choose(opts, "Console de missão")
		match i:
			0:
				var keys := Mission.BUDGETS.keys()
				Mission.difficulty = keys[(keys.find(Mission.difficulty) + 1) % keys.size()]
				await UI.say("Orçamento: %d M$." % int(Mission.budget()))
			1:
				await _pick("Objetivo científico", Mission.OBJECTIVES, "objective", _obj_label)
			2:
				await _pick_instruments()
			3:
				await _pick("Energia", Mission.ARRAYS, "array_id", _array_label)
			4:
				await _pick("Lançador", Mission.LAUNCHERS, "launcher", _launcher_label)
			5:
				await _pick("Órbita", Mission.ORBITS, "orbit", _orbit_label)
			6:
				await _pick("Estação terrestre", Mission.STATIONS, "station", _station_label)
			7:
				await UI.say(Mission.review_lines())
			8:
				var r := Mission.launch()
				await UI.say(r["lines"])
			_:
				return


func _pick(title: String, table: Dictionary, field: String, label: Callable) -> void:
	var ids := table.keys()
	var opts: Array = []
	for id in ids:
		opts.append(label.call(id))
	opts.append("Voltar")
	var i := await UI.choose(opts, title)
	if i >= 0 and i < ids.size():
		Mission.set(field, ids[i])


func _pick_instruments() -> void:
	while true:
		var ids := Mission.INSTRUMENTS.keys()
		var opts: Array = []
		for id in ids:
			var ins: Dictionary = Mission.INSTRUMENTS[id]
			var mark := "[x] " if Mission.instruments.has(id) else "[ ] "
			opts.append("%s%s %dkg %dW %.0fd %dM$" % [mark, ins["name"], int(ins["mass"]), int(ins["power"]), ins["data"], int(ins["cost"])])
		opts.append("Concluir")
		var i := await UI.choose(opts, "Instrumentos %d/%d" % [Mission.instruments.size(), Mission.MAX_INSTRUMENTS])
		if i < 0 or i >= ids.size():
			return
		if not Mission.toggle_instrument(ids[i]):
			await UI.say("Máximo de %d instrumentos." % Mission.MAX_INSTRUMENTS)


func _obj_label(id: String) -> String:
	var o: Dictionary = Mission.OBJECTIVES[id]
	return "%s: %.0f dados/dia, %d meses" % [o["name"], o["min_data"], o["months"]]


func _array_label(id: String) -> String:
	var a: Dictionary = Mission.ARRAYS[id]
	return "%s %dW %dkg %dM$" % [a["name"], int(a["watts"]), int(a["mass"]), int(a["cost"])]


func _launcher_label(id: String) -> String:
	var l: Dictionary = Mission.LAUNCHERS[id]
	var c: Dictionary = l["cap"]
	return "%s %dM$ (LEO %d, GEO %d, L1 %d kg)" % [l["name"], int(l["cost"]), int(c["leo"]), int(c["geo"]), int(c["l1"])]


func _orbit_label(id: String) -> String:
	var o: Dictionary = Mission.ORBITS[id]
	return "%s: eclipse %d%%, link %.1f" % [o["name"], int(float(o["eclipse"]) * 100.0), o["link"]]


func _station_label(id: String) -> String:
	var s: Dictionary = Mission.STATIONS[id]
	return "%s %.0f dados/dia %dM$" % [s["name"], s["rate"], int(s["cost"])]
