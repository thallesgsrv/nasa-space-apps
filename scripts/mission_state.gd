extends Node
## Estado persistente da MISSAO (autoload "MissionState").
## Fase 1 (Terra): os 9 estagios CML escrevem em `params`. Fase 3 (Espaco): Voyage/Solar leem `params`
## e o sorteio de eventos usa os riscos aceitos no CML 7. Fase 6/7: retorno e relatorio pos-missao.
## O host e a autoridade; o cliente (cientista) so espelha (ver SYNC em net.gd).
## Todos os numeros sao PLACEHOLDERS faceis de ajustar. Os valores de DEFAULTS reproduzem o jogo antigo
## (quem pula o planejamento joga exatamente como antes).

signal changed

## Selos de origem dos eventos. Eventos ficticios NUNCA sao apresentados como registro da NASA.
const TAG_REAL := "REAL"
const TAG_RISK := "RISCO"
const TAG_FICT := "FICT"
const TAG_NAMES := {
	"REAL": "REAL: baseado em registro científico real",
	"RISCO": "RISCO REAL: fenômeno real, ocorrência simulada",
	"FICT": "FICTÍCIO: desafio criado para o jogo",
}

const DEFAULTS := {
	"credits": 100.0,       # so existem na Terra; o que sobra vira pontos (ate um teto)
	"mass": 100.0,          # massa da nave (consumo de combustivel)
	"mass_cap": 999.0,      # capacidade do foguete escolhido no CML 2
	"energy_mult": 1.0,     # multiplicador do consumo de energia
	"fuel": 100.0,
	"time_bonus": 0.0,      # segundos extras (margem de cronograma)
	"reliability": 50.0,    # 0..100
	"comms": 50.0,          # 0..100 (qualidade do enlace)
	"risk": 30.0,           # 0..100 (30 = jogo antigo)
	"parts": 0.0,           # pecas reserva
	"science": 50.0,        # capacidade cientifica 0..100
}

const PARAM_NAMES := {
	"credits": "créditos", "mass": "massa", "mass_cap": "capacidade do foguete", "energy_mult": "consumo de energia",
	"fuel": "combustível", "time_bonus": "s de margem", "reliability": "confiabilidade", "comms": "comunicação",
	"risk": "risco", "parts": "peças reserva", "science": "capacidade científica",
}

const RISKS := {
	"thermal": {"name": "Superaquecimento do reator", "kind": "reactor", "fx": {"parts": 1.0, "reliability": 5.0, "risk": -4.0}},
	"comms": {"name": "Perda de comunicação", "kind": "comm", "fx": {"comms": 10.0, "risk": -4.0}},
	"nav": {"name": "Rota de colisão", "kind": "asteroid", "fx": {"fuel": 0.0, "risk": -4.0}},
}
const MITIGATE_COST := 12.0

## Cada CML: titulo, o que se faz, como passa. As opcoes ficam nas funcoes _cmlN.
const CML_INFO := [
	{"title": "CML 1 - Guardanapo (Cocktail Napkin)", "goal": "Definir o problema científico e o objetivo principal.", "pass": "Um objetivo escolhido."},
	{"title": "CML 2 - Viabilidade inicial", "goal": "Ver se a missão é possível: escolher o foguete (capacidade x custo).", "pass": "Foguete escolhido dentro do orçamento."},
	{"title": "CML 3 - Espaço de trocas (Trade Space)", "goal": "Comparar alternativas de energia e de estrutura da nave.", "pass": "Uma alternativa por categoria."},
	{"title": "CML 4 - Projeto pontual (Point Design)", "goal": "Escolher o kit de instrumentos e as peças reserva.", "pass": "Um kit escolhido."},
	{"title": "CML 5 - Conceito base (Baseline)", "goal": "Definir orçamento de reserva e margem de cronograma.", "pass": "Política de reserva escolhida."},
	{"title": "CML 6 - Conceito integrado", "goal": "Achar inconsistências entre os subsistemas e decidir: corrigir ou assumir o risco.", "pass": "Cada inconsistência corrigida ou assumida."},
	{"title": "CML 7 - Linha de base preliminar", "goal": "Identificar riscos e decidir quais mitigar. O que ficar sem mitigação vai acontecer mais no voo.", "pass": "Análise de riscos concluída."},
	{"title": "CML 8 - PDR (Revisão preliminar de projeto)", "goal": "Verificar os requisitos do projeto.", "pass": "Todos os requisitos atendidos (ou dispensados com risco)."},
	{"title": "CML 9 - CDR (Revisão crítica de projeto)", "goal": "Validar o projeto final e autorizar o lançamento.", "pass": "Lançamento autorizado."},
]

