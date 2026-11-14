extends Node
## Comportamento de cada objeto interativo (autoload "Interactions").
## Cada Interativo nas salas tem um "action"; run() executa a acao correspondente.
## Tudo aqui e PLACEHOLDER de jogabilidade: valores e textos ficam faceis de trocar.

const ROUTES := ["Lua", "Marte", "Júpiter"]  # rotas de exemplo (sala de controle)
const PLANET_TRANSITION := "res://assets/Viideos/trasiicao.ogv"  # cutscene de troca de planeta


func run(action: String, source: Node, player: Node) -> void:
	match action:
		"fridge":
			await _cafeteria_item(source, "refri", "Geladeira", "Beber agora")
		"coffee":
			await _cafeteria_item(source, "cafe", "Máquina de café", "Tomar agora")
		"bolacha":
			await _cafeteria_item(source, "bolacha", "Vitrine de bolachas", "Comer agora")
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
		"escudos":
			await _escudos()
		"propulsor":
			await UI.say(["Painel do propulsor.", "Todos os sistemas estáveis. (Controle do propulsor em desenvolvimento.)"])
		"assento":
			await _assento(source, player)
		"checkup":
			await _checkup()
		"mission_pacotes":
			await _estante_culturas()
		"aquecedor":
			await _aquecedor()
		"centrifuga":
			await _centrifuga()
		"painel_base":
			await _painel_base()
		_:
			push_warning("Acao de interacao desconhecida: " + action)


# ============================ tutorial ============================
func show_tutorial() -> void:
	var skip := await UI.choose(["Ver tutorial", "Pular tutorial"], "Tutorial")
	if skip != 0:
		return
	await UI.say([
		"Use W A S D (ou as setas) para andar.",
		"Perto de um objeto interativo aparece [F]. Aperte F (ou Enter) para usar.",
		"Aperte I (ou Tab) para abrir a mochila. Esc cancela os menus.",
		"Aperte 1 para trocar entre o astronauta (estação) e o cientista (Terra).",
		"Aperte M (ou J) para ver as missões. O objetivo atual aparece no canto da tela por um tempo; depois fica só um \"!\" (clique nele ou aperte V para ver de novo).",
		"Fique de olho nas barras de comida, sono e água lá embaixo!",
	])


# ============================ inventario ============================
func open_inventory() -> void:
	var g = UI.open_grid("inventory")
	g.desc_provider = _inventory_text
	while true:
		g.set_items(GameState.inventory)
		var i: int = await g.picked
		if i < 0:
			break
		if i >= GameState.inventory.size():
			continue
		var chosen: String = GameState.inventory[i]
		var a := await UI.choose(["Usar", "Voltar"], GameState.item_name(chosen))
		if a == 0:
			await _consume(chosen)
	g.queue_free()


func _inventory_text(_i: int, id: String) -> String:
	var head := "Mochila %d/%d" % [GameState.inventory.size(), GameState.INVENTORY_SLOTS]
	if id == "":
		return head + "
Espaço vazio.   Esc: fechar"
	return "%s: %s
%s   F: usar   Esc: fechar" % [head, GameState.item_name(id), _effects_text(GameState.ITEMS[id]["effects"])]


func _consume(id: String) -> void:
	if id == "amostra":
		await _comer_amostra()
		return
	if GameState.ITEMS[id]["effects"].is_empty():
		await UI.say("%s não pode ser usado assim." % GameState.item_name(id))
		return
	if GameState.remove_item(id):
		GameState.use_item(id)
		await UI.say("Você usou %s. %s" % [GameState.item_name(id), _effects_text(GameState.ITEMS[id]["effects"])])


# Comer a amostra: se estiver estragada (mesmo que a base tenha dito sucesso) tira 50% da vida atual.
func _comer_amostra() -> void:
	if Missions.is_step("enviar"):
		await UI.say("Você precisa enviar esta amostra à base antes. Não dá para comê-la agora.")
		return
	if not GameState.remove_item("amostra"):
		return
	await UI.say(Missions.eat_sample())


