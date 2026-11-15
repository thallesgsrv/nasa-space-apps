extends Node
## Sistema de missoes (autoload "Missions"): missao atual, etapas, estado das estacoes da
## missao 1 (aquecedor, amostra) e efeitos que valem para a PROXIMA missao.
## Textos, tempos e chances sao PLACEHOLDERS baseados no documento de design; ajuste aqui.

signal changed

const HEAT_TIME := 10.0   # segundos para aquecer os pacotes
const SPIN_TIME := 4.0    # segundos para centrifugar
const SUCCESS_CHANCE := 0.5

const COLORS_OK := ["Azul", "Verde"]        # coloracoes que indicam sucesso (a base conhece)
const COLORS_FAIL := ["Marrom", "Amarelo"]  # coloracoes que indicam falha

## lado: "ESPAÇO" (astronauta) ou "TERRA" (cientista da base)
const DEFS := {
	"bionutrientes": {
		"title": "Testar e coletar bionutrientes",
		"steps": [
			{"id": "pacotes", "side": "ESPAÇO", "text": "Pegar o pacote de cultura de fungos (armazém, estante de cima)"},
			{"id": "aquecer", "side": "ESPAÇO", "text": "Aquecer o pacote na máquina de aquecimento (armazém, containers azuis à direita)"},
			{"id": "centrifugar", "side": "ESPAÇO", "text": "Esvaziar e centrifugar (sala de controle, máquinas do canto esquerdo)"},
			{"id": "enviar", "side": "ESPAÇO", "text": "Enviar a amostra à base pela cápsula (armazém, cilindro do canto direito)"},
			{"id": "veredito", "side": "TERRA", "text": "Base: analisar o fungo na mesa do microscópio (placa de Petri) e dar o veredito no painel (laboratório; tecla 1)"},
			{"id": "retirar", "side": "ESPAÇO", "text": "Retirar a amostra na cápsula (armazém) e ler o resultado da base"},
		],
	},
	"cme": {
		"title": "Alerta de Ejeção de Massa Coronal (CME)",
		"steps": [
			{"id": "solar", "side": "TERRA", "text": "Base: monitorar o terminal solar, conferir o manual e decidir entre alertar ou ignorar (painel do laboratório; tecla 1)"},
			{"id": "escudos", "side": "ESPAÇO", "text": "Se houver alerta: correr ao controle de energia (sala do reator) e ativar os escudos antes da onda chegar"},
		],
	},
	"viagem": {
		"title": "Viagem até a rota escolhida",
		"steps": [
			{"id": "rota", "side": "ESPAÇO", "text": "Escolher a rota e iniciar a viagem (cadeira de comando, sala de controle)"},
			{"id": "viajar", "side": "EQUIPE", "text": "Chegar ao destino: a base prevê os perigos e a nave faz as manobras (veja o painel da viagem)"},
		],
	},
}

const ORDER := ["bionutrientes", "viagem", "cme"]   # as missoes comecam nesta ordem

## Eventos do documento de design (ainda sem minigames; so listados no menu).
const EVENTS := [
	"Interferência na comunicação",
	"Rota de colisão com asteroides",
	"Controle térmico do reator",
]

var active := ""
var step := 0
var finished: Array[String] = []
var flags: Dictionary = {}     # efeitos para a proxima missao (ver verdict())

# estado das estacoes da missao 1
var heater_state := "idle"     # idle | heating | ready
var heating_left := 0.0
var analyzed := false
var data_sent := false
var sample_color := ""
var sample_ok := false
var result_lines: Array = []   # mensagem da base, mostrada ao RETIRAR a amostra na capsula


func reset() -> void:
	active = ""
	step = 0
	finished.clear()
	flags.clear()
	heater_state = "idle"
	heating_left = 0.0
	analyzed = false
	data_sent = false
	sample_color = ""
	sample_ok = false
	result_lines = []
	changed.emit()


func _process(delta: float) -> void:
	if heater_state == "heating" and GameState.running:
		heating_left -= delta
		if heating_left <= 0.0:
			heating_left = 0.0
			heater_state = "ready"
			GameState.notice.emit(tr("Os pacotes terminaram de aquecer!"))
			changed.emit()


# ============================ missao atual ============================
func start(id: String) -> void:
	if not DEFS.has(id):
		return
	active = id
	step = 0
	if id == "cme":
		Solar.generate()
	GameState.notice.emit(tr("Nova missão: %s") % tr(DEFS[id]["title"]))
	changed.emit()


func current_step_id() -> String:
	if active == "":
		return ""
	return DEFS[active]["steps"][step]["id"]


func is_step(id: String) -> bool:
	return current_step_id() == id


## Conclui a etapa atual se for a indicada (ignora chamadas fora de ordem).
func complete(id: String) -> void:
	if not is_step(id):
		return
	var steps: Array = DEFS[active]["steps"]
	step += 1
	if step >= steps.size():
		finished.append(active)
		GameState.notice.emit(tr("Missão concluída: %s") % tr(DEFS[active]["title"]))
		active = ""
		step = 0
		for next_id in ORDER:           # a proxima missao comeca sozinha
			if not finished.has(next_id):
				start(next_id)
				break
	else:
		GameState.notice.emit(tr("Missão atualizada: %s") % tr(steps[step]["text"]))
	changed.emit()