# ---- estado (replicado para o cliente, ver SYNC em net.gd) ----
var planned := false
var objective := ""
var cml_done := 0
var params: Dictionary = DEFAULTS.duplicate()
var decisions: Array = []        # [{cml, label, fx}]
var accepted_risks: Array = []   # ids de RISKS nao mitigados no CML 7
var mitigated: Array = []
var log: Array = []              # eventos da missao: [{kind, tag, label, cause, ok, outcome}]
var stats: Dictionary = {}
var report: Dictionary = {}      # {text, score, grade} depois do retorno

# ---- so locais (nao replicados) ----
var planning_disabled := false   # testes e modo rapido: nao abre o planejamento
var auto_mode := false           # testes: responde sem interface
var auto_picks: Array = []


func reset() -> void:
	planned = false
	objective = ""
	cml_done = 0
	params = DEFAULTS.duplicate()
	decisions = []
	accepted_risks = []
	mitigated = []
	log = []
	stats = {}
	report = {}
	changed.emit()


func p(key: String) -> float:
	return float(params.get(key, DEFAULTS.get(key, 0.0)))


# ============================ efeitos no voo ============================
## Chamado por Voyage.start(): massa, combustivel, consumo e margem de tempo vindos do projeto.
func apply_to_voyage() -> void:
	Voyage.mass = p("mass")
	Voyage.fuel = clampf(p("fuel"), 0.0, 100.0)
	Voyage.energy_mult *= p("energy_mult")
	Voyage.time_left += p("time_bonus")


## Chance de haver evento a cada sorteio (0.15 com risco 30, igual ao jogo antigo).
func event_chance() -> float:
	return clampf(0.15 * (0.5 + p("risk") / 60.0), 0.05, 0.4)


func event_weights() -> Dictionary:
	var w := {"comm": 1.0, "asteroid": 1.0, "reactor": 1.0}
	for id in accepted_risks:
		if RISKS.has(id):
			w[RISKS[id]["kind"]] += 1.5
	return w


func pick_event_kind() -> String:
	if accepted_risks.is_empty():
		return String(Voyage.KINDS.pick_random())
	var w := event_weights()
	var total := 0.0
	for k in w:
		total += w[k]
	var r := randf() * total
	for k in w:
		r -= w[k]
		if r <= 0.0:
			return String(k)
	return String(Voyage.KINDS.pick_random())


## Por que o evento aconteceu (para o relatorio). Vazio se foi so sorte.
func cause_for(kind: String) -> String:
	for id in accepted_risks:
		if RISKS.has(id) and RISKS[id]["kind"] == kind:
			return tr("No CML 7 vocês aceitaram o risco: %s.") % tr(RISKS[id]["name"])
	return ""


func blackout_mult() -> float:
	return clampf(1.5 - p("comms") / 100.0, 0.6, 1.2)


## Gasta uma peca reserva (CML 4) em um reparo. Devolve true se havia peca.
func use_part(what: String) -> bool:
	if p("parts") < 1.0:
		return false
	params["parts"] = p("parts") - 1.0
	stat_inc("parts_used")
	stats["part_used_for"] = what
	changed.emit()
	return true


# ============================ registro de eventos ============================
func log_event(kind: String, tag: String, label: String, cause: String = "") -> void:
	log.append({"kind": kind, "tag": tag, "label": label, "cause": cause, "ok": null, "outcome": ""})
	changed.emit()