func _effects_text(effects: Dictionary) -> String:
	if effects.is_empty():
		return "Sem efeito."
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
	var g = UI.open_grid("storage")
	g.desc_provider = _storage_text
	while true:
		g.set_items(GameState.storage)
		var i: int = await g.picked
		if i < 0:
			break
		if i < GameState.storage.size():
			var id: String = GameState.storage[i]
			var a := await UI.choose(["Retirar para a mochila", "Voltar"], GameState.item_name(id))
			if a == 0 and not GameState.take_storage_at(i):
				await UI.say("A mochila está cheia! (%d espaços)" % GameState.INVENTORY_SLOTS)
		else:
			await _armario_guardar()
	g.queue_free()


func _storage_text(_i: int, id: String) -> String:
	var head := "Armário %d/%d" % [GameState.storage.size(), GameState.STORAGE_SLOTS]
	if id == "":
		return head + "
Espaço vazio.   F: guardar um item da mochila   Esc: fechar"
	return "%s: %s
%s   F: retirar   Esc: fechar" % [head, GameState.item_name(id), _effects_text(GameState.ITEMS[id]["effects"])]


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


func _capsula() -> void:
	# A cápsula tem 1 ESPAÇO: ou leva um item para a Terra, ou traz um item de volta.
	while true:
		var title := "Cápsula (1 espaço)"
		var i := await UI.choose(["Enviar item", "Retirar item", "Fechar"], title)
		if i == 0:
			if not await _capsula_enviar():
				continue
			return
		elif i == 1:
			if await _capsula_retirar():
				return
		else:
			return


func _capsula_ocupada() -> bool:
	if GameState.capsule_item != "":
		if GameState.capsule_hold:
			await UI.say(["%s está na Terra, esperando o veredito da base." % GameState.item_name(GameState.capsule_item), "Aperte 1 para ver a base (cientista)."])
		else:
			await UI.say("A cápsula está a caminho da Terra com: %s. Chega em %d s." % [GameState.item_name(GameState.capsule_item), ceili(GameState.capsule_left)])
		return true
	if GameState.capsule_ready != "":
		await UI.say("O espaço da cápsula está ocupado por: %s. Retire primeiro." % GameState.item_name(GameState.capsule_ready))
		return true
	return false


## true = acabou (enviou); false = volta ao menu
func _capsula_enviar() -> bool:
	if not Voyage.comms_ok():
		await UI.say("Sem contato com a base: a cápsula está bloqueada pela interferência.")
		return false
	if await _capsula_ocupada():
		return false
	var ids := GameState.unique_ids(GameState.inventory)
	if ids.is_empty():
		await UI.say("Você não tem nada na mochila para enviar.")
		return false
	var opts: Array = []
	for id in ids:
		opts.append(GameState.item_name(id))
	opts.append("Voltar")
	var i := await UI.choose(opts, "Enviar para a Terra")
	if i < 0 or i >= ids.size():
		return false
	var chosen: String = ids[i]
	if chosen == "amostra":
		# amostra da missao: a BASE analisa; ela fica na Terra ate o veredito
		if not Missions.is_step("enviar"):
			await UI.say("Esta amostra ainda não está pronta para ser enviada.")
			return false
		if GameState.send_to_earth(chosen, true):
			Missions.send_data()
			await UI.say(["Amostra enviada à Terra.", "A base vai analisar e dar o veredito; só então ela volta. Aperte 1 para ir à base."])
			return true
		return false
	if GameState.send_to_earth(chosen):
		await UI.say("Enviado à Terra: %s. Chega de volta em %d segundos." % [GameState.item_name(chosen), int(GameState.CAPSULE_TIME)])
		return true
	return false


## true = retirou (fecha o menu); false = volta ao menu
func _capsula_retirar() -> bool:
	if GameState.capsule_ready == "":
		if GameState.capsule_item != "":
			await _capsula_ocupada()
		else:
			await UI.say("Não há nada na cápsula para retirar.")
		return false
	var id: String = GameState.capsule_ready
	if not GameState.collect_capsule():
		await UI.say("Sua mochila está cheia! (%d espaços)" % GameState.INVENTORY_SLOTS)
		return false
	if id == "amostra" and not Missions.result_lines.is_empty():
		await UI.say("Você retirou: %s." % GameState.item_name(id))
		await UI.say(Missions.take_result())
	else:
		await UI.say("Você retirou: %s." % GameState.item_name(id))
	return true


