extends Node
## Missao 2: viagem ate a rota escolhida (autoload "Voyage").
## Controla tempo limite, energia, combustivel, massa, o sorteio de eventos e os tres eventos:
##   comm (interferencia na comunicacao), asteroid (rota de colisao) e reactor (falha termica / valvulas).
## Regras vindas do documento de design + respostas do grupo; os NUMEROS sao placeholders (ajuste aqui).
## Quem preve o que vai acontecer e a BASE (cientista na Terra): previsao e dados dos eventos so la.

signal changed

const ROUTES := {
	"Lua": {"travel": 180.0, "limit": 260.0},
	"Marte": {"travel": 240.0, "limit": 340.0},
	"Júpiter": {"travel": 300.0, "limit": 420.0},
}

const EVENT_INTERVAL := 30.0     # a cada 30 s ha um sorteio
const NO_EVENT_CHANCE := 0.85    # 85% de nao acontecer nada
const KINDS := ["comm", "asteroid", "reactor"]
const KIND_NAMES := {
	"comm": "Interferência na comunicação",
	"asteroid": "Rota de colisão com asteroide",
	"reactor": "Falha térmica do reator",
}

const ENERGY_DRAIN := 0.12       # % de energia por segundo (antes dos multiplicadores)
const FUEL_DRAIN := 0.10         # % de combustivel por segundo (vezes massa/100)
const MANEUVER_FUEL := 25.0
const MANEUVER_ENERGY := 30.0    # manobra gasta MUITA energia...
const MANEUVER_TIME := 30.0      # ...o que reduz o tempo planejado da missao
const BLACKOUT_TIME := 25.0
const SEE_ASTEROID_AT := 12.0    # a tripulacao so percebe o asteroide a esta distancia (em segundos)
const ASTEROID_HIT_CHANCE := 0.85  # pequena chance de passar sem colidir mesmo sem manobra

const REACTOR_QUICK_TIME := 25.0   # estabilizacao rapida (poucas jogadas)
const REACTOR_QUICK_MOVES := 4
const REACTOR_DEADLINE := 60.0     # dentro do prazo
const REACTOR_HARD_LIMIT := 90.0   # depois disso o reator desliga
const REACTOR_HEAT_JUMP := 25.0
const POS_NAMES := ["N", "L", "S", "O"]

var active := false
var bonus := {}               # bonus dos minigames da base ainda nao usados (aplicados ao iniciar a viagem)
var comms_cut := 0.0          # segundos a menos nos proximos apagoes de comunicacao
var dodge_unlocked := false   # terminou o minigame da nave sem dano: libera jogar na cabine
var route := ""
var travel_time := 1.0
var time_left := 0.0
var progress := 0.0          # 0..100
var energy := 100.0
var fuel := 100.0
var mass := 100.0
var energy_mult := 1.0

var next_event := ""         # ja sorteado para o proximo intervalo (so a base enxerga)
var next_in := EVENT_INTERVAL
var event := ""              # evento em andamento
var blackout_left := 0.0
var asteroid: Dictionary = {}
var reactor: Dictionary = {}
var base_alert := ""         # ultimo alerta que a base mandou para a nave

var _seen_asteroid := false


func reset() -> void:
	active = false
	route = ""
	progress = 0.0
	energy = 100.0
	fuel = 100.0
	mass = 100.0
	energy_mult = 1.0
	next_event = ""
	next_in = EVENT_INTERVAL
	event = ""
	blackout_left = 0.0
	asteroid = {}
	reactor = {}
	base_alert = ""
	_seen_asteroid = false
	GameState.heat_extra_rate = 0.0
	changed.emit()


