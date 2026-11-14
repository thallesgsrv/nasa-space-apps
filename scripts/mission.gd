extends Node
## Autoload "Mission": modelo de projeto de missao (regras simples e verificaveis).
## ATENCAO: TODOS os valores abaixo sao FICTICIOS, feitos para o jogo. Nao sao dados de missoes reais.
## Inspiracao conceitual (principios, nao numeros): segmentos Launch/Space/Ground/User, requisitos
## mensuraveis, trade space e margens (CML do JPL e webinar "Design and Develop Science Missions").

const BUS_MASS := 100.0         # kg  (plataforma fixa)
const BUS_POWER := 60.0         # W
const BUS_COST := 40.0          # M$
const BUS_RELIABILITY := 0.97   # por ano
const MAX_INSTRUMENTS := 4
const DATA_DAYS := 30.0         # dias por mes simulado
const SUCCESS_FRACTION := 0.9   # fracao minima do requisito de dados para cumprir a missao

const BUDGETS := {"facil": 500.0, "normal": 380.0, "dificil": 320.0}
const DIFFICULTY_NAMES := {"facil": "Fácil", "normal": "Normal", "dificil": "Difícil"}

## needs = tipos de instrumento que respondem a pergunta cientifica
## min_data = dados/dia que precisam CHEGAR a Terra; months = vida util pedida
const OBJECTIVES := {
	"clima": {"name": "Clima da Terra", "needs": ["imager", "radiometer"], "min_data": 6.0, "months": 12, "best_orbit": ["leo", "geo"],
		"desc": "Acompanhar nuvens e temperatura do planeta."},
	"sol": {"name": "Coroa solar", "needs": ["coronagraph", "spectrometer"], "min_data": 4.0, "months": 18, "best_orbit": ["geo", "l1"],
		"desc": "Observar o Sol sem interrupção."},
	"exo": {"name": "Exoplanetas", "needs": ["telescope"], "min_data": 5.0, "months": 24, "best_orbit": ["l1"],
		"desc": "Detectar planetas por trânsito."},
}

## mass kg, power W, data dados/dia, cost M$, rel confiabilidade por ano
const INSTRUMENTS := {
	"imager": {"name": "Câmera multiespectral", "type": "imager", "mass": 45.0, "power": 55.0, "data": 5.0, "cost": 60.0, "rel": 0.95},
	"radiometer": {"name": "Radiômetro", "type": "radiometer", "mass": 70.0, "power": 90.0, "data": 3.0, "cost": 80.0, "rel": 0.93},
	"coronagraph": {"name": "Coronógrafo", "type": "coronagraph", "mass": 60.0, "power": 40.0, "data": 4.0, "cost": 90.0, "rel": 0.92},
	"spectrometer": {"name": "Espectrômetro", "type": "spectrometer", "mass": 30.0, "power": 25.0, "data": 2.0, "cost": 35.0, "rel": 0.97},
	"telescope": {"name": "Telescópio de trânsito", "type": "telescope", "mass": 85.0, "power": 70.0, "data": 6.0, "cost": 120.0, "rel": 0.94},
}

const ARRAYS := {
	"p": {"name": "Painel solar pequeno", "watts": 150.0, "mass": 20.0, "cost": 15.0},
	"m": {"name": "Painel solar médio", "watts": 300.0, "mass": 35.0, "cost": 25.0},
	"g": {"name": "Painel solar grande", "watts": 550.0, "mass": 60.0, "cost": 40.0},
}

## cap = massa maxima (kg) por orbita
const LAUNCHERS := {
	"pequeno": {"name": "Lançador pequeno", "cap": {"leo": 300.0, "geo": 0.0, "l1": 0.0}, "cost": 40.0, "rel": 0.90},
	"medio": {"name": "Lançador médio", "cap": {"leo": 800.0, "geo": 350.0, "l1": 250.0}, "cost": 110.0, "rel": 0.94},
	"pesado": {"name": "Lançador pesado", "cap": {"leo": 2000.0, "geo": 900.0, "l1": 700.0}, "cost": 220.0, "rel": 0.97},
}

