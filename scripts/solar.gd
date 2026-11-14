extends Node
## Missao 3: Alerta de Ejecao de Massa Coronal (CME) (autoload "Solar").
## A BASE (Terra) monitora o terminal solar, confere o manual de limite seguro e decide alertar ou ignorar.
## Se alertar, a nave recebe um alarme com contagem regressiva e o ASTRONAUTA precisa ativar os escudos
## no controle de energia (sala do reator) antes da onda chegar.
## Valores sao PLACEHOLDERS (ajuste aqui).

signal changed

const CME_COUNTDOWN := 20.0   # segundos do alarme ate a onda chegar
const HIT_FLUX := 6.0         # raios-X a partir de onde a tempestade e perigosa
const HIT_ANGLE := 20.0       # angulo maximo (graus, para os dois lados) que atinge a rota da nave
const INVERT_TIME := 8.0      # controles invertidos / tela piscando apos ser atingido

var real := false             # a tempestade realmente atinge a nave?
var base_flux := 0.0
var base_angle := 0.0
var decided := false
var alert_sent := false
var countdown := 0.0
var shield_on := false
var resolved := false
var inverted_left := 0.0
var last_result := ""

var _t := 0.0


func reset() -> void:
	real = false
	base_flux = 0.0
	base_angle = 0.0
	decided = false
	alert_sent = false
	countdown = 0.0
	shield_on = false
	resolved = false
	inverted_left = 0.0
	last_result = ""
	changed.emit()


## Cria a CME desta missao (chamado quando a missao comeca).
func generate() -> void:
	reset()
	if randf() < 0.5:   # tempestade que realmente atinge a nave
		base_flux = randf_range(6.5, 9.5)
		base_angle = randf_range(-14.0, 14.0)
	elif randf() < 0.5: # fraca demais
		base_flux = randf_range(2.0, 5.0)
		base_angle = randf_range(-15.0, 15.0)
	else:               # forte, mas apontada para longe
		base_flux = randf_range(6.5, 9.5)
		base_angle = (1.0 if randf() < 0.5 else -1.0) * randf_range(30.0, 70.0)
	real = base_flux >= HIT_FLUX and absf(base_angle) <= HIT_ANGLE
	changed.emit()


func live_flux() -> float:
	return base_flux + sin(_t * 1.7) * 0.25


func live_angle() -> float:
	return base_angle + sin(_t * 0.9) * 1.5


func _process(delta: float) -> void:
	_t += delta
	if inverted_left > 0.0 and (not UI.busy or UI.realtime):
		inverted_left = maxf(0.0, inverted_left - delta)
	if alert_sent and not resolved and (not UI.busy or UI.realtime):
		countdown -= delta
		if countdown <= 0.0:
			countdown = 0.0
			_resolve()
		else:
			changed.emit()


## Texto do terminal solar (a UI chama de novo varias vezes por segundo: "tempo real").
func terminal_text() -> String:
	var lines: Array[String] = [tr("TERMINAL SOLAR - CME"), ""]
	lines.append(tr("Fluxo de raios-X:      %.1f") % live_flux())
	lines.append(tr("Ângulo da trajetória:  %+.0f graus  (0 = direto na rota da nave)") % live_angle())
	lines.append("")
	lines.append(tr("MANUAL DE LIMITE SEGURO"))
	lines.append(tr("A tempestade atinge a nave se o fluxo for MAIOR OU IGUAL a %.1f") % HIT_FLUX)
	lines.append(tr("E o ângulo estiver entre -%d e +%d graus.") % [int(HIT_ANGLE), int(HIT_ANGLE)])
	lines.append(tr("Fora disso, a ejeção passa longe ou é fraca demais."))
	lines.append("")
	lines.append(tr("F / Esc / M: fechar e decidir"))
	return "\n".join(lines)


## Decisao da base. Devolve as linhas para mostrar ao jogador.
func decide(send_alert: bool) -> Array:
	if decided:
		return [tr("A decisão já foi tomada.")]
	decided = true
	Missions.complete("solar")
	if send_alert:
		alert_sent = true
		countdown = CME_COUNTDOWN
		GameState.notice.emit(tr("ALARME SOLAR! Ative os escudos no controle de energia (sala do reator)!"))
		changed.emit()
		return [tr("Alerta de abrigo enviado à nave."), tr("A nave tem %d s para ativar os escudos.") % int(CME_COUNTDOWN)]
	_resolve()
	return [tr("Você ignorou o evento."), last_result]


func activate_shield() -> void:
	if alert_sent and not resolved:
		shield_on = true
		GameState.notice.emit(tr("Escudos ativados! Energia redirecionada."))
		changed.emit()


func _energy(delta_energy: float) -> void:
	if Voyage.active:
		Voyage.energy = clampf(Voyage.energy + delta_energy, 0.0, 100.0)
	elif delta_energy <= -20.0:
		Missions.flags["energia_extra"] = true   # a proxima missao gasta mais energia


func _resolve() -> void:
	resolved = true
	if real and alert_sent and shield_on:
		_energy(-15.0)
		last_result = tr("A nave atravessou a tempestade sem danos. Gastou energia moderada nos escudos.")
	elif real and alert_sent:
		GameState.apply_effects({"health": -15.0})
		inverted_left = INVERT_TIME
		last_result = tr("Os escudos não foram ativados a tempo! A radiação atingiu a nave: controles invertidos e vida -15.")
	elif real:
		GameState.apply_effects({"health": -20.0})
		inverted_left = INVERT_TIME
		last_result = tr("A base não avisou! A radiação atingiu a nave: painéis em interferência (controles invertidos) e vida -20.")
	elif alert_sent and shield_on:
		_energy(-30.0)
		if Voyage.active:
			Voyage.time_left -= 30.0
		last_result = tr("Alarme falso: os escudos foram ligados à toa. Queda brusca de energia e tempo perdido.")
	elif alert_sent:
		last_result = tr("Era alarme falso e os escudos não foram ligados. Nada aconteceu.")
	else:
		last_result = tr("Falso alarme descartado corretamente. Nada aconteceu.")
	Missions.complete("solar")     # (ja concluida se a base decidiu; ignora se fora de ordem)
	Missions.complete("escudos")
	GameState.notice.emit(last_result)
	changed.emit()