# ============================ sala do reator ============================
func _nucleo() -> void:
	while true:
		var title := "Núcleo %d%%" % int(round(GameState.heat))
		if GameState.meltdown_left >= 0.0:
			title += "  EXPLODE EM %d s" % ceili(GameState.meltdown_left)
		var opts: Array = ["Resfriar núcleo", "Ver temperatura", "Fechar"]
		if Voyage.event == "reactor":
			opts.insert(2, "Ajustar válvulas (URGENTE)")
		var i := await UI.choose(opts, title)
		if opts[maxi(i, 0)] == "Ajustar válvulas (URGENTE)" and i >= 0:
			await _valvulas()
		elif i == 0:
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
	while true:
		var title := ""
		var opts: Array = []
		var acts: Array = []
		if Voyage.active:
			title = "Viagem: %s" % Voyage.route
			opts.append("Mapa espacial")
			acts.append("mapa")
			if Voyage.maneuver_available():
				opts.append("Manobra evasiva")
				acts.append("manobra")
		elif Missions.is_step("rota"):
			title = "Escolha a rota"
			for r in ROUTES:
				opts.append("Iniciar viagem: " + r)
				acts.append("rota:" + r)
		else:
			title = "Rota: " + (GameState.route if GameState.route != "" else "nenhuma")
			for r in ROUTES:
				opts.append("Ir para " + r)
				acts.append("define:" + r)
		opts.append("Levantar")
		acts.append("levantar")
		var i := await UI.choose(opts, title)
		if i < 0 or acts[i] == "levantar":
			break
		var a: String = acts[i]
		if a == "mapa":
			await UI.say(Voyage.map_text())
		elif a == "manobra":
			await UI.say(Voyage.maneuver())
		elif a.begins_with("rota:"):
			var r := a.substr(5)
			var c := await UI.choose(["Confirmar viagem para %s" % r, "Voltar"], "Rota: " + r)
			if c == 0:
				Voyage.start(r)
				Missions.complete("rota")
				await planet_transition()
				await UI.say(["Viagem iniciada: %s." % r, "A base prevê os perigos; a nave faz as manobras. Cuide da energia e do combustível!"])
				break
		else:
			var r2 := a.substr(7)
			GameState.route = r2
			await UI.say(["Próxima rota definida: %s." % r2, "(A viagem começa na missão de viagem.)"])
	player.stand(stand_pos)



# ============================ missoes ============================
func open_missions() -> void:
	await UI.show_panel(Missions.summary_text())


# Missao 1 (espaco): pegar pacotes -> aquecer -> centrifugar -> enviar pela capsula (a base analisa).
# As estacoes usam objetos que ja existem nas salas (placeholders ate chegarem as imagens finais).
func _estante_culturas() -> void:
	if not Missions.is_step("pacotes"):
		await UI.say("Estante com pacotes de culturas e materiais diversos.")
		return
	var i := await UI.choose(["Pegar pacote de cultura de fungos", "Cancelar"], "Estante de culturas")
	if i != 0:
		return
	if not GameState.add_item("pacote_fungos"):
		await UI.say("A mochila está cheia! (%d espaços)" % GameState.INVENTORY_SLOTS)
		return
	Missions.complete("pacotes")
	await UI.say(["Você pegou um pacote com a cultura de fungos.", "Leve-o à máquina de aquecimento (os containers azuis, no canto direito)."])