## eclipse = fracao do tempo sem sol; link = fator de contato/distancia para downlink
const ORBITS := {
	"leo": {"name": "Órbita baixa (LEO)", "eclipse": 0.35, "link": 0.2, "storm": false},
	"geo": {"name": "Órbita geoestacionária", "eclipse": 0.05, "link": 1.0, "storm": true},
	"l1": {"name": "Ponto L1 (Sol-Terra)", "eclipse": 0.0, "link": 0.6, "storm": true},
}

## rate = dados/dia que a estacao recebe com link 1.0
const STATIONS := {
	"basica": {"name": "Estação terrestre básica", "rate": 4.0, "cost": 10.0},
	"media": {"name": "Estação terrestre média", "rate": 8.0, "cost": 25.0},
	"rede": {"name": "Rede de estações", "rate": 16.0, "cost": 50.0},
}

var difficulty := "normal"
var objective := ""
var instruments: Array[String] = []
var array_id := ""
var launcher := ""
var orbit := ""
var station := ""


func reset() -> void:
	difficulty = "normal"
	objective = ""
	instruments.clear()
	array_id = ""
	launcher = ""
	orbit = ""
	station = ""


func budget() -> float:
	return BUDGETS[difficulty]


func toggle_instrument(id: String) -> bool:
	if instruments.has(id):
		instruments.erase(id)
		return true
	if instruments.size() >= MAX_INSTRUMENTS:
		return false
	instruments.append(id)
	return true


## Calcula as metricas e os problemas do projeto atual.
func evaluate() -> Dictionary:
	var metrics := _compute_metrics()
	var blocking := _collect_blocking_issues(metrics)
	var warnings := _collect_warning_issues(metrics)
	return {
		"mass": metrics["mass"], "cap": metrics["cap"], "power_gen": metrics["power_gen"], "power_use": metrics["power_use"], "duty": metrics["duty"],
		"data_raw": metrics["data_raw"], "data_gen": metrics["data_gen"], "downlink": metrics["downlink"], "data_day": metrics["data_day"], "cost": metrics["cost"],
		"fit": metrics["fit"], "blocking": blocking, "warnings": warnings,
	}


func _compute_metrics() -> Dictionary:
	var mass := BUS_MASS
	var power_use := BUS_POWER
	var cost := BUS_COST
	var data_raw := 0.0
	var matching := 0
	var need: Array = []
	if objective != "":
		need = OBJECTIVES[objective]["needs"]
	for id in instruments:
		var ins: Dictionary = INSTRUMENTS[id]
		mass += float(ins["mass"])
		power_use += float(ins["power"])
		cost += float(ins["cost"])
		if need.has(ins["type"]):
			matching += 1
			data_raw += float(ins["data"])  # so instrumentos ligados ao objetivo geram ciencia util
	var power_gen := 0.0
	if array_id != "":
		var a: Dictionary = ARRAYS[array_id]
		mass += float(a["mass"])
		cost += float(a["cost"])
		if orbit != "":
			power_gen = float(a["watts"]) * (1.0 - float(ORBITS[orbit]["eclipse"]))
	if station != "":
		cost += float(STATIONS[station]["cost"])
	if launcher != "":
		cost += float(LAUNCHERS[launcher]["cost"])
	var cap := 0.0
	if launcher != "" and orbit != "":
		cap = float(LAUNCHERS[launcher]["cap"][orbit])
	var duty := 0.0
	if array_id != "" and orbit != "":
		duty = minf(1.0, power_gen / power_use)
	var data_gen := data_raw * duty
	var downlink := 0.0
	if station != "" and orbit != "":
		downlink = float(STATIONS[station]["rate"]) * float(ORBITS[orbit]["link"])
	var data_day := minf(data_gen, downlink)
	var fit := 1.0
	if objective != "" and orbit != "" and not OBJECTIVES[objective]["best_orbit"].has(orbit):
		fit = 0.6
	return {
		"mass": mass,
		"cap": cap,
		"power_gen": power_gen,
		"power_use": power_use,
		"duty": duty,
		"data_raw": data_raw,
		"data_gen": data_gen,
		"downlink": downlink,
		"data_day": data_day,
		"cost": cost,
		"fit": fit,
		"matching": matching,
	}