## Onde esta o objetivo atual: sala e acao do objeto (usado para guiar com o "!" azul).
func current_target() -> Dictionary:
	match current_step_id():
		"pacotes":
			return {"room": "armazem", "action": "mission_pacotes"}
		"aquecer":
			return {"room": "armazem", "action": "aquecedor"}
		"centrifugar":
			return {"room": "sala_controle", "action": "centrifuga"}
		"enviar", "retirar":
			return {"room": "armazem", "action": "capsula"}
		"veredito":
			if not analyzed:
				return {"room": "laboratorio", "action": "mesa_analise"}
			return {"room": "laboratorio", "action": "painel_base"}
		"rota":
			return {"room": "sala_controle", "action": "assento"}
		"solar":
			return {"room": "laboratorio", "action": "painel_base"}
		"escudos":
			if Solar.alert_sent and not Solar.resolved:
				return {"room": "sala_reator", "action": "escudos"}
	return {}


func tracker_text() -> String:
	if active == "":
		return ""
	var s: Dictionary = DEFS[active]["steps"][step]
	return "[%s] %s" % [tr(s["side"]), tr(s["text"])]


# ============================ missao 1: amostra e veredito ============================
## Nomes das coloracoes (traduzidos) para mostrar ao jogador.
func color_list(ok: bool) -> String:
	return ", ".join((COLORS_OK if ok else COLORS_FAIL).map(func(c): return tr(c)))


func color_name() -> String:
	return tr(sample_color)


func analyze_sample() -> String:
	sample_ok = randf() < SUCCESS_CHANCE
	sample_color = (COLORS_OK if sample_ok else COLORS_FAIL).pick_random()
	analyzed = true
	changed.emit()
	return sample_color


func send_data() -> void:
	data_sent = true
	complete("enviar")


## A analise e feita pela BASE (analyze_sample no painel do laboratorio), nao pelo astronauta.
## Veredito da base. Devolve linhas de texto para mostrar ao jogador.
## Regras do documento: falha -> mais energia/dados gastos, sem efeito posterior;
## sucesso real -> proxima missao melhor; sucesso declarado sobre falha real -> risco (hidden).
func verdict(says_success: bool) -> Array:
	flags.clear()
	if says_success:
		if sample_ok:
			flags["nave_leve"] = true
			flags["menos_energia"] = true
			flags["mais_tempo"] = true
		else:
			flags["envenenamento"] = true   # consequencia escondida da decisao errada
	else:
		flags["energia_extra"] = true
		flags["dados_extra"] = true
	complete("veredito")
	GameState.release_capsule()   # a amostra volta para a capsula depois do OK da base
	if says_success:
		result_lines = [tr("A base analisou a amostra."), tr("Resultado: SUCESSO."), tr("Os efeitos aparecerão na próxima missão.")]
	else:
		result_lines = [tr("A base analisou a amostra."), tr("Resultado: FALHA."), tr("A pesquisa gastou mais energia e ocupou mais dados armazenados.")]
	return [tr("Veredito registrado: %s.") % (tr("SUCESSO") if says_success else tr("FALHA")), tr("A amostra volta para a nave pela cápsula; o astronauta lê o resultado ao retirá-la.")]


## Mensagem da base (sucesso/falha) mostrada ao retirar a amostra; conclui a ultima etapa.
func take_result() -> Array:
	var out := result_lines
	result_lines = []
	complete("retirar")
	return out


## O astronauta come a amostra. Se ela estava em estado de FALHA (mesmo que a base tenha dito
## sucesso), ele passa mal e perde 50% da vida ATUAL. Se estava boa, ganha um pouco de comida.
func eat_sample() -> Array:
	if sample_ok:
		GameState.apply_effects({"food": 20.0})
		return [tr("Você comeu a amostra."), tr("Estava boa! Comida +20.")]
	var dmg := GameState.health * 0.5
	GameState.apply_effects({"health": -dmg})
	return [tr("Você comeu a amostra."), tr("Estava estragada! Você passou muito mal e perdeu %d de vida (50%% da vida atual).") % int(round(dmg))]


## Efeitos visiveis para a proxima missao (o risco escondido nao aparece).
func effects_lines() -> Array[String]:
	var names := {
		"nave_leve": tr("Massa da nave menor"),
		"menos_energia": tr("Menor consumo de energia"),
		"mais_tempo": tr("Mais tempo limite na missão"),
		"energia_extra": tr("Maior consumo de energia (pesquisa que falhou)"),
		"dados_extra": tr("Mais dados armazenados (pesquisa que falhou)"),
	}
	var out: Array[String] = []
	for k in flags:
		if names.has(k):
			out.append(names[k])
	return out


# ============================ texto do menu de missoes ============================
func summary_text() -> String:
	var lines: Array[String] = [tr("MISSÕES"), ""]
	if active != "":
		lines.append(tr("Missão atual: ") + tr(DEFS[active]["title"]))
		var steps: Array = DEFS[active]["steps"]
		for i in steps.size():
			var s: Dictionary = steps[i]
			var mark := "[x]" if i < step else ("[>]" if i == step else "[ ]")
			lines.append(" %s %s (%s)" % [mark, tr(s["text"]), tr(s["side"])])
	else:
		lines.append(tr("Nenhuma missão ativa."))
	if not finished.is_empty():
		lines.append("")
		lines.append(tr("Concluídas:"))
		for id in finished:
			lines.append(" - " + tr(DEFS[id]["title"]))
		var fx := effects_lines()
		lines.append(tr("Efeitos para a próxima missão: ") + (", ".join(fx) if not fx.is_empty() else tr("nenhum")))
	lines.append("")
	lines.append(tr("Eventos possíveis (em desenvolvimento): ") + ", ".join(EVENTS.map(func(e): return tr(e))))
	lines.append("")
	lines.append(tr("F / Esc / M: fechar"))
	return "\n".join(lines)
