extends Node
## Comportamento de cada objeto interativo (autoload "Interactions").
## Cada Interativo nas salas tem um "action"; run() executa a acao correspondente.
## Tudo aqui e PLACEHOLDER de jogabilidade: valores e textos ficam faceis de trocar.

const ROUTES := ["Lua", "Marte", "Júpiter"]  # rotas de exemplo (sala de controle)
const PLANET_TRANSITION := "res://assets/Viideos/trasiicao.ogv"  # cutscene de troca de planeta


func run(action: String, source: Node, player: Node) -> void:
	match action:
		"fridge":
			await _cafeteria_item(source, "refri", tr("Geladeira"), tr("Beber agora"))
		"coffee":
			await _cafeteria_item(source, "cafe", tr("Máquina de café"), tr("Tomar agora"))
		"bolacha":
			await _cafeteria_item(source, "bolacha", tr("Vitrine de bolachas"), tr("Comer agora"))
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
		"mesa_analise":
			await _mesa_analise()
		"mural_formulas":
			await _mural_formulas()
		"bancada_frascos":
			await _bancada_frascos()
		"propulsor":
			await UI.say([tr("Painel do propulsor."), tr("Todos os sistemas estáveis. (Controle do propulsor em desenvolvimento.)")])
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
	var skip := await UI.choose([tr("Ver tutorial"), tr("Pular tutorial")], tr("Tutorial"))
	if skip != 0:
		return
	await UI.say([
		tr("Use W A S D (ou as setas) para andar."),
		tr("Perto de um objeto interativo aparece [F]. Aperte F (ou Enter) para usar."),
		tr("Aperte I (ou Tab) para abrir a mochila. Esc cancela os menus."),
		tr("Aperte 1 para trocar entre o astronauta (estação) e o cientista (Terra)."),
		tr("Aperte M (ou J) para ver as missões. O objetivo atual aparece no canto da tela por um tempo; depois fica só um \"!\" (clique nele ou aperte V para ver de novo)."),
		tr("Fique de olho nas barras de comida, sono e água lá embaixo!"),
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
		var a := await UI.choose([tr("Usar"), tr("Voltar")], GameState.item_name(chosen))
		if a == 0:
			await _consume(chosen)
	g.queue_free()


func _inventory_text(_i: int, id: String) -> String:
	var head := tr("Mochila %d/%d") % [GameState.inventory.size(), GameState.INVENTORY_SLOTS]
	if id == "":
		return head + tr("\nEspaço vazio.   Esc: fechar")
	return tr("%s: %s\n%s   F: usar   Esc: fechar") % [head, GameState.item_name(id), _effects_text(GameState.ITEMS[id]["effects"])]


func _consume(id: String) -> void:
	if id == "amostra":
		await _comer_amostra()
		return
	if GameState.ITEMS[id]["effects"].is_empty():
		await UI.say(tr("%s não pode ser usado assim.") % GameState.item_name(id))
		return
	if GameState.remove_item(id):
		GameState.use_item(id)
		await UI.say(tr("Você usou %s. %s") % [GameState.item_name(id), _effects_text(GameState.ITEMS[id]["effects"])])


# Comer a amostra: se estiver estragada (mesmo que a base tenha dito sucesso) tira 50% da vida atual.
func _comer_amostra() -> void:
	if Missions.is_step("enviar"):
		await UI.say(tr("Você precisa enviar esta amostra à base antes. Não dá para comê-la agora."))
		return
	if not GameState.remove_item("amostra"):
		return
	await UI.say(Missions.eat_sample())


func _effects_text(effects: Dictionary) -> String:
	if effects.is_empty():
		return tr("Sem efeito.")
	var names := {"food": tr("Comida"), "thirst": tr("Água"), "sleep": tr("Sono"), "health": tr("Vida")}
	var parts: Array[String] = []
	for k in effects:
		parts.append("%s %+d" % [names.get(k, k), int(effects[k])])
	return ", ".join(parts) + "."


# ============================ cafeteria ============================
func _cafeteria_item(_source: Node, id: String, title: String, now_label: String) -> void:
	var label := GameState.item_name(id)
	var i := await UI.choose([now_label, tr("Guardar na mochila"), tr("Cancelar")], title)
	if i == 0:
		GameState.use_item(id)
		await UI.say("%s! %s" % [label, _effects_text(GameState.ITEMS[id]["effects"])])
	elif i == 1:
		if GameState.add_item(id):
			await UI.say(tr("%s guardado na mochila.") % label)
		else:
			await UI.say(tr("A mochila está cheia! (%d espaços)") % GameState.INVENTORY_SLOTS)


# ============================ dormitorio ============================
func _bunk() -> void:
	var i := await UI.choose([tr("Dormir"), tr("Cancelar")], tr("Beliche (2 vagas)"))
	if i != 0:
		return
	UI.lock()  # mantem o tempo parado durante o fade
	await UI.blink(1.2, 0.8)
	UI.unlock()
	GameState.apply_effects({"sleep": 100.0, "food": -10.0, "thirst": -10.0})
	await UI.say([tr("Você dormiu um pouco."), tr("Sono restaurado, mas deu fome e sede. (Sistema com %d camas: em breve)") % GameState.BEDS])


# ============================ armazem ============================
func _impressora() -> void:
	var i := await UI.choose([tr("Produzir ração"), tr("Fechar")], tr("Impressora de comida"))
	if i != 0:
		return
	if GameState.output_rations >= 5:
		await UI.say(tr("A saída já está cheia (5 rações). Retire no terminal ao lado esquerdo."))
		return
	UI.toast(tr("Produzindo ração..."), GameState.PRODUCE_TIME)
	await get_tree().create_timer(GameState.PRODUCE_TIME).timeout
	GameState.output_rations += 1
	GameState.inventory_changed.emit()
	await UI.say([tr("Ração pronta!"), tr("Ela saiu no terminal grande da esquerda.")])


func _terminal_saida() -> void:
	var n := GameState.output_rations
	if n <= 0:
		await UI.say(tr("Nenhuma ração pronta. Produza uma na impressora de comida (máquina da direita)."))
		return
	var i := await UI.choose([tr("Retirar ração (%d)") % n, tr("Fechar")], tr("Terminal de saída"))
	if i != 0:
		return
	if not GameState.inventory_has_room():
		await UI.say(tr("A mochila está cheia! (%d espaços)") % GameState.INVENTORY_SLOTS)
		return
	GameState.output_rations -= 1
	GameState.add_item("racao")
	await UI.say(tr("Você pegou 1 ração."))


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
			var a := await UI.choose([tr("Retirar para a mochila"), tr("Voltar")], GameState.item_name(id))
			if a == 0 and not GameState.take_storage_at(i):
				await UI.say(tr("A mochila está cheia! (%d espaços)") % GameState.INVENTORY_SLOTS)
		else:
			await _armario_guardar()
	g.queue_free()


func _storage_text(_i: int, id: String) -> String:
	var head := tr("Armário %d/%d") % [GameState.storage.size(), GameState.STORAGE_SLOTS]
	if id == "":
		return head + tr("\nEspaço vazio.   F: guardar um item da mochila   Esc: fechar")
	return tr("%s: %s\n%s   F: retirar   Esc: fechar") % [head, GameState.item_name(id), _effects_text(GameState.ITEMS[id]["effects"])]


func _armario_guardar() -> void:
	if not GameState.storage_has_room():
		await UI.say(tr("O armário está cheio! (%d espaços)") % GameState.STORAGE_SLOTS)
		return
	var ids := GameState.unique_ids(GameState.inventory)
	if ids.is_empty():
		await UI.say(tr("Você não tem nada na mochila para guardar."))
		return
	var opts: Array = []
	for id in ids:
		opts.append(GameState.item_name(id))
	opts.append(tr("Voltar"))
	var i := await UI.choose(opts, tr("Guardar qual item?"))
	if i >= 0 and i < ids.size() and GameState.store_item(ids[i]):
		await UI.say(tr("%s guardado no armário.") % GameState.item_name(ids[i]))


func _capsula() -> void:
	# A cápsula tem 1 ESPAÇO: ou leva um item para a Terra, ou traz um item de volta.
	while true:
		var title := tr("Cápsula (1 espaço)")
		var i := await UI.choose([tr("Enviar item"), tr("Retirar item"), tr("Fechar")], title)
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
			await UI.say([tr("%s está na Terra, esperando o veredito da base.") % GameState.item_name(GameState.capsule_item), tr("Aperte 1 para ver a base (cientista).")])
		else:
			await UI.say(tr("A cápsula está a caminho da Terra com: %s. Chega em %d s.") % [GameState.item_name(GameState.capsule_item), ceili(GameState.capsule_left)])
		return true
	if GameState.capsule_ready != "":
		await UI.say(tr("O espaço da cápsula está ocupado por: %s. Retire primeiro.") % GameState.item_name(GameState.capsule_ready))
		return true
	return false


## true = acabou (enviou); false = volta ao menu
func _capsula_enviar() -> bool:
	if not Voyage.comms_ok():
		await UI.say(tr("Sem contato com a base: a cápsula está bloqueada pela interferência."))
		return false
	if await _capsula_ocupada():
		return false
	var ids := GameState.unique_ids(GameState.inventory)
	if ids.is_empty():
		await UI.say(tr("Você não tem nada na mochila para enviar."))
		return false
	var opts: Array = []
	for id in ids:
		opts.append(GameState.item_name(id))
	opts.append(tr("Voltar"))
	var i := await UI.choose(opts, tr("Enviar para a Terra"))
	if i < 0 or i >= ids.size():
		return false
	var chosen: String = ids[i]
	if chosen == "amostra":
		# amostra da missao: a BASE analisa; ela fica na Terra ate o veredito
		if not Missions.is_step("enviar"):
			await UI.say(tr("Esta amostra ainda não está pronta para ser enviada."))
			return false
		if GameState.send_to_earth(chosen, true):
			Missions.send_data()
			await UI.say([tr("Amostra enviada à Terra."), tr("A base vai analisar e dar o veredito; só então ela volta. Aperte 1 para ir à base.")])
			return true
		return false
	if GameState.send_to_earth(chosen):
		await UI.say(tr("Enviado à Terra: %s. Chega de volta em %d segundos.") % [GameState.item_name(chosen), int(GameState.CAPSULE_TIME)])
		return true
	return false


## true = retirou (fecha o menu); false = volta ao menu
func _capsula_retirar() -> bool:
	if GameState.capsule_ready == "":
		if GameState.capsule_item != "":
			await _capsula_ocupada()
		else:
			await UI.say(tr("Não há nada na cápsula para retirar."))
		return false
	var id: String = GameState.capsule_ready
	if not GameState.collect_capsule():
		await UI.say(tr("Sua mochila está cheia! (%d espaços)") % GameState.INVENTORY_SLOTS)
		return false
	if id == "amostra" and not Missions.result_lines.is_empty():
		await UI.say(tr("Você retirou: %s.") % GameState.item_name(id))
		await UI.say(Missions.take_result())
	else:
		await UI.say(tr("Você retirou: %s.") % GameState.item_name(id))
	return true


# ============================ sala do reator ============================
func _nucleo() -> void:
	while true:
		var title := tr("Núcleo %d%%") % int(round(GameState.heat))
		if GameState.meltdown_left >= 0.0:
			title += tr("  EXPLODE EM %d s") % ceili(GameState.meltdown_left)
		var opts: Array = [tr("Resfriar núcleo"), tr("Ver temperatura"), tr("Fechar")]
		if Voyage.event == "reactor":
			opts.insert(2, tr("Ajustar válvulas (URGENTE)"))
		var i := await UI.choose(opts, title)
		if opts[maxi(i, 0)] == tr("Ajustar válvulas (URGENTE)") and i >= 0:
			await _valvulas()
		elif i == 0:
			GameState.cool_core(50.0)
			await UI.say(tr("Sistema de resfriamento ativado. Núcleo em %d%%.") % int(round(GameState.heat)))
		elif i == 1:
			var state := tr("estável")
			if GameState.heat >= GameState.HEAT_WARNING:
				state = tr("PERIGOSO")
			elif GameState.heat >= 60.0:
				state = tr("quente")
			await UI.say(tr("Temperatura do núcleo: %d%% (%s).") % [int(round(GameState.heat)), state])
		else:
			return


func _botiquim() -> void:
	var i := await UI.choose([tr("Curar-se"), tr("Fechar")], tr("Kit médico"))
	if i != 0:
		return
	if GameState.health >= 100.0:
		await UI.say(tr("Você já está com a vida cheia."))
		return
	GameState.heal(50.0)
	await UI.say(tr("Você se curou. Vida: %d.") % int(round(GameState.health)))


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
		var title := ""
		var opts: Array = []
		var acts: Array = []
		if Voyage.active:
			title = tr("Viagem: %s") % tr(Voyage.route)
			opts.append(tr("Mapa espacial"))
			acts.append("mapa")
			if Voyage.maneuver_available():
				opts.append(tr("Manobra evasiva"))
				acts.append("manobra")
		elif Missions.is_step("rota"):
			title = tr("Escolha a rota")
			for r in ROUTES:
				opts.append(tr("Iniciar viagem: ") + tr(r))
				acts.append("rota:" + r)
		else:
			title = tr("Rota: ") + (tr(GameState.route) if GameState.route != "" else tr("nenhum"))
			for r in ROUTES:
				opts.append(tr("Ir para ") + tr(r))
				acts.append("define:" + r)
		if Voyage.dodge_unlocked:
			opts.append(tr("Minigame: campo de asteroides"))
			acts.append("desvio")
		opts.append(tr("Levantar"))
		acts.append("levantar")
		var i := await UI.choose(opts, title)
		if i < 0 or acts[i] == "levantar":
			break
		var a: String = acts[i]
		if a == "desvio":
			await _jogar_desvio(true)
		elif a == "mapa":
			await UI.say(Voyage.map_text())
		elif a == "manobra":
			await UI.say(Voyage.maneuver())
		elif a.begins_with("rota:"):
			var r := a.substr(5)
			var c := await UI.choose([tr("Confirmar viagem para %s") % tr(r), tr("Voltar")], tr("Rota: ") + tr(r))
			if c == 0:
				Voyage.start(r)
				Missions.complete("rota")
				await planet_transition()
				await UI.say([tr("Viagem iniciada: %s.") % tr(r), tr("A base prevê os perigos; a nave faz as manobras. Cuide da energia e do combustível!")])
				await UI.say(tr("Pilote a nave pequena pelo campo de asteroides! Termine sem nenhum dano para liberar este minigame na cabine."))
				await _jogar_desvio(false)
				break
		else:
			var r2 := a.substr(7)
			GameState.route = r2
			await UI.say([tr("Próxima rota definida: %s.") % tr(r2), tr("(A viagem começa na missão de viagem.)")])



# Minigame da nave: desviar de asteroides. Sem dano = libera para jogar quando quiser na cabine.
func _jogar_desvio(free_play: bool) -> void:
	var g = UI.open_dodge(free_play)
	await g.closed
	var clean: bool = g.finished and g.hits == 0
	g.queue_free()
	if clean and not Voyage.dodge_unlocked:
		Voyage.dodge_unlocked = true


# ============================ missoes ============================
func open_missions() -> void:
	await UI.show_panel(Missions.summary_text())


# Missao 1 (espaco): pegar pacotes -> aquecer -> centrifugar -> enviar pela capsula (a base analisa).
# As estacoes usam objetos que ja existem nas salas (placeholders ate chegarem as imagens finais).
func _estante_culturas() -> void:
	if not Missions.is_step("pacotes"):
		await UI.say(tr("Estante com pacotes de culturas e materiais diversos."))
		return
	var i := await UI.choose([tr("Pegar pacote de cultura de fungos"), tr("Cancelar")], tr("Estante de culturas"))
	if i != 0:
		return
	if not GameState.add_item("pacote_fungos"):
		await UI.say(tr("A mochila está cheia! (%d espaços)") % GameState.INVENTORY_SLOTS)
		return
	Missions.complete("pacotes")
	await UI.say([tr("Você pegou um pacote com a cultura de fungos."), tr("Leve-o à máquina de aquecimento (os containers azuis, no canto direito).")])


func _aquecedor() -> void:
	match Missions.heater_state:
		"heating":
			await UI.say(tr("Aquecendo os pacotes... faltam %d s.") % ceili(Missions.heating_left))
		"ready":
			if not GameState.add_item("pacote_quente"):
				await UI.say(tr("A mochila está cheia! (%d espaços)") % GameState.INVENTORY_SLOTS)
				return
			Missions.heater_state = "idle"
			Missions.complete("aquecer")
			await UI.say([tr("Pacote aquecido!"), tr("Agora leve para a centrífuga (sala de controle, máquinas do canto esquerdo).")])
		_:
			if Missions.is_step("aquecer") and GameState.inventory.has("pacote_fungos"):
				var i := await UI.choose([tr("Colocar pacote para aquecer"), tr("Cancelar")], tr("Máquina de aquecimento"))
				if i == 0 and GameState.remove_item("pacote_fungos"):
					Missions.heater_state = "heating"
					Missions.heating_left = Missions.HEAT_TIME
					Missions.changed.emit()
					await UI.say(tr("Aquecendo... volte em %d segundos.") % int(Missions.HEAT_TIME))
			else:
				await UI.say(tr("Máquina de aquecimento. (Precisa de um pacote de cultura de fungos.)"))


func _centrifuga() -> void:
	if Missions.is_step("centrifugar") and GameState.inventory.has("pacote_quente"):
		var i := await UI.choose([tr("Esvaziar e centrifugar"), tr("Cancelar")], tr("Centrífuga"))
		if i != 0:
			return
		UI.toast(tr("Centrifugando..."), Missions.SPIN_TIME)
		await get_tree().create_timer(Missions.SPIN_TIME).timeout
		GameState.remove_item("pacote_quente")
		GameState.add_item("amostra")
		Missions.complete("centrifugar")
		await UI.say([tr("Amostra centrifugada!"), tr("Envie-a à base pela cápsula do armazém (cilindro do canto direito).")])
	else:
		await UI.say(tr("Centrífuga. (Precisa de um pacote aquecido.)"))


# Missao 1 (Terra): a base conhece as coloracoes e decide sucesso ou falha.
func _painel_base() -> void:
	var table := tr("Colorações de SUCESSO: %s.   Colorações de FALHA: %s.") % [Missions.color_list(true), Missions.color_list(false)]
	if not Voyage.comms_ok():
		await UI.say([tr("SEM CONTATO com a nave (%d s).") % ceili(Voyage.blackout_left), tr("Painel da base indisponível durante a interferência.")])
		return
	if not Missions.is_step("veredito") and (Voyage.active or Missions.is_step("solar")):
		await _base_viagem()
		return
	if not Missions.is_step("veredito"):
		if Missions.data_sent or not Missions.finished.is_empty():
			await UI.say([tr("Painel da base."), table])
		else:
			await UI.say([tr("Painel da base."), table, tr("Aguardando a amostra da nave.")])
		return
	if not Missions.analyzed:
		await UI.say(tr("Analise a amostra na mesa do microscópio antes de dar o veredito."))
		return
	await UI.say([tr("Coloração observada: %s.") % Missions.color_name().to_upper(), table])
	var i := await UI.choose([tr("Indicar SUCESSO"), tr("Indicar FALHA"), tr("Cancelar")], tr("Veredito da base"))
	if i == 0 or i == 1:
		await UI.say(Missions.verdict(i == 0))


# ============================ dormitorio: checkup ============================
func _checkup() -> void:
	var i := await UI.choose([tr("Fazer checkup"), tr("Cancelar")], tr("Terminal médico"))
	if i != 0:
		return
	UI.toast(tr("Escaneando..."), 1.6)
	await get_tree().create_timer(1.6).timeout
	var lines: Array = [tr("Checkup concluído.")]
	lines.append(tr("Vida %d%%   Comida %d%%   Água %d%%   Sono %d%%") % [
		int(round(GameState.health)), int(round(GameState.food)),
		int(round(GameState.thirst)), int(round(GameState.sleep))])
	var issues: Array[String] = []
	if GameState.health < 60.0:
		issues.append(tr("ferido"))
	if GameState.food < 40.0:
		issues.append(tr("com fome"))
	if GameState.thirst < 40.0:
		issues.append(tr("com sede"))
	if GameState.sleep < 40.0:
		issues.append(tr("cansado"))
	lines.append(tr("Você está bem.") if issues.is_empty() else tr("Atenção: você está ") + ", ".join(issues) + ".")
	if GameState.conditions.is_empty():
		lines.append(tr("Nenhuma doença ou anomalia detectada."))
	else:
		lines.append(tr("Detectado: ") + ", ".join(GameState.conditions) + ".")
	await UI.say(lines)


# ============================ Missao 2: base e reator ============================
func _base_viagem() -> void:
	while true:
		var opts: Array = []
		var acts: Array = []
		if Voyage.active:
			opts.append_array([tr("Monitor da nave"), tr("Previsão de perigos"), tr("Enviar alerta à nave")])
			acts.append_array(["monitor", "previsao", "alerta"])
		if Missions.is_step("solar"):
			opts.append(tr("Terminal solar (CME)"))
			acts.append("solar")
		opts.append(tr("Fechar"))
		acts.append("fechar")
		var i := await UI.choose(opts, tr("Painel da base"))
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
		await UI.say([tr("Objeto detectado: velocidade %.1f km/s, distância %d km.") % [speed, dist], tr("Calcule: tempo = distância ÷ velocidade.")])
		var vals: Array = Voyage.asteroid_choices()
		var labels: Array = []
		for v in vals:
			labels.append(tr("Impacto em %d s") % int(v))
		var k := await UI.choose(labels, tr("Quando ele atinge a nave?"))
		if k >= 0:
			Voyage.set_estimate(int(vals[k]))
	await UI.say(Voyage.send_alert())


# Valvulas do reator (astronauta): girar uma valvula gira tambem as vizinhas. O tempo corre durante o minigame.
func _valvulas() -> void:
	UI.realtime = true
	while Voyage.event == "reactor":
		var opts: Array = []
		for k in 5:
			opts.append(tr("Girar válvula %d") % (k + 1))
		opts.append(tr("Sair"))
		var i := await UI.choose(opts, tr("%s   Eficiência %d%%") % [Voyage.valve_state_text(), int(Voyage.reactor_eff())])
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
		var i := await UI.choose([tr("Enviar alerta de abrigo"), tr("Ignorar (falso alarme)"), tr("Ver o terminal de novo")], tr("Decisão da base"))
		if i == 0 or i == 1:
			await UI.say(Solar.decide(i == 0))
			return
		if i < 0:
			return


# Astronauta: chave dos escudos no controle de energia (sala do reator, maquinas da esquerda).
func _escudos() -> void:
	if not Solar.alert_sent or Solar.resolved:
		await UI.say(tr("Controle de energia e suporte de vida. Nenhum alerta solar ativo."))
		return
	if Solar.shield_on:
		await UI.say(tr("Os escudos já estão ativos. Aguarde a onda passar."))
		return
	var i := await UI.choose([tr("Ativar escudos"), tr("Cancelar")], tr("Controle de energia"))
	if i == 0:
		Solar.activate_shield()
		await UI.say([tr("Escudos ativados!"), tr("Energia redirecionada. Aguarde a onda passar.")])


# Mesa de analise (lado da Terra): placa de Petri (missao) e analise de amostra ao microscopio.
func _mesa_analise() -> void:
	var can_petri := Missions.is_step("veredito") and not Missions.analyzed
	if Missions.is_step("veredito") and Missions.analyzed:
		await UI.say([tr("A amostra já foi analisada."), tr("Coloração observada: %s.") % Missions.color_name().to_upper(), tr("Agora dê o veredito no painel da base.")])
	var opts: Array = []
	if can_petri:
		opts.append(tr("Fungo (amostra da nave)"))
	opts.append(tr("Microscópio: contar colônias"))
	opts.append(tr("Cancelar"))
	var i := await UI.choose(opts, tr("O que você quer analisar?"))
	if i < 0 or i >= opts.size() - 1:
		return
	if can_petri and i == 0:
		var g = UI.open_petri()
		await g.closed
		g.queue_free()
		if Missions.analyzed:
			await UI.say([tr("Análise concluída."), tr("Coloração observada: %s.") % Missions.color_name().to_upper(), tr("Agora dê o veredito no painel da base.")])
		return
	var d := await _escolher_dificuldade()
	if d < 0:
		return
	var m = UI.open_microscope(d)
	await m.closed
	var res: Dictionary = m.result
	m.queue_free()
	if not res.is_empty():
		await UI.say([tr("Você contou %d colônias → %s.") % [res["count"], res["label"]],
			tr("Valor real: %d → %s. Pontuação: %d%%.") % [res["truth"], res["true_label"], res["score"]]])


func _escolher_dificuldade() -> int:
	var i := await UI.choose([tr("Fácil"), tr("Médio"), tr("Difícil"), tr("Cancelar")], tr("Dificuldade"))
	return i if i >= 0 and i < 3 else -1


# Mural de formulas (Terra): cada acerto da bonus no recurso ligado a formula (vale na viagem).
func _mural_formulas() -> void:
	var i := await UI.choose([tr("Normal"), tr("Difícil (arrastar os valores primeiro)"), tr("Cancelar")], tr("Mural de fórmulas"))
	if i < 0 or i > 1:
		return
	var g = UI.open_mural(i == 1)
	await g.closed
	var res: Dictionary = g.result
	g.queue_free()
	if res.is_empty():
		return
	var lines: Array = []
	for b in res["bonuses"]:
		Voyage.grant(b["kind"], float(b["amount"]))
		lines.append(tr("Bônus enviado à nave: ") + tr(FormulaMural.KIND_TEXT[b["kind"]]) % int(round(float(b["amount"]))))
	if lines.is_empty():
		lines.append(tr("Nenhum bônus desta vez."))
	else:
		lines.append(tr("(O bônus vale na viagem em andamento ou na próxima.)"))
	await UI.say(lines)


# Bancada de frascos (Terra): preparo de reagente; boa qualidade rende combustivel para a viagem.
func _bancada_frascos() -> void:
	var d := await _escolher_dificuldade()
	if d < 0:
		return
	var g = UI.open_reagent(d)
	await g.closed
	var res: Dictionary = g.result
	g.queue_free()
	if res.is_empty():
		return
	var q: int = res["quality"]
	if res["spilled"]:
		await UI.say(tr("O copo transbordou. Nada aproveitável."))
	elif q >= 50:
		var amount := 4.0 + 10.0 * float(q) / 100.0
		Voyage.grant("fuel", amount)
		await UI.say([tr("Reagente com %d%% de qualidade.") % q, tr("Bônus enviado à nave: +%d%% de combustível.") % int(round(amount)), tr("(O bônus vale na viagem em andamento ou na próxima.)")])
	else:
		await UI.say(tr("Reagente com %d%% de qualidade: baixo demais para ser aproveitado.") % q)