func set_outcome(kind: String, ok: bool, text: String = "") -> void:
	for i in range(log.size() - 1, -1, -1):
		if log[i]["kind"] == kind and log[i]["ok"] == null:
			log[i]["ok"] = ok
			log[i]["outcome"] = text
			break
	changed.emit()


func stat_inc(key: String) -> void:
	stats[key] = int(stats.get(key, 0)) + 1


func stat_set(key: String, value: Variant) -> void:
	stats[key] = value


# ============================ planejamento (CML 1..9) ============================
func _auto() -> bool:
	return auto_mode


func _ask(options: Array, title: String) -> int:
	if _auto():
		var v: int = int(auto_picks.pop_front()) if not auto_picks.is_empty() else 0
		return clampi(v, 0, options.size() - 1)
	return await UI.choose(options, title)


func _say(lines: Variant) -> void:
	if _auto():
		return
	await UI.say(lines)


func _can_afford(fx: Dictionary) -> bool:
	return p("credits") + float(fx.get("credits", 0.0)) >= 0.0


func _fx_text(fx: Dictionary) -> String:
	var parts: Array[String] = []
	for k in fx:
		if k == "set":
			continue
		var v: float = float(fx[k])
		if v == 0.0:
			continue
		if k == "energy_mult":
			parts.append("%+d%% %s" % [int(round(v * 100.0)), tr(PARAM_NAMES[k])])
		else:
			parts.append("%+d %s" % [int(round(v)), tr(PARAM_NAMES.get(k, k))])
	return ", ".join(parts) if not parts.is_empty() else tr("sem efeito direto")


func apply_fx(fx: Dictionary) -> void:
	for k in fx:
		if k == "set":
			for sk in fx["set"]:
				if sk == "objective":
					objective = String(fx["set"][sk])
				else:
					params[sk] = fx["set"][sk]
			continue
		params[k] = p(k) + float(fx[k])
	for k in ["reliability", "comms", "risk", "science", "fuel"]:
		params[k] = clampf(p(k), 0.0, 100.0)
	params["credits"] = maxf(0.0, p("credits"))
	params["parts"] = maxf(0.0, p("parts"))
	params["energy_mult"] = maxf(0.5, p("energy_mult"))
	changed.emit()


## Mostra as alternativas (com custo/efeito) e devolve a escolhida; os efeitos ja foram aplicados.
func _choose_option(cml: int, title: String, opts: Array) -> Dictionary:
	var lines: Array = []
	for o in opts:
		lines.append("%s: %s [%s]" % [tr(o["label"]), tr(o["desc"]), _fx_text(o["fx"])])
	await _say(lines)
	var chosen: Dictionary = {}
	while chosen.is_empty():
		var labels: Array = []
		for o in opts:
			labels.append(tr(o["label"]))
		var i: int = await _ask(labels, title)
		if i < 0:
			continue
		var o: Dictionary = opts[i]
		if not _can_afford(o["fx"]):
			if _auto():
				for alt in opts:
					if _can_afford(alt["fx"]):
						o = alt
						break
			else:
				await _say(tr("Créditos insuficientes para esta opção."))
				continue
		chosen = o
	apply_fx(chosen["fx"])
	decisions.append({"cml": cml, "label": chosen["label"], "fx": chosen["fx"].duplicate(true)})
	return chosen


func _intro(n: int) -> void:
	var info: Dictionary = CML_INFO[n - 1]
	await _say([tr(info["title"]), tr("Objetivo: ") + tr(info["goal"]), tr("Para passar: ") + tr(info["pass"]) + "  " + tr("Créditos: %d") % int(p("credits"))])


func _advance(n: int) -> void:
	cml_done = n
	changed.emit()


