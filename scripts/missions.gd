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
			{"id": "veredito", "side": "TERRA", "text": "Base: analisar a amostra, conferir a coloração e dar o veredito (painel do laboratório; tecla 1)"},
			{"id": "retirar", "side": "ESPAÇO", "text": "Retirar a amostra na cápsula (armazém) e ler o resultado da base"},
		],
	},
}

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
			GameState.notice.emit("Os pacotes terminaram de aquecer!")
			changed.emit()


# ============================ missao atual ============================
func start(id: String) -> void:
	if not DEFS.has(id):
		return
	active = id
	step = 0
	GameState.notice.emit("Nova missão: %s" % DEFS[id]["title"])
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
		GameState.notice.emit("Missão concluída: %s" % DEFS[active]["title"])
		active = ""
		step = 0
	else:
		GameState.notice.emit("Missão atualizada: %s" % steps[step]["text"])
	changed.emit()


func tracker_text() -> String:
	if active == "":
		return ""
	var s: Dictionary = DEFS[active]["steps"][step]
	return "[%s] %s" % [s["side"], s["text"]]


# ============================ missao 1: amostra e veredito ============================
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
		result_lines = ["A base analisou a amostra.", "Resultado: SUCESSO.", "Os efeitos aparecerão na próxima missão."]
	else:
		result_lines = ["A base analisou a amostra.", "Resultado: FALHA.", "A pesquisa gastou mais energia e ocupou mais dados armazenados."]
	return ["Veredito registrado: %s." % ("SUCESSO" if says_success else "FALHA"), "A amostra volta para a nave pela cápsula; o astronauta lê o resultado ao retirá-la."]


## Mensagem da base (sucesso/falha) mostrada ao retirar a amostra; conclui a ultima etapa.
func take_result() -> Array:
	var out := result_lines
	result_lines = []
	complete("retirar")
	return out


## Efeitos visiveis para a proxima missao (o risco escondido nao aparece).
func effects_lines() -> Array[String]:
	var names := {
		"nave_leve": "Massa da nave menor",
		"menos_energia": "Menor consumo de energia",
		"mais_tempo": "Mais tempo limite na missão",
		"energia_extra": "Maior consumo de energia (pesquisa que falhou)",
		"dados_extra": "Mais dados armazenados (pesquisa que falhou)",
	}
	var out: Array[String] = []
	for k in flags:
		if names.has(k):
			out.append(names[k])
	return out


# ============================ texto do menu de missoes ============================
func summary_text() -> String:
	var lines: Array[String] = ["MISSÕES", ""]
	if active != "":
		lines.append("Missão atual: " + DEFS[active]["title"])
		var steps: Array = DEFS[active]["steps"]
		for i in steps.size():
			var s: Dictionary = steps[i]
			var mark := "[x]" if i < step else ("[>]" if i == step else "[ ]")
			lines.append(" %s %s (%s)" % [mark, s["text"], s["side"]])
	else:
		lines.append("Nenhuma missão ativa.")
	if not finished.is_empty():
		lines.append("")
		lines.append("Concluídas:")
		for id in finished:
			lines.append(" - " + DEFS[id]["title"])
		var fx := effects_lines()
		lines.append("Efeitos para a próxima missão: " + (", ".join(fx) if not fx.is_empty() else "nenhum"))
	lines.append("")
	lines.append("Eventos possíveis (em desenvolvimento): " + ", ".join(EVENTS))
	lines.append("")
	lines.append("F / Esc / M: fechar")
	return "\n".join(lines)