## Comeca a viagem. Os efeitos da Missao 1 entram aqui (massa, consumo de energia, tempo limite).
func start(route_name: String) -> void:
	if not ROUTES.has(route_name):
		return
	reset()
	active = true
	route = route_name
	travel_time = ROUTES[route_name]["travel"]
	time_left = ROUTES[route_name]["limit"]
	MissionState.apply_to_voyage()   # massa, combustivel, consumo e margem vindos do planejamento (CML)
	var fx: Dictionary = Missions.flags
	if fx.get("nave_leve", false):
		mass = minf(mass, 90.0)
	if fx.get("menos_energia", false):
		energy_mult *= 0.8
	if fx.get("energia_extra", false):
		energy_mult *= 1.2
	if fx.get("mais_tempo", false):
		time_left += 60.0
	for k in bonus:
		_apply_bonus(k, float(bonus[k]), true)
	bonus = {}
	_roll_next()
	GameState.route = route_name
	GameState.notice.emit(tr("Viagem iniciada: %s") % route_name)
	changed.emit()


## Bonus ganho nos minigames da base (Terra). Com a viagem em andamento vale na hora; antes dela
## fica guardado e entra quando a viagem comecar. kind: time | energy | comms | mass | fuel.
func grant(kind: String, amount: float) -> void:
	if active:
		_apply_bonus(kind, amount, false)
		changed.emit()
	else:
		bonus[kind] = float(bonus.get(kind, 0.0)) + amount


func _apply_bonus(kind: String, amount: float, at_start: bool) -> void:
	match kind:
		"time":
			time_left += amount
		"energy":
			if at_start:
				energy_mult *= maxf(0.6, 1.0 - amount * 0.006)
			else:
				energy = minf(100.0, energy + amount)
		"fuel":
			if at_start:
				mass = maxf(70.0, mass - amount * 0.3)
			else:
				fuel = minf(100.0, fuel + amount)
		"mass":
			mass = maxf(70.0, mass - amount)
		"comms":
			comms_cut = minf(20.0, comms_cut + amount)
			blackout_left = maxf(0.0, blackout_left - amount)


func comms_ok() -> bool:
	return blackout_left <= 0.0


func _process(delta: float) -> void:
	if Net.is_client():
		return
	if not active or not GameState.running:
		return
	if UI.busy and not UI.realtime:
		return  # menus congelam a viagem (o minigame das valvulas roda em tempo real)
	_tick(delta)


func _tick(delta: float) -> void:
	time_left -= delta
	progress += 100.0 / travel_time * delta
	energy -= ENERGY_DRAIN * energy_mult * delta
	fuel -= FUEL_DRAIN * (mass / 100.0) * delta

	if blackout_left > 0.0:
		blackout_left -= delta
		if blackout_left <= 0.0:
			blackout_left = 0.0
			if event == "comm":
				event = ""
			GameState.notice.emit(tr("Comunicação com a base restabelecida."))
			MissionState.set_outcome("comm", true)

	next_in -= delta
	if next_in <= 0.0:
		if next_event != "" and event == "":
			_trigger(next_event)
		_roll_next()
		next_in = EVENT_INTERVAL

	if event == "asteroid":
		_tick_asteroid(delta)
	elif event == "reactor":
		_tick_reactor(delta)

	if not active:
		return
	if progress >= 100.0:
		_arrive()
	elif energy <= 0.0:
		_fail(tr("A energia da nave acabou. Tudo desligou no escuro."))
	elif fuel <= 0.0:
		_fail(tr("O combustível acabou. A nave ficou à deriva."))
	elif time_left <= 0.0:
		_fail(tr("O tempo da missão esgotou antes da chegada."))
	else:
		changed.emit()


func _roll_next() -> void:
	next_event = "" if randf() < 1.0 - MissionState.event_chance() else MissionState.pick_event_kind()


## Dispara um evento (usado pelo sorteio; tambem serve para testes).
func force_event(kind: String) -> void:
	if active and event == "":
		_trigger(kind)


func _trigger(kind: String) -> void:
	event = kind
	_log_event(kind)
	match kind:
		"comm":
			blackout_left = maxf(5.0, BLACKOUT_TIME * MissionState.blackout_mult() - comms_cut)
			GameState.notice.emit(tr("Interferência na comunicação! Sem contato com a base por %d s.") % int(blackout_left))
		"asteroid":
			var speed := randf_range(6.0, 12.0)
			var eta := randf_range(28.0, 40.0)
			asteroid = {
				"speed": speed, "eta": eta, "distance": speed * eta,
				"will_hit": randf() < ASTEROID_HIT_CHANCE, "maneuvered": false, "estimate": -1,
			}
			_seen_asteroid = false
		"reactor":
			_start_reactor()
	changed.emit()