## Roda os 9 estagios. O host decide; o cliente (cientista) acompanha pelo estado espelhado.
func run_planning() -> void:
	var pick: int = await _ask([tr("Planejar a missão (CML 1 a 9)"), tr("Missão rápida (plano padrão)")], tr("Antes do lançamento"))
	if pick != 0:
		planned = true
		cml_done = 9
		decisions.append({"cml": 0, "label": "Plano padrão (sem planejamento)", "fx": {}})
		changed.emit()
		return
	await _say([tr("Nesta fase vocês projetam a missão na Terra. Cada decisão muda a nave e o que acontece no voo."), tr("Os 9 estágios CML medem a maturidade de uma missão: de uma ideia no guardanapo até o projeto pronto para construir.")])
	await _cml1()
	await _cml2()
	await _cml3()
	await _cml4()
	await _cml5()
	await _cml6()
	await _cml7()
	await _cml8()
	await _cml9()


func _cml1() -> void:
	await _intro(1)
	await _choose_option(1, tr("Objetivo da missão"), [
		{"label": "Cultivar bionutrientes", "desc": "Testar fungos como fonte de alimento no espaço.", "fx": {"science": 10.0, "set": {"objective": "bio"}}},
		{"label": "Medir radiação cislunar", "desc": "Mapear a radiação fora da proteção da Terra.", "fx": {"science": 10.0, "risk": 5.0, "set": {"objective": "radiation"}}},
		{"label": "Testar comunicação óptica", "desc": "Provar um enlace de dados mais rápido.", "fx": {"science": 5.0, "comms": 15.0, "set": {"objective": "comms"}}},
	])
	_advance(1)


func _cml2() -> void:
	await _intro(2)
	await _say(tr("Um foguete maior carrega mais massa, mas custa mais. Se a nave passar da capacidade, a missão não é viável."))
	await _choose_option(2, tr("Escolha o foguete"), [
		{"label": "Foguete pequeno", "desc": "Barato, mas limita a massa da nave.", "fx": {"credits": -10.0, "set": {"mass_cap": 105.0}}},
		{"label": "Foguete médio", "desc": "Equilíbrio entre custo e capacidade.", "fx": {"credits": -25.0, "set": {"mass_cap": 115.0}}},
		{"label": "Foguete pesado", "desc": "Muita capacidade, orçamento pesado.", "fx": {"credits": -45.0, "set": {"mass_cap": 135.0}}},
	])
	_advance(2)


func _cml3() -> void:
	await _intro(3)
	await _choose_option(3, tr("Fonte de energia"), [
		{"label": "Painéis solares", "desc": "Leves e simples; dependem do Sol.", "fx": {"credits": -10.0, "energy_mult": -0.15, "mass": 5.0, "risk": 3.0}},
		{"label": "Gerador nuclear compacto", "desc": "Muita energia, caro e pesado.", "fx": {"credits": -25.0, "energy_mult": -0.25, "mass": 8.0, "reliability": 5.0}},
		{"label": "Só baterias", "desc": "Baratas, mas o consumo fica alto.", "fx": {"credits": -5.0, "energy_mult": 0.1}},
	])
	await _choose_option(3, tr("Estrutura da nave"), [
		{"label": "Casco leve", "desc": "Economiza massa, protege menos.", "fx": {"credits": -5.0, "mass": -8.0, "reliability": -10.0}},
		{"label": "Casco blindado", "desc": "Mais proteção e confiabilidade, mais massa.", "fx": {"credits": -15.0, "mass": 10.0, "reliability": 10.0, "risk": -10.0}},
	])
	_advance(3)


func _cml4() -> void:
	await _intro(4)
	await _choose_option(4, tr("Kit de instrumentos"), [
		{"label": "Kit científico completo", "desc": "Máxima ciência; divide banda de comunicação.", "fx": {"credits": -20.0, "science": 20.0, "mass": 5.0, "comms": -10.0}},
		{"label": "Kit equilibrado", "desc": "Boa ciência e uma peça reserva.", "fx": {"credits": -15.0, "science": 10.0, "parts": 1.0, "mass": 3.0}},
		{"label": "Kit básico + peças reserva", "desc": "Pouca ciência, duas peças para reparos.", "fx": {"credits": -10.0, "science": 5.0, "parts": 2.0}},
	])
	_advance(4)


