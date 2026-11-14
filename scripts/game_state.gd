extends Node
## Estado global do jogo (autoload "GameState"): necessidades, vida, nucleo do reator,
## inventario, armazenamento, comida produzida e capsula para a Terra.
## Os numeros abaixo sao PLACEHOLDERS faceis de ajustar (nenhuma regra final aprovada).

signal changed            # necessidades / vida / nucleo mudaram
signal inventory_changed  # inventario, armario ou capsula mudaram
signal failed(reason: String)    # missao falhou (colisao, tempo, energia, combustivel): game over
signal exploded                # o nucleo ficou 12 s em 100% sem resfriar
signal notice(text: String)  # aviso curto para a interface mostrar

# --- ajustes (por segundo) ---
const FOOD_DECAY := 0.5      # comida: 100 -> 0 em ~200 s
const THIRST_DECAY := 0.8    # agua
const SLEEP_DECAY := 0.3     # sono
const HEAT_RISE := 0.6       # temperatura do nucleo sobe sozinha
const STARVE_DAMAGE := 0.5   # vida perdida por segundo, por necessidade zerada
const MELTDOWN_TIME := 12.0  # segundos ate a nave explodir depois que o nucleo chega a 100%
const HEAT_WARNING := 80.0
const CAPSULE_TIME := 5.0    # segundos que a capsula demora para voltar da Terra
const PRODUCE_TIME := 3.0    # segundos para a impressora produzir uma racao

const INVENTORY_SLOTS := 6
const STORAGE_SLOTS := 20    # armarios do armazem
const BEDS := 4              # vagas para dormir (sistema futuro)

## id -> nome e efeitos (valores somados as necessidades)
const ITEMS := {
	"cafe": {"name": "Café", "short": "CA", "effects": {"sleep": 25.0, "thirst": 10.0}},
	"bolacha": {"name": "Bolacha", "short": "BO", "effects": {"food": 30.0}},
	"refri": {"name": "Refrigerante", "short": "RE", "effects": {"thirst": 35.0}},
	"racao": {"name": "Ração", "short": "RA", "effects": {"food": 50.0}},
	# itens da missao 1 (sem efeito ao usar)
	"pacote_fungos": {"name": "Pacote de fungos", "short": "PF", "effects": {}},
	"pacote_quente": {"name": "Pacote aquecido", "short": "PQ", "effects": {}},
	"amostra": {"name": "Amostra centrifugada", "short": "AM", "effects": {}},
}

var running := false  # so conta tempo durante a partida
var food := 100.0
var thirst := 100.0
var sleep := 100.0
var health := 100.0
var heat := 35.0
var heat_extra_rate := 0.0          # variacao extra da temperatura por segundo (eventos do reator)
var meltdown_left := -1.0         # contagem para a explosao (-1 = parada)

var inventory: Array[String] = []
var storage: Array[String] = []   # itens guardados nos armarios (max STORAGE_SLOTS)
var output_rations := 0           # racoes prontas esperando no terminal de saida
var capsule_item := ""            # item viajando para a Terra
var capsule_left := 0.0
var capsule_hold := false         # true: item fica na Terra ate a base liberar (veredito da missao)
var capsule_ready := ""           # item que chegou da Terra e espera ser retirado (1 espaco)
var route := ""                   # proxima rota escolhida na sala de controle
var conditions: Array[String] = []  # doencas/anomalias descobertas no checkup (nenhuma por enquanto)
var tutorial_done := false

var _heat_warned := false


func _ready() -> void:
	_setup_input()


func reset() -> void:
	food = 100.0
	thirst = 100.0
	sleep = 100.0
	health = 100.0
	heat = 35.0
	meltdown_left = -1.0
	heat_extra_rate = 0.0
	inventory.clear()
	storage.clear()
	output_rations = 0
	capsule_item = ""
	capsule_left = 0.0
	capsule_hold = false
	capsule_ready = ""
	route = ""
	conditions.clear()
	tutorial_done = false
	_heat_warned = false
	Missions.reset()
	Voyage.reset()
	Solar.reset()
	changed.emit()
	inventory_changed.emit()


func _process(delta: float) -> void:
	if not running:
		return
	# a viagem da capsula segue mesmo com menus abertos
	if capsule_item != "" and not capsule_hold:
		capsule_left -= delta
		if capsule_left <= 0.0:
			_capsule_arrived()
	if UI.busy and not UI.realtime:
		return  # menus e dialogos congelam o tempo das necessidades
	food = maxf(0.0, food - FOOD_DECAY * delta)
	thirst = maxf(0.0, thirst - THIRST_DECAY * delta)
	sleep = maxf(0.0, sleep - SLEEP_DECAY * delta)
	heat = clampf(heat + (HEAT_RISE + heat_extra_rate) * delta, 0.0, 100.0)
	var damage := 0.0
	for v in [food, thirst, sleep]:
		if v <= 0.0:
			damage += STARVE_DAMAGE
	health = clampf(health - damage * delta, 0.0, 100.0)
	if heat >= 100.0:
		if meltdown_left < 0.0:
			meltdown_left = MELTDOWN_TIME
			notice.emit(tr("NÚCLEO CRÍTICO! Resfrie agora: a nave explode em %d segundos!") % int(MELTDOWN_TIME))
		else:
			meltdown_left -= delta
			if meltdown_left <= 0.0:
				meltdown_left = 0.0
				running = false
				changed.emit()
				exploded.emit()
				return
	elif meltdown_left >= 0.0:
		meltdown_left = -1.0
	if heat >= HEAT_WARNING and not _heat_warned:
		_heat_warned = true
		notice.emit(tr("O núcleo do reator está esquentando!"))
	elif heat < HEAT_WARNING - 10.0:
		_heat_warned = false
	changed.emit()