## Registra o evento no relatorio com o selo de origem (nada aqui e registro real da NASA).
func _log_event(kind: String) -> void:
	var tag := MissionState.TAG_FICT
	var label: String = KIND_NAMES.get(kind, kind)
	if kind == "comm":
		tag = MissionState.TAG_RISK   # blecaute de radio por atividade solar e um fenomeno real; aqui e simulado
	MissionState.log_event(kind, tag, label, MissionState.cause_for(kind))


func _fail(reason: String) -> void:
	active = false
	comms_cut = 0.0
	GameState.heat_extra_rate = 0.0
	GameState.failed.emit(reason)


func _arrive() -> void:
	active = false
	comms_cut = 0.0
	event = ""
	GameState.heat_extra_rate = 0.0
	GameState.notice.emit(tr("Chegada ao destino: %s! Missão cumprida.") % tr(route))
	Missions.complete("viajar")
	changed.emit()


# ============================ asteroide ============================
func asteroid_visible() -> bool:
	return event == "asteroid" and float(asteroid["eta"]) <= SEE_ASTEROID_AT


func maneuver_available() -> bool:
	return event == "asteroid" and not bool(asteroid["maneuvered"]) and (asteroid_visible() or base_alert == "asteroid")


func _tick_asteroid(delta: float) -> void:
	asteroid["eta"] = float(asteroid["eta"]) - delta
	var eta: float = asteroid["eta"]
	if not _seen_asteroid and eta <= SEE_ASTEROID_AT:
		_seen_asteroid = true
		GameState.notice.emit(tr("ALERTA: objeto se aproximando! Impacto em ~%d s. Faça a manobra na cadeira de comando!") % int(ceil(eta)))
	if eta <= 0.0:
		if bool(asteroid["maneuvered"]) or not bool(asteroid["will_hit"]):
			GameState.notice.emit(tr("O objeto passou sem atingir a nave."))
			MissionState.set_outcome("asteroid", true)
			event = ""
			asteroid = {}
			base_alert = ""
		else:
			_fail(tr("A nave colidiu com um asteroide."))


## Manobra evasiva (astronauta). Devolve a mensagem para mostrar.
func maneuver() -> String:
	if not maneuver_available():
		return tr("Nenhum perigo para desviar agora.")
	if fuel < MANEUVER_FUEL:
		return tr("Combustível insuficiente para a manobra.")
	fuel -= MANEUVER_FUEL
	energy = maxf(0.0, energy - MANEUVER_ENERGY)
	time_left -= MANEUVER_TIME
	asteroid["maneuvered"] = true
	changed.emit()
	return tr("Manobra evasiva feita! Combustível -%d, energia -%d, tempo -%d s.") % [int(MANEUVER_FUEL), int(MANEUVER_ENERGY), int(MANEUVER_TIME)]


## Tres tempos de impacto possiveis (um e o certo) para o minigame de calculo da base.
func asteroid_choices() -> Array:
	var real := maxi(1, int(round(float(asteroid["eta"]))))
	var out: Array = [real, real + 9, maxi(1, real - 7)]
	out.shuffle()
	return out


func set_estimate(seconds: int) -> void:
	if Net.is_client():
		await Net.call_host("Voyage", "set_estimate", [seconds])
		return
	MissionState.stat_inc("base_actions")
	if event == "asteroid":
		asteroid["estimate"] = seconds


# ============================ reator (valvulas) ============================
func _start_reactor() -> void:
	var targets: Array = []
	var two: Array = []
	for i in 5:
		targets.append(randi() % 4)
		two.append(randf() < 0.4)   # 1 posicao correta ou 2 possiveis
	var st: Array = targets.duplicate()
	for k in 6:
		_rotate(st, randi() % 5)    # embaralha a partir do alvo: sempre existe solucao
	reactor = {"targets": targets, "two": two, "state": st, "eff": 0.0, "moves": 0, "wrong": 0, "elapsed": 0.0}
	if _correct() == 5:
		_rotate(reactor["state"], 0)
	var jump := REACTOR_HEAT_JUMP * lerpf(1.2, 0.8, MissionState.p("reliability") / 100.0)   # confiabilidade (CML 3)
	if MissionState.use_part("reator"):
		jump *= 0.6   # peca reserva (CML 4) amortece o salto de temperatura
	GameState.heat = maxf(GameState.heat, minf(95.0, GameState.heat + jump))   # nunca esfria o nucleo
	_apply_reactor_rate()
	GameState.notice.emit(tr("ALERTA: falha térmica no reator! Ajuste as válvulas no painel do núcleo (a base tem os alvos)."))