func _cml5() -> void:
	await _intro(5)
	await _say(tr("Dinheiro de reserva e tempo de folga protegem a missão. Mas créditos não gastos viram pontos no final (até um teto)."))
	await _choose_option(5, tr("Política de reserva"), [
		{"label": "Reserva alta (20%)", "desc": "Mais folga no cronograma e menos risco.", "fx": {"credits": -15.0, "risk": -8.0, "time_bonus": 30.0}},
		{"label": "Reserva média (10%)", "desc": "Folga moderada.", "fx": {"credits": -7.0, "risk": -3.0, "time_bonus": 15.0}},
		{"label": "Sem reserva", "desc": "Guarda créditos, mas a missão fica frágil.", "fx": {"risk": 8.0}},
	])
	_advance(5)


## Inconsistencias do projeto atual (CML 6). Cada uma tem correcao (custa) e aceitar (risco).
func inconsistencies() -> Array:
	var out: Array = []
	if p("energy_mult") > 1.0:
		out.append({"id": "power", "text": "O consumo de energia previsto é maior que a geração.", "fix": {"credits": -8.0, "energy_mult": -0.15}})
	if p("science") >= 70.0 and p("comms") < 50.0:
		out.append({"id": "data", "text": "Os instrumentos vão gerar mais dados do que o enlace consegue transmitir.", "fix": {"credits": -8.0, "comms": 15.0}})
	if p("mass") > p("mass_cap"):
		out.append({"id": "mass", "text": "A massa da nave passa da capacidade do foguete.", "fix": {"credits": -8.0, "mass": -8.0}})
	return out


func _cml6() -> void:
	await _intro(6)
	var list := inconsistencies()
	if list.is_empty():
		await _say(tr("Revisão cruzada: nenhuma inconsistência encontrada. Bom trabalho! Bônus de 5 créditos."))
		apply_fx({"credits": 5.0})
		decisions.append({"cml": 6, "label": "Projeto consistente", "fx": {"credits": 5.0}})
		_advance(6)
		return
	for inc in list:
		await _say(tr("INCONSISTÊNCIA: ") + tr(inc["text"]))
		var fix_cost := " [%s]" % _fx_text(inc["fix"])
		var i: int = await _ask([tr("Corrigir") + fix_cost, tr("Assumir o risco (risco +6)")], tr("O que fazer?"))
		if i == 0 and _can_afford(inc["fix"]):
			apply_fx(inc["fix"])
			decisions.append({"cml": 6, "label": "Corrigiu: " + String(inc["text"]), "fx": inc["fix"].duplicate(true)})
		else:
			apply_fx({"risk": 6.0})
			stat_set("waived_" + String(inc["id"]), true)
			decisions.append({"cml": 6, "label": "Assumiu o risco: " + String(inc["text"]), "fx": {"risk": 6.0}})
	_advance(6)


func _cml7() -> void:
	await _intro(7)
	await _say([tr("Simulando a missão no papel... estes são os 3 maiores riscos."), tr("Cada mitigação custa %d créditos. O que ficar sem mitigação acontece com mais chance durante o voo.") % int(MITIGATE_COST)])
	mitigated = []
	while true:
		var labels: Array = []
		var ids: Array = []
		for id in RISKS:
			if mitigated.has(id):
				continue
			labels.append(tr("Mitigar: ") + tr(RISKS[id]["name"]) + " [-%d %s]" % [int(MITIGATE_COST), tr("créditos")])
			ids.append(id)
		labels.append(tr("Concluir análise de riscos"))
		var i: int = await _ask(labels, tr("Análise de riscos"))
		if i < 0 or i >= ids.size():
			break
		if not _can_afford({"credits": -MITIGATE_COST}):
			if _auto():
				break
			await _say(tr("Créditos insuficientes para esta opção."))
			continue
		var id: String = ids[i]
		mitigated.append(id)
		var fx: Dictionary = RISKS[id]["fx"].duplicate()
		fx["credits"] = -MITIGATE_COST
		apply_fx(fx)
		decisions.append({"cml": 7, "label": "Mitigou: " + String(RISKS[id]["name"]), "fx": fx})
	accepted_risks = []
	for id in RISKS:
		if not mitigated.has(id):
			accepted_risks.append(id)
	changed.emit()
	_advance(7)


