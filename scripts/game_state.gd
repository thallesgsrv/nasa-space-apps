extends Node
## Estado global do jogo (autoload "GameState"): necessidades, vida, nucleo do reator,
## inventario, armazenamento, comida produzida e capsula para a Terra.
## Os numeros abaixo sao PLACEHOLDERS faceis de ajustar (nenhuma regra final aprovada).

signal changed            # necessidades / vida / nucleo mudaram
signal inventory_changed  # inventario, armario ou capsula mudaram
signal notice(text: String)  # aviso curto para a interface mostrar

# --- ajustes (por segundo) ---
const FOOD_DECAY := 0.5      # comida: 100 -> 0 em ~200 s
const THIRST_DECAY := 0.8    # agua
const SLEEP_DECAY := 0.3     # sono
const HEAT_RISE := 0.6       # temperatura do nucleo sobe sozinha
const STARVE_DAMAGE := 0.5   # vida perdida por segundo, por necessidade zerada
const OVERHEAT_DAMAGE := 1.0 # vida perdida por segundo com o nucleo em 100%
const HEAT_WARNING := 80.0
const CAPSULE_TIME := 5.0    # segundos que a capsula demora para voltar da Terra
const PRODUCE_TIME := 3.0    # segundos para a impressora produzir uma racao

const INVENTORY_SLOTS := 6
const STORAGE_SLOTS := 20    # armarios do armazem
const BEDS := 4              # vagas para dormir (sistema futuro)

## id -> nome e efeitos (valores somados as necessidades)
const ITEMS := {
	"cafe": {"name": "Café", "effects": {"sleep": 25.0, "thirst": 10.0}},
	"croquete": {"name": "Croquete", "effects": {"food": 30.0}},
	"refri": {"name": "Refrigerante", "effects": {"thirst": 35.0}},
	"racao": {"name": "Ração", "effects": {"food": 50.0}},
}

var running := false  # so conta tempo durante a partida
var food := 100.0
var thirst := 100.0
var sleep := 100.0
var health := 100.0
var heat := 35.0

var inventory: Array[String] = []
var storage: Array[String] = []   # itens guardados nos armarios (max STORAGE_SLOTS)
var output_rations := 0           # racoes prontas esperando no terminal de saida
var capsule_item := ""            # item viajando para a Terra
var capsule_left := 0.0
var capsule_ready := ""           # item que voltou mas nao coube na mochila
var route := ""                   # proxima rota escolhida na sala de controle
var tutorial_done := false

var _heat_warned := false


func _ready() -> void:
	_setup_input()


func _emit_state_change() -> void:
	changed.emit()


func _emit_inventory_change() -> void:
	inventory_changed.emit()


func reset() -> void:
	food = 100.0
	thirst = 100.0
	sleep = 100.0
	health = 100.0
	heat = 35.0
	inventory.clear()
	storage.clear()
	output_rations = 0
	capsule_item = ""
	capsule_left = 0.0
	capsule_ready = ""
	route = ""
	tutorial_done = false
	_heat_warned = false
	_emit_state_change()
	_emit_inventory_change()


func _process(delta: float) -> void:
	if not running:
		return
	# a viagem da capsula segue mesmo com menus abertos
	if capsule_item != "":
		capsule_left -= delta
		if capsule_left <= 0.0:
			_capsule_arrived()
	if UI.busy:
		return  # menus e dialogos congelam o tempo das necessidades
	food = maxf(0.0, food - FOOD_DECAY * delta)
	thirst = maxf(0.0, thirst - THIRST_DECAY * delta)
	sleep = maxf(0.0, sleep - SLEEP_DECAY * delta)
	heat = minf(100.0, heat + HEAT_RISE * delta)
	var damage := 0.0
	for v in [food, thirst, sleep]:
		if v <= 0.0:
			damage += STARVE_DAMAGE
	if heat >= 100.0:
		damage += OVERHEAT_DAMAGE
	health = clampf(health - damage * delta, 0.0, 100.0)
	if heat >= HEAT_WARNING and not _heat_warned:
		_heat_warned = true
		notice.emit("O núcleo do reator está esquentando!")
	elif heat < HEAT_WARNING - 10.0:
		_heat_warned = false
	_emit_state_change()


# --- necessidades ---
func apply_effects(effects: Dictionary) -> void:
	food = clampf(food + effects.get("food", 0.0), 0.0, 100.0)
	thirst = clampf(thirst + effects.get("thirst", 0.0), 0.0, 100.0)
	sleep = clampf(sleep + effects.get("sleep", 0.0), 0.0, 100.0)
	health = clampf(health + effects.get("health", 0.0), 0.0, 100.0)
	_emit_state_change()


func use_item(id: String) -> void:
	apply_effects(ITEMS[id]["effects"])


func cool_core(amount: float) -> void:
	heat = maxf(0.0, heat - amount)
	_emit_state_change()


func heal(amount: float) -> void:
	health = clampf(health + amount, 0.0, 100.0)
	_emit_state_change()


# --- inventario ---
func item_name(id: String) -> String:
	return ITEMS[id]["name"] if ITEMS.has(id) else id


func inventory_has_room() -> bool:
	return inventory.size() < INVENTORY_SLOTS


func add_item(id: String) -> bool:
	if not inventory_has_room():
		return false
	inventory.append(id)
	_emit_inventory_change()
	return true


func remove_item(id: String) -> bool:
	var i := inventory.find(id)
	if i < 0:
		return false
	inventory.remove_at(i)
	_emit_inventory_change()
	return true


# --- armarios (20 espacos) ---
func storage_has_room() -> bool:
	return storage.size() < STORAGE_SLOTS


func store_item(id: String) -> bool:
	if not storage_has_room() or not remove_item(id):
		return false
	storage.append(id)
	_emit_inventory_change()
	return true


func take_from_storage(id: String) -> bool:
	var i := storage.find(id)
	if i < 0 or not inventory_has_room():
		return false
	storage.remove_at(i)
	inventory.append(id)
	_emit_inventory_change()
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
func send_to_earth(id: String) -> bool:
	if capsule_item != "" or capsule_ready != "" or not remove_item(id):
		return false
	capsule_item = id
	capsule_left = CAPSULE_TIME
	_emit_inventory_change()
	return true


func _capsule_arrived() -> void:
	var id := capsule_item
	capsule_item = ""
	capsule_left = 0.0
	if add_item(id):
		notice.emit("A cápsula voltou da Terra: %s" % item_name(id))
	else:
		capsule_ready = id
		notice.emit("A cápsula voltou, mas a mochila está cheia!")
	_emit_inventory_change()


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