func _collect_blocking_issues(metrics: Dictionary) -> Array[String]:
	var blocking: Array[String] = []
	if objective == "":
		blocking.append("Defina o objetivo científico.")
	if instruments.is_empty():
		blocking.append("Escolha ao menos um instrumento.")
	elif objective != "" and metrics["matching"] == 0:
		blocking.append("Nenhum instrumento responde ao objetivo (%s)." % OBJECTIVES[objective]["name"])
	if array_id == "":
		blocking.append("Escolha o painel solar.")
	if launcher == "":
		blocking.append("Escolha o lançador.")
	if orbit == "":
		blocking.append("Escolha a órbita.")
	if station == "":
		blocking.append("Escolha a estação terrestre.")
	if launcher != "" and orbit != "" and metrics["mass"] > metrics["cap"]:
		if metrics["cap"] <= 0.0:
			blocking.append("%s não alcança essa órbita." % LAUNCHERS[launcher]["name"])
		else:
			blocking.append("Massa %d kg acima da capacidade do lançador (%d kg)." % [int(metrics["mass"]), int(metrics["cap"])])
	if metrics["cost"] > budget():
		blocking.append("Custo %d M$ acima do orçamento (%d M$)." % [int(metrics["cost"]), int(budget())])
	return blocking


func _collect_warning_issues(metrics: Dictionary) -> Array[String]:
	var warnings: Array[String] = []
	if metrics["duty"] > 0.0 and metrics["duty"] < 1.0:
		warnings.append("Energia insuficiente: instrumentos a %d%% do tempo." % int(metrics["duty"] * 100.0))
	if metrics["data_gen"] > metrics["downlink"] and metrics["downlink"] > 0.0:
		warnings.append("Comunicação limita os dados: gera %.1f/dia, chegam %.1f/dia." % [metrics["data_gen"], metrics["downlink"]])
	if metrics["fit"] < 1.0:
		warnings.append("Órbita pouco adequada ao objetivo: ciência cai 40%.")
	if objective != "" and metrics["matching"] < instruments.size():
		warnings.append("Há instrumentos sem relação com o objetivo (massa e custo desperdiçados).")
	return warnings


func review_lines() -> Array[String]:
	var ev := evaluate()
	var out: Array[String] = []
	out.append("Massa %d/%d kg | Energia %d/%d W" % [int(ev["mass"]), int(ev["cap"]), int(ev["power_gen"]), int(ev["power_use"])])
	out.append("Dados %.1f/dia, link %.1f/dia | Custo %d/%d M$" % [ev["data_gen"], ev["downlink"], int(ev["cost"]), int(budget())])
	if objective != "":
		var o: Dictionary = OBJECTIVES[objective]
		out.append("Requisito: %.1f dados/dia por %d meses (mínimo %d%%)." % [o["min_data"], o["months"], int(SUCCESS_FRACTION * 100.0)])
	for b in ev["blocking"]:
		out.append("BLOQUEIA: " + str(b))
	for w in ev["warnings"]:
		out.append("Aviso: " + str(w))
	if ev["blocking"].is_empty() and ev["warnings"].is_empty():
		out.append("Projeto consistente. Pronto para lançar.")
	return out