func requirements() -> Array:
	return [
		{"id": "power", "text": "Energia: consumo dentro da geração", "ok": p("energy_mult") <= 1.0, "fix": {"credits": -6.0, "energy_mult": -0.15}},
		{"id": "mass", "text": "Massa dentro da capacidade do foguete", "ok": p("mass") <= p("mass_cap"), "fix": {"credits": -6.0, "mass": -8.0}},
		{"id": "reliability", "text": "Confiabilidade mínima (40)", "ok": p("reliability") >= 40.0, "fix": {"credits": -6.0, "reliability": 10.0}},
		{"id": "parts", "text": "Pelo menos 1 peça reserva", "ok": p("parts") >= 1.0, "fix": {"credits": -6.0, "parts": 1.0}},
	]


func _cml8() -> void:
	await _intro(8)
	var failing: Array = []
	var lines: Array = []
	for r in requirements():
		lines.append(("[OK] " if r["ok"] else "[FALHA] ") + tr(r["text"]))
		if not r["ok"]:
			failing.append(r)
	await _say(lines)
	if failing.is_empty():
		await _say(tr("PDR aprovado sem pendências."))
		decisions.append({"cml": 8, "label": "PDR aprovado", "fx": {}})
		_advance(8)
		return
	var total_fix := 0.0
	for r in failing:
		total_fix += absf(float(r["fix"]["credits"]))
	var opts := [tr("Pedir ajuste do projeto (-%d créditos)") % int(total_fix), tr("Aprovar com dispensa (risco +%d)") % (8 * failing.size())]
	var i: int = await _ask(opts, tr("Decisão da banca"))
	if i == 0 and p("credits") >= total_fix:
		for r in failing:
			apply_fx(r["fix"])
		decisions.append({"cml": 8, "label": "Ajustou o projeto no PDR", "fx": {"credits": -total_fix}})
	else:
		apply_fx({"risk": 8.0 * failing.size()})
		stat_set("pdr_waiver", failing.size())
		decisions.append({"cml": 8, "label": "Aprovou com dispensa no PDR", "fx": {"risk": 8.0 * failing.size()}})
	_advance(8)


func summary_lines() -> Array:
	return [
		tr("Massa %d / capacidade %s") % [int(p("mass")), str(int(p("mass_cap"))) if p("mass_cap") < 900.0 else "-"],
		tr("Consumo de energia: %d%%   Confiabilidade: %d   Comunicação: %d") % [int(p("energy_mult") * 100.0), int(p("reliability")), int(p("comms"))],
		tr("Ciência: %d   Peças: %d   Risco: %d   Créditos: %d") % [int(p("science")), int(p("parts")), int(p("risk")), int(p("credits"))],
	]


func _cml9() -> void:
	await _intro(9)
	await _say(summary_lines())
	await _ask([tr("Autorizar o lançamento")], tr("CDR: decisão final"))
	decisions.append({"cml": 9, "label": "Lançamento autorizado", "fx": {}})
	planned = true
	_advance(9)
	await _say(tr("Lançamento autorizado! Três tripulantes embarcam; a base na Terra acompanha."))


# ============================ retorno e relatorio ============================
func systems_lines() -> Array:
	return [
		tr("Energia: %d%%   Combustível: %d%%") % [int(Voyage.energy), int(Voyage.fuel)],
		tr("Núcleo do reator: %d%%   Vida: %d%%") % [int(GameState.heat), int(GameState.health)],
		tr("Peças reserva: %d   Comunicação: %s") % [int(p("parts")), tr("estável") if Voyage.comms_ok() else tr("interferência")],
	]