## Girar a valvula i tambem gira as vizinhas (estilo "Lights Out"), em passos N->L->S->O.
func _rotate(arr: Array, i: int) -> void:
	for j in [i - 1, i, i + 1]:
		if j >= 0 and j < arr.size():
			arr[j] = (int(arr[j]) + 1) % 4


func _valve_ok(i: int) -> bool:
	var s: int = reactor["state"][i]
	var t: int = reactor["targets"][i]
	return s == t or (bool(reactor["two"][i]) and s == (t + 2) % 4)


func _correct() -> int:
	var c := 0
	for i in 5:
		if _valve_ok(i):
			c += 1
	return c


func reactor_eff() -> float:
	return float(reactor["eff"]) if event == "reactor" else 0.0


## Uma jogada do astronauta. Jogada que nao melhora faz a temperatura subir mais depressa.
func press(i: int) -> void:
	if event != "reactor" or i < 0 or i > 4:
		return
	var before := _correct()
	_rotate(reactor["state"], i)
	reactor["moves"] = int(reactor["moves"]) + 1
	if _correct() <= before:
		reactor["wrong"] = int(reactor["wrong"]) + 1
	_apply_reactor_rate()
	changed.emit()


func _apply_reactor_rate() -> void:
	var eff: float = reactor["eff"]
	GameState.heat_extra_rate = 0.9 - 2.0 * eff / 100.0 + 0.2 * float(reactor["wrong"])


func _tick_reactor(delta: float) -> void:
	reactor["elapsed"] = float(reactor["elapsed"]) + delta
	var target := float(_correct()) / 5.0 * 100.0
	reactor["eff"] = move_toward(float(reactor["eff"]), target, 20.0 * delta)  # barra com atraso
	_apply_reactor_rate()
	if _correct() == 5 and float(reactor["eff"]) >= 90.0:
		_reactor_stable()
	elif float(reactor["elapsed"]) >= REACTOR_HARD_LIMIT:
		_reactor_shutdown()


func _reactor_stable() -> void:
	var t: float = reactor["elapsed"]
	var moves: int = reactor["moves"]
	if t <= REACTOR_QUICK_TIME and moves <= REACTOR_QUICK_MOVES:
		energy = minf(100.0, energy + 20.0)
		GameState.notice.emit(tr("Reator estabilizado rápido! Potência +20."))
	elif t <= REACTOR_DEADLINE:
		energy = minf(100.0, energy + 8.0)
		GameState.notice.emit(tr("Reator estabilizado dentro do prazo. Potência +8."))
	else:
		GameState.notice.emit(tr("Reator estabilizado, mas fora do prazo: sem bônus."))
	MissionState.set_outcome("reactor", t <= REACTOR_DEADLINE)
	event = ""
	reactor = {}
	GameState.heat_extra_rate = 0.0
	changed.emit()


func _reactor_shutdown() -> void:
	MissionState.set_outcome("reactor", false)
	energy = maxf(0.0, energy - 40.0)
	event = ""
	reactor = {}
	GameState.heat_extra_rate = 0.0
	GameState.heat = 55.0
	GameState.notice.emit(tr("DESLIGAMENTO DO REATOR! Perda grande de potência."))
	_trigger("comm")   # o desligamento ativa direto a interferencia na comunicacao


func valve_state_text() -> String:
	if event != "reactor":
		return ""
	var parts: Array[String] = []
	for i in 5:
		parts.append("V%d:%s" % [i + 1, tr(POS_NAMES[int(reactor["state"][i])])])
	return " ".join(parts)