## Simula a missao e devolve {ok, success, score, lines}.
func launch() -> Dictionary:
	var ev := evaluate()
	var lines: Array[String] = []
	if not ev["blocking"].is_empty():
		lines.append("Revisão reprovada. O lançamento foi cancelado.")
		for b in ev["blocking"]:
			lines.append("- " + str(b))
		return {"ok": false, "success": false, "score": 0, "lines": lines}

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var o: Dictionary = OBJECTIVES[objective]
	var months: int = o["months"]
	lines.append("Lançamento com %s para %s." % [LAUNCHERS[launcher]["name"], ORBITS[orbit]["name"]])
	if rng.randf() > float(LAUNCHERS[launcher]["rel"]):
		lines.append("FALHA NO LANÇAMENTO. O foguete foi perdido.")
		lines.append("Motivo: risco do lançador (confiabilidade %d%%)." % int(float(LAUNCHERS[launcher]["rel"]) * 100.0))
		return {"ok": true, "success": false, "score": 5, "lines": lines}
	lines.append("Órbita atingida. Comissionamento concluído.")

	var active: Array[String] = instruments.duplicate()
	var lost := 0
	var total := 0.0
	var months_run := 0
	var downlink: float = ev["downlink"]
	var duty: float = ev["duty"]
	var fit: float = ev["fit"]
	var bus_failed := false
	for month in range(1, months + 1):
		if rng.randf() < (1.0 - BUS_RELIABILITY) / 12.0:
			lines.append("Mês %d: falha na plataforma. Missão encerrada." % month)
			bus_failed = true
			break
		months_run = month
		for id in active.duplicate():
			if rng.randf() < (1.0 - float(INSTRUMENTS[id]["rel"])) / 12.0:
				active.erase(id)
				lost += 1
				lines.append("Mês %d: %s falhou." % [month, INSTRUMENTS[id]["name"]])
		var storm := 1.0
		if ORBITS[orbit]["storm"] and rng.randf() < 0.08:
			storm = 0.5
			lines.append("Mês %d: tempestade solar reduziu os dados." % month)
		var gen := 0.0
		for id in active:
			if o["needs"].has(INSTRUMENTS[id]["type"]):
				gen += float(INSTRUMENTS[id]["data"])
		gen *= duty
		total += minf(gen, downlink) * DATA_DAYS * storm * fit
	var required: float = float(o["min_data"]) * DATA_DAYS * months
	var frac := total / required
	lines.append("Operou %d de %d meses. Dados entregues: %d de %d (%d%%)." % [months_run, months, int(total), int(required), int(frac * 100.0)])

	var success := frac >= SUCCESS_FRACTION and not bus_failed
	var thrift := clampf((budget() - float(ev["cost"])) / budget(), 0.0, 1.0)
	var score := int(clampf(frac, 0.0, 1.2) / 1.2 * 70.0 + thrift * 20.0 + (10.0 if lost == 0 and not bus_failed else 0.0))
	if success:
		lines.append("MISSÃO CUMPRIDA! Pontuação: %d/100." % score)
	else:
		lines.append("MISSÃO NÃO ATINGIU OS REQUISITOS. Pontuação: %d/100." % score)
		lines.append("Por quê: " + _failure_reason(ev, bus_failed, lost, frac))
	if not ev["warnings"].is_empty():
		lines.append("Pontos de atenção do projeto:")
		for w in ev["warnings"]:
			lines.append("- " + str(w))
	return {"ok": true, "success": success, "score": score, "lines": lines}


func _failure_reason(ev: Dictionary, bus_failed: bool, lost: int, frac: float) -> String:
	if bus_failed:
		return "a plataforma falhou antes do fim da vida útil. Faltou margem de confiabilidade."
	var power_loss: float = float(ev["data_raw"]) - float(ev["data_gen"])
	var comm_loss: float = maxf(0.0, float(ev["data_gen"]) - float(ev["downlink"]))
	if comm_loss > 0.0 and comm_loss >= power_loss:
		return "a comunicação não escoou os dados. Use estação melhor ou órbita com mais contato."
	if power_loss > 0.0:
		return "energia insuficiente deixou os instrumentos desligados parte do tempo."
	if float(ev["fit"]) < 1.0:
		return "a órbita escolhida não era a ideal para o objetivo."
	if lost > 0:
		return "falhas de instrumentos reduziram os dados. Considere instrumentos mais confiáveis."
	if frac < SUCCESS_FRACTION:
		return "os instrumentos geram dados abaixo do requisito. Adicione instrumentos úteis."
	return "combinação de azar e margens pequenas."