## Fase 6: checklist, janela de retorno e reentrada. Termina gerando o relatorio.
func run_return() -> void:
	await _say([tr("RETORNO À TERRA"), tr("Primeiro, a verificação dos sistemas.")] + systems_lines())
	var can_stay: bool = Voyage.fuel >= 40.0
	var win: int = await _ask([tr("Partir agora (mais margem)"), tr("Ficar mais um pouco para coletar dados")], tr("Janela de retorno"))
	if win == 1 and can_stay:
		Voyage.fuel = maxf(0.0, Voyage.fuel - 15.0)
		apply_fx({"science": 8.0, "risk": 5.0})
		stat_set("stayed", true)
		decisions.append({"cml": 10, "label": "Ficou para coletar mais dados", "fx": {"science": 8.0, "risk": 5.0, "fuel": -15.0}})
		await _say(tr("Mais dados coletados. Combustível -15."))
	else:
		if win == 1:
			await _say(tr("Combustível insuficiente para esperar. A tripulação parte agora."))
		decisions.append({"cml": 10, "label": "Partiu na janela", "fx": {}})
	var angles := [tr("Ângulo raso"), tr("Ângulo nominal"), tr("Ângulo íngreme")]
	var correct := randi() % 3
	var hint := p("comms") >= 50.0 and Voyage.comms_ok()
	if hint:
		await _say(tr("A base orienta: use o %s.") % angles[correct].to_lower())
	else:
		await _say(tr("Sem enlace estável com a base: a reentrada será feita sem orientação."))
	var pick: int = await _ask(angles, tr("Reentrada"))
	stat_set("reentry_hint", hint)
	if pick == correct:
		stat_set("reentry_ok", true)
		await _say(tr("Reentrada perfeita! A cápsula pousa em segurança."))
	else:
		stat_set("reentry_ok", false)
		var dmg := 10.0 if p("reliability") >= 60.0 else 25.0
		GameState.apply_effects({"health": -dmg})
		await _say(tr("Ângulo errado! A tripulação sofre uma reentrada dura: vida -%d.") % int(dmg))
	Missions.complete("retorno")
	finish_report()
	if not _auto():
		await UI.show_panel(String(report["text"]))
		var c: int = await UI.choose([tr("Continuar explorando"), tr("Voltar ao menu inicial")], tr("Missão concluída"))
		if c == 1:
			GameState.running = false
			GameState.reset()
			if Net.is_online():
				Net.leave()
			get_tree().change_scene_to_file("res://scenes/start_menu.tscn")


func _score_science() -> float:
	var s := p("science") * 0.5
	if Missions.finished.has("bionutrientes"):
		s += 25.0
	if bool(stats.get("cme_safe", false)):
		s += 25.0
	return clampf(s, 0.0, 100.0)


func _score_ship() -> float:
	return clampf((GameState.health + (100.0 - GameState.heat) + Voyage.energy + Voyage.fuel) / 4.0, 0.0, 100.0)


func _score_decisions() -> float:
	var n := 0
	var ok := 0
	for e in log:
		if e["ok"] != null:
			n += 1
			if e["ok"]:
				ok += 1
	return 70.0 if n == 0 else float(ok) / float(n) * 100.0


func _score_efficiency() -> float:
	if not Voyage.ROUTES.has(Voyage.route):
		return 50.0
	var limit: float = Voyage.ROUTES[Voyage.route]["limit"] + p("time_bonus")
	return clampf(Voyage.time_left / limit * 200.0, 0.0, 100.0)


func _score_budget() -> float:
	return clampf(minf(p("credits"), 30.0) / 30.0 * 100.0, 0.0, 100.0)


func _score_coop() -> float:
	return clampf(float(stats.get("base_actions", 0)) * 20.0, 0.0, 100.0)


func grade_for(score: float) -> String:
	if score >= 85.0:
		return "A"
	if score >= 70.0:
		return "B"
	if score >= 55.0:
		return "C"
	if score >= 40.0:
		return "D"
	return "E"