# --- necessidades ---
func apply_effects(effects: Dictionary) -> void:
	food = clampf(food + effects.get("food", 0.0), 0.0, 100.0)
	thirst = clampf(thirst + effects.get("thirst", 0.0), 0.0, 100.0)
	sleep = clampf(sleep + effects.get("sleep", 0.0), 0.0, 100.0)
	health = clampf(health + effects.get("health", 0.0), 0.0, 100.0)
	changed.emit()


func use_item(id: String) -> void:
	apply_effects(ITEMS[id]["effects"])


func cool_core(amount: float) -> void:
	heat = maxf(0.0, heat - amount)
	if heat < 100.0:
		meltdown_left = -1.0
	changed.emit()


func heal(amount: float) -> void:
	health = clampf(health + amount, 0.0, 100.0)
	changed.emit()


# --- inventario ---
func item_name(id: String) -> String:
	return tr(ITEMS[id]["name"]) if ITEMS.has(id) else id


func item_short(id: String) -> String:
	return ITEMS[id]["short"] if ITEMS.has(id) else id.substr(0, 2).to_upper()


func inventory_has_room() -> bool:
	return inventory.size() < INVENTORY_SLOTS


func add_item(id: String) -> bool:
	if not inventory_has_room():
		return false
	inventory.append(id)
	inventory_changed.emit()
	return true


func remove_item(id: String) -> bool:
	var i := inventory.find(id)
	if i < 0:
		return false
	inventory.remove_at(i)
	inventory_changed.emit()
	return true


# --- armarios (20 espacos) ---
func storage_has_room() -> bool:
	return storage.size() < STORAGE_SLOTS


func store_item(id: String) -> bool:
	if not storage_has_room() or not remove_item(id):
		return false
	storage.append(id)
	inventory_changed.emit()
	return true


func take_from_storage(id: String) -> bool:
	var i := storage.find(id)
	if i < 0 or not inventory_has_room():
		return false
	storage.remove_at(i)
	inventory.append(id)
	inventory_changed.emit()
	return true


func take_storage_at(i: int) -> bool:
	if i < 0 or i >= storage.size() or not inventory_has_room():
		return false
	inventory.append(storage[i])
	storage.remove_at(i)
	inventory_changed.emit()
	return true


func count_of(list: Array, id: String) -> int:
	var n := 0
	for it in list:
		if it == id:
			n += 1
	return n


## ids distintos em ordem de aparicao
func unique_ids(list: Array) -> Array[String]:
	var out: Array[String] = []
	for it in list:
		if not out.has(it):
			out.append(it)
	return out


# --- capsula para a Terra ---
## hold = true: o item fica na Terra e so volta depois de release_capsule() (base libera).
func send_to_earth(id: String, hold: bool = false) -> bool:
	if capsule_item != "" or capsule_ready != "" or not remove_item(id):
		return false
	capsule_item = id
	capsule_hold = hold
	capsule_left = CAPSULE_TIME
	inventory_changed.emit()
	return true


## A base liberou o item: ele volta ao astronauta apos CAPSULE_TIME segundos.
func release_capsule() -> void:
	if capsule_item != "" and capsule_hold:
		capsule_hold = false
		capsule_left = CAPSULE_TIME
		inventory_changed.emit()


func _capsule_arrived() -> void:
	# a capsula tem 1 espaco: o item fica la ate o astronauta retirar
	capsule_ready = capsule_item
	capsule_item = ""
	capsule_left = 0.0
	notice.emit(tr("Chegou da Terra: %s. Retire na cápsula (armazém).") % item_name(capsule_ready))
	inventory_changed.emit()


func collect_capsule() -> bool:
	if capsule_ready == "" or not add_item(capsule_ready):
		return false
	capsule_ready = ""
	return true


# --- entrada: acoes criadas no codigo (setas + WASD, F/Enter/Espaco, I/Tab) ---
func _setup_input() -> void:
	var binds := {
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"move_up": [KEY_W, KEY_UP],
		"move_down": [KEY_S, KEY_DOWN],
		"interact": [KEY_F, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
		"inventory": [KEY_I, KEY_TAB],
		"switch_world": [KEY_1, KEY_KP_1],
		"missions": [KEY_M, KEY_J],
		"objective": [KEY_V],
	}
	for action in binds:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		InputMap.action_erase_events(action)
		for key in binds[action]:
			# uma ligacao pela posicao fisica da tecla e outra pela tecla logica (layout)
			var physical := InputEventKey.new()
			physical.physical_keycode = key
			InputMap.action_add_event(action, physical)
			var logical := InputEventKey.new()
			logical.keycode = key
			InputMap.action_add_event(action, logical)