# ============================ textos (base e astronauta) ============================
func _clock(seconds: float) -> String:
	var s := maxi(0, int(ceil(seconds)))
	return "%02d:%02d" % [s / 60, s % 60]


## Mapa espacial da cadeira de comando (visao do astronauta).
func map_text() -> Array:
	var n := clampi(int(progress / 5.0), 0, 20)
	var bar := "[" + "=".repeat(n) + ">" + ".".repeat(20 - n) + "]"
	var lines: Array = [tr("Rota: %s   %s %d%%") % [tr(route), bar, int(progress)]]
	if asteroid_visible():
		lines.append(tr("!! OBJETO À FRENTE !! Impacto em ~%d s.") % int(ceil(float(asteroid["eta"]))))
	else:
		lines.append(tr("Espaço livre à vista. (Só a base prevê perigos distantes.)"))
	if base_alert != "":
		lines.append(tr("Último alerta da base: ") + tr(KIND_NAMES.get(base_alert, base_alert)))
	return lines


## Monitor da nave (visao da base).
func monitor_text() -> String:
	var lines: Array[String] = [tr("MONITOR DA NAVE"), ""]
	lines.append(tr("Rota: %s   Progresso: %d%%   Tempo restante: %s") % [tr(route), int(progress), _clock(time_left)])
	lines.append(tr("Energia: %d%%   Combustível: %d%%   Massa: %d") % [int(energy), int(fuel), int(mass)])
	if event != "":
		lines.append("")
		lines.append(tr("EM ANDAMENTO: ") + tr(KIND_NAMES[event]))
	lines.append("")
	lines.append(tr("F / Esc / M: fechar"))
	return "\n".join(lines)


## Previsao da base: so a Terra sabe o que o proximo sorteio reserva e os dados dos eventos.
func forecast_text() -> String:
	var lines: Array[String] = [tr("PREVISÃO DE PERIGOS"), ""]
	lines.append(tr("Próximo sorteio de eventos em %d s.") % int(ceil(next_in)))
	if next_event != "":
		lines.append(tr("PREVISTO: ") + tr(KIND_NAMES[next_event]))
	else:
		lines.append(tr("Previsto: nada de perigoso no próximo intervalo."))
	if event == "asteroid":
		lines.append("")
		lines.append(tr("EM ANDAMENTO: asteroide  |  velocidade %.1f km/s  |  distância %d km") % [float(asteroid["speed"]), int(float(asteroid["speed"]) * float(asteroid["eta"]))])
		lines.append(tr("(tempo de impacto = distância ÷ velocidade)"))
	elif event == "reactor":
		lines.append("")
		lines.append(tr("EM ANDAMENTO: reator. Alvos das válvulas (N, L, S, O):"))
		var parts: Array[String] = []
		for i in 5:
			var t: int = reactor["targets"][i]
			var s := "V%d: %s" % [i + 1, tr(POS_NAMES[t])]
			if bool(reactor["two"][i]):
				s += tr(" ou ") + tr(POS_NAMES[(t + 2) % 4])
			parts.append(s)
		lines.append("   ".join(parts))
	lines.append("")
	lines.append(tr("F / Esc / M: fechar"))
	return "\n".join(lines)


## A base manda um alerta para a nave. Devolve o texto mostrado ao jogador.
func send_alert() -> Array:
	if Net.is_client():
		return await Net.call_host("Voyage", "send_alert", [], [])
	MissionState.stat_inc("base_actions")
	var kind := event if event != "" else next_event
	if kind == "":
		return [tr("Nada de perigoso a avisar por enquanto.")]
	base_alert = kind
	var msg := tr("Alerta da base: %s.") % tr(KIND_NAMES[kind])
	if kind == "asteroid" and event == "asteroid":
		var est: int = asteroid["estimate"]
		msg += tr(" Impacto estimado em %s s. Façam a manobra evasiva!") % (str(est) if est >= 0 else "?")
	elif kind == "reactor" and event == "reactor":
		msg += tr(" Os alvos das válvulas estão com a base.")
	GameState.notice.emit(msg)
	changed.emit()
	return [tr("Alerta enviado à nave."), msg]