## Ligacoes causa -> consequencia (do planejamento ao voo) para o relatorio.
func causal_lines() -> Array:
	var out: Array = []
	for e in log:
		if String(e["cause"]) != "":
			out.append(tr("%s: %s") % [tr(Voyage.KIND_NAMES.get(e["kind"], e["kind"])), e["cause"]])
	for id in mitigated:
		for e in log:
			if e["kind"] == RISKS[id]["kind"]:
				out.append(tr("A mitigação de \"%s\" (CML 7) ajudou: o evento aconteceu com menos chance.") % tr(RISKS[id]["name"]))
				break
	if int(stats.get("parts_used", 0)) > 0:
		out.append(tr("A peça reserva (CML 4) amorteceu o superaquecimento do reator."))
	for k in ["mass", "power", "data"]:
		if bool(stats.get("waived_" + k, false)):
			out.append(tr("Uma inconsistência do CML 6 foi assumida como risco: o risco da missão subiu."))
			break
	if int(stats.get("pdr_waiver", 0)) > 0:
		out.append(tr("O PDR foi aprovado com dispensa: requisitos não cumpridos aumentaram o risco."))
	if stats.has("reentry_hint"):
		if bool(stats["reentry_hint"]):
			out.append(tr("A boa comunicação (CML 3/5) deu a dica certa na reentrada."))
		else:
			out.append(tr("Sem enlace estável, a reentrada foi sem orientação."))
	return out.slice(0, 6)


func build_report() -> Dictionary:
	var sci := _score_science()
	var ship := _score_ship()
	var dec := _score_decisions()
	var eff := _score_efficiency()
	var bud := _score_budget()
	var coop := _score_coop()
	var has_coop := Net.has_partner() or int(stats.get("base_actions", 0)) > 0
	var total := sci * 0.30 + ship * 0.20 + dec * 0.15 + eff * 0.10 + bud * 0.10
	var weight := 0.85
	if has_coop:
		total += coop * 0.15
		weight += 0.15
	total = clampf(total / weight, 0.0, 100.0)
	var grade := grade_for(total)
	var names := {"bio": "Cultivar bionutrientes", "radiation": "Medir radiação cislunar", "comms": "Testar comunicação óptica"}
	var lines: Array[String] = []
	lines.append(tr("RELATÓRIO PÓS-MISSÃO"))
	lines.append("")
	lines.append(tr("Objetivo: ") + (tr(names[objective]) if names.has(objective) else tr("plano padrão")))
	lines.append(tr("Nota final: %s (%d/100)") % [grade, int(round(total))])
	lines.append("")
	lines.append(tr("Ciência %d   Nave %d   Decisões %d") % [int(sci), int(ship), int(dec)])
	lines.append(tr("Eficiência %d   Orçamento %d (sobraram %d créditos)") % [int(eff), int(bud), int(p("credits"))])
	if has_coop:
		lines.append(tr("Cooperação com a base: %d (ações da base: %d)") % [int(coop), int(stats.get("base_actions", 0))])
	lines.append("")
	lines.append(tr("EVENTOS DA MISSÃO"))
	if log.is_empty():
		lines.append(tr("Nenhum evento relevante."))
	for e in log:
		var res := ""
		if e["ok"] != null:
			res = tr(" - superado") if e["ok"] else tr(" - falhou")
		lines.append("[%s] %s%s" % [e["tag"], tr(e["label"]), res])
	lines.append("")
	lines.append(tr("SELOS: REAL = registro científico real; RISCO = fenômeno real, ocorrência simulada; FICT = desafio fictício do jogo."))
	var causal := causal_lines()
	if not causal.is_empty():
		lines.append("")
		lines.append(tr("O QUE SUAS DECISÕES CAUSARAM"))
		for c in causal:
			lines.append("- " + String(c))
	lines.append("")
	lines.append(tr("DECISÕES DO PLANEJAMENTO"))
	for d in decisions:
		lines.append("CML %d: %s" % [int(d["cml"]), tr(d["label"])])
	return {"text": "\n".join(lines), "score": total, "grade": grade}


func finish_report() -> void:
	report = build_report()
	changed.emit()
	var f := FileAccess.open("user://last_report.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"report": report, "params": params, "decisions": decisions, "events": log, "stats": stats}, "\t"))
		f.close()