func _aquecedor() -> void:
	match Missions.heater_state:
		"heating":
			await UI.say("Aquecendo os pacotes... faltam %d s." % ceili(Missions.heating_left))
		"ready":
			if not GameState.add_item("pacote_quente"):
				await UI.say("A mochila está cheia! (%d espaços)" % GameState.INVENTORY_SLOTS)
				return
			Missions.heater_state = "idle"
			Missions.complete("aquecer")
			await UI.say(["Pacote aquecido!", "Agora leve para a centrífuga (sala de controle, máquinas do canto esquerdo)."])
		_:
			if Missions.is_step("aquecer") and GameState.inventory.has("pacote_fungos"):
				var i := await UI.choose(["Colocar pacote para aquecer", "Cancelar"], "Máquina de aquecimento")
				if i == 0 and GameState.remove_item("pacote_fungos"):
					Missions.heater_state = "heating"
					Missions.heating_left = Missions.HEAT_TIME
					Missions.changed.emit()
					await UI.say("Aquecendo... volte em %d segundos." % int(Missions.HEAT_TIME))
			else:
				await UI.say("Máquina de aquecimento. (Precisa de um pacote de cultura de fungos.)")


func _centrifuga() -> void:
	if Missions.is_step("centrifugar") and GameState.inventory.has("pacote_quente"):
		var i := await UI.choose(["Esvaziar e centrifugar", "Cancelar"], "Centrífuga")
		if i != 0:
			return
		UI.toast("Centrifugando...", Missions.SPIN_TIME)
		await get_tree().create_timer(Missions.SPIN_TIME).timeout
		GameState.remove_item("pacote_quente")
		GameState.add_item("amostra")
		Missions.complete("centrifugar")
		await UI.say(["Amostra centrifugada!", "Envie-a à base pela cápsula do armazém (cilindro do canto direito)."])
	else:
		await UI.say("Centrífuga. (Precisa de um pacote aquecido.)")


# Missao 1 (Terra): a base conhece as coloracoes e decide sucesso ou falha.
func _painel_base() -> void:
	var table := "Colorações de SUCESSO: %s.   Colorações de FALHA: %s." % [", ".join(Missions.COLORS_OK), ", ".join(Missions.COLORS_FAIL)]
	if not Voyage.comms_ok():
		await UI.say(["SEM CONTATO com a nave (%d s)." % ceili(Voyage.blackout_left), "Painel da base indisponível durante a interferência."])
		return
	if not Missions.is_step("veredito") and (Voyage.active or Missions.is_step("solar")):
		await _base_viagem()
		return
	if not Missions.is_step("veredito"):
		if Missions.data_sent or not Missions.finished.is_empty():
			await UI.say(["Painel da base.", table])
		else:
			await UI.say(["Painel da base.", table, "Aguardando a amostra da nave."])
		return
	if not Missions.analyzed:
		var a := await UI.choose(["Analisar amostra", "Cancelar"], "Amostra recebida da nave")
		if a != 0:
			return
		UI.toast("Analisando a amostra...", 1.6)
		await get_tree().create_timer(1.6).timeout
		var color := Missions.analyze_sample()
		await UI.say(["Análise concluída.", "Coloração observada: %s." % color.to_upper(), table])
	else:
		await UI.say(["Coloração observada: %s." % Missions.sample_color.to_upper(), table])
	var i := await UI.choose(["Indicar SUCESSO", "Indicar FALHA", "Cancelar"], "Veredito da base")
	if i == 0 or i == 1:
		await UI.say(Missions.verdict(i == 0))


# ============================ dormitorio: checkup ============================
func _checkup() -> void:
	var i := await UI.choose(["Fazer checkup", "Cancelar"], "Terminal médico")
	if i != 0:
		return
	UI.toast("Escaneando...", 1.6)
	await get_tree().create_timer(1.6).timeout
	var lines: Array = ["Checkup concluído."]
	lines.append("Vida %d%%   Comida %d%%   Água %d%%   Sono %d%%" % [
		int(round(GameState.health)), int(round(GameState.food)),
		int(round(GameState.thirst)), int(round(GameState.sleep))])
	var issues: Array[String] = []
	if GameState.health < 60.0:
		issues.append("ferido")
	if GameState.food < 40.0:
		issues.append("com fome")
	if GameState.thirst < 40.0:
		issues.append("com sede")
	if GameState.sleep < 40.0:
		issues.append("cansado")
	lines.append("Você está bem." if issues.is_empty() else "Atenção: você está " + ", ".join(issues) + ".")
	if GameState.conditions.is_empty():
		lines.append("Nenhuma doença ou anomalia detectada.")
	else:
		lines.append("Detectado: " + ", ".join(GameState.conditions) + ".")
	await UI.say(lines)


# ============================ Missao 2: base e reator ============================
func _base_viagem() -> void:
	while true:
		var opts: Array = []
		var acts: Array = []
		if Voyage.active:
			opts.append_array(["Monitor da nave", "Previsão de perigos", "Enviar alerta à nave"])
			acts.append_array(["monitor", "previsao", "alerta"])
		if Missions.is_step("solar"):
			opts.append("Terminal solar (CME)")
			acts.append("solar")
		opts.append("Fechar")
		acts.append("fechar")
		var i := await UI.choose(opts, "Painel da base")
		if i < 0 or acts[i] == "fechar":
			return
		match String(acts[i]):
			"monitor":
				await UI.show_panel(Voyage.monitor_text())
			"previsao":
				await UI.show_panel(Voyage.forecast_text())
			"alerta":
				await _enviar_alerta()
			"solar":
				await _terminal_solar()
				if not Missions.is_step("solar"):
					return


func _enviar_alerta() -> void:
	if Voyage.event == "asteroid":
		# minigame de calculo: tempo de impacto = distancia / velocidade
		var speed: float = Voyage.asteroid["speed"]
		var dist := int(speed * float(Voyage.asteroid["eta"]))
		await UI.say(["Objeto detectado: velocidade %.1f km/s, distância %d km." % [speed, dist], "Calcule: tempo = distância ÷ velocidade."])
		var vals: Array = Voyage.asteroid_choices()
		var labels: Array = []
		for v in vals:
			labels.append("Impacto em %d s" % int(v))
		var k := await UI.choose(labels, "Quando ele atinge a nave?")
		if k >= 0:
			Voyage.set_estimate(int(vals[k]))
	await UI.say(Voyage.send_alert())


# Valvulas do reator (astronauta): girar uma valvula gira tambem as vizinhas. O tempo corre durante o minigame.
func _valvulas() -> void:
	UI.realtime = true
	while Voyage.event == "reactor":
		var opts: Array = []
		for k in 5:
			opts.append("Girar válvula %d" % (k + 1))
		opts.append("Sair")
		var i := await UI.choose(opts, "%s   Eficiência %d%%" % [Voyage.valve_state_text(), int(Voyage.reactor_eff())])
		if i < 0 or i >= 5:
			break
		Voyage.press(i)
	UI.realtime = false


# Cutscene usada SEMPRE que a nave troca de planeta (saida para um novo destino).
func planet_transition() -> void:
	await UI.play_video(PLANET_TRANSITION)
	await UI.fade_to(0.0, 0.6)


# ============================ Missao 3: CME ============================
# Base: terminal solar em "tempo real" + manual; decide alertar ou ignorar.
func _terminal_solar() -> void:
	while true:
		await UI.show_panel("", Callable(Solar, "terminal_text"))
		var i := await UI.choose(["Enviar alerta de abrigo", "Ignorar (falso alarme)", "Ver o terminal de novo"], "Decisão da base")
		if i == 0 or i == 1:
			await UI.say(Solar.decide(i == 0))
			return
		if i < 0:
			return


# Astronauta: chave dos escudos no controle de energia (sala do reator, maquinas da esquerda).
func _escudos() -> void:
	if not Solar.alert_sent or Solar.resolved:
		await UI.say("Controle de energia e suporte de vida. Nenhum alerta solar ativo.")
		return
	if Solar.shield_on:
		await UI.say("Os escudos já estão ativos. Aguarde a onda passar.")
		return
	var i := await UI.choose(["Ativar escudos", "Cancelar"], "Controle de energia")
	if i == 0:
		Solar.activate_shield()
		await UI.say(["Escudos ativados!", "Energia redirecionada. Aguarde a onda passar."])
