extends Control
## Lobby do multiplayer em LAN. Telas: principal -> (criar sala | procurar salas | entrar por IP) -> aguardando.
## Host = astronauta (estacao). Cliente = cientista (base na Terra). W/S escolhem, F/Enter confirma, Esc volta.

const BG := preload("res://assets/ui/start_bg.png")
const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const INK := Color("1b2a5c")
const LIGHT := Color("dfe9ff")
const GAME_SCENE := "res://scenes/cutscene_intro.tscn"
const MENU_SCENE := "res://scenes/start_menu.tscn"
const PANEL := Rect2(168, 210, 1200, 640)

enum S { MAIN, HOSTING, BROWSE, IP, JOINING, WAITING }

var _state := S.MAIN
var _sel := 0
var _title: Label
var _body: Label
var _rows: Array[Label] = []
var _cursor: Polygon2D
var _hint: Label
var _ip_edit: LineEdit
var _items: Array = []      # [{"label": String, "act": String, "arg": Variant}]
var _starting := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Audio.stop_music()
	UI.show_hud(false)
	GameState.running = false
	var bg := TextureRect.new()
	bg.texture = BG
	bg.size = Vector2(1536, 1024)
	bg.stretch_mode = TextureRect.STRETCH_KEEP
	add_child(bg)
	var panel := Panel.new()
	panel.position = PANEL.position
	panel.size = PANEL.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.09, 0.22, 0.92)
	sb.border_color = LIGHT
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	_title = _label(36, LIGHT, Vector2(PANEL.position.x + 40, PANEL.position.y + 28), Vector2(PANEL.size.x - 80, 48))
	_body = _label(24, LIGHT, Vector2(PANEL.position.x + 40, PANEL.position.y + 96), Vector2(PANEL.size.x - 80, 200))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for i in 6:
		_rows.append(_label(30, LIGHT, Vector2(PANEL.position.x + 110, PANEL.position.y + 300 + i * 52), Vector2(PANEL.size.x - 160, 42)))
	_cursor = Polygon2D.new()
	_cursor.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 30), Vector2(22, 15)])
	_cursor.color = LIGHT
	add_child(_cursor)
	_hint = _label(24, Color("dfe9ff"), Vector2(0, 962), Vector2(1536, 30))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip_edit = LineEdit.new()
	_ip_edit.add_theme_font_override("font", FONT)
	_ip_edit.add_theme_font_size_override("font_size", 30)
	_ip_edit.position = Vector2(PANEL.position.x + 110, PANEL.position.y + 300)
	_ip_edit.size = Vector2(520, 56)
	_ip_edit.placeholder_text = "192.168.0.10"
	_ip_edit.max_length = 15
	_ip_edit.visible = false
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _join_ip(_ip_edit.text))
	add_child(_ip_edit)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.connected_to_host.connect(_on_connected)
	Net.connection_failed.connect(_on_conn_failed)
	Net.game_start_requested.connect(_on_start_requested)
	if Net.is_online():
		Net.leave()   # voltando de uma partida: comeca limpo
	_go(S.MAIN)
	UI.fade_to(0.0, 0.3)


func _exit_tree() -> void:
	Net.stop_browsing()


func _label(size: int, color: Color, pos: Vector2, sz: Vector2) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	l.size = sz
	add_child(l)
	return l


# ---------------------------------------------------------------- telas
func _go(s: S) -> void:
	_state = s
	_sel = 0
	_ip_edit.visible = false
	_ip_edit.release_focus()
	Net.stop_browsing()
	match s:
		S.MAIN:
			if Net.is_online():
				Net.leave()
			_title.text = tr("MULTIPLAYER LAN")
			_body.text = tr("Dois jogadores na mesma rede. O HOST joga de astronauta na estação; o outro jogador é a BASE na Terra (cientista) e decide com as informações que só ele vê.")
			_items = [
				{"label": tr("CRIAR SALA (ser o astronauta)"), "act": "host"},
				{"label": tr("PROCURAR SALAS (ser a base)"), "act": "browse"},
				{"label": tr("ENTRAR POR IP"), "act": "ip"},
				{"label": tr("VOLTAR"), "act": "back"},
			]
			_hint.text = tr("W / S: escolher     F ou Enter: confirmar")
		S.HOSTING:
			_title.text = tr("SALA CRIADA")
			_items = []
			_refresh_hosting()
		S.BROWSE:
			Net.start_browsing()
			_title.text = tr("SALAS NA REDE")
			_refresh_browse()
		S.IP:
			_title.text = tr("ENTRAR POR IP")
			_body.text = tr("Digite o IP do host (aparece na tela dele) e aperte Enter.")
			_items = []
			_ip_edit.visible = true
			_ip_edit.text = ""
			_ip_edit.grab_focus()
			_hint.text = tr("Enter: conectar     Esc: voltar")
		S.JOINING:
			_title.text = tr("CONECTANDO...")
			_body.text = ""
			_items = []
			_hint.text = tr("Esc: cancelar")
		S.WAITING:
			_title.text = tr("CONECTADO")
			_body.text = tr("Você é a BASE na Terra (cientista). Aguardando o host iniciar a missão...")
			_items = []
			_hint.text = tr("Esc: sair da sala")
	_render()


func _refresh_hosting() -> void:
	var ips := Net.local_ips()
	var ip_text := ", ".join(ips) if not ips.is_empty() else tr("(não encontrado)")
	var status := tr("Cientista conectado! Pronto para começar.") if Net.partner_connected else tr("Aguardando o cientista entrar...")
	_body.text = tr("Seu IP na rede: %s   Porta: %d\nO outro jogador pode achar a sala sozinho em PROCURAR SALAS.\n\n%s") % [ip_text, Net.PORT, status]
	_items = []
	if Net.partner_connected:
		_items.append({"label": tr("INICIAR MISSÃO"), "act": "start"})
	_items.append({"label": tr("CANCELAR"), "act": "main"})
	_hint.text = tr("W / S: escolher     F ou Enter: confirmar     Esc: cancelar")


func _refresh_browse() -> void:
	_items = []
	for ip in Net.hosts:
		var h: Dictionary = Net.hosts[ip]
		_items.append({"label": "%s  (%s)" % [h["name"], ip], "act": "join", "arg": ip, "port": h["port"]})
	_items.append({"label": tr("VOLTAR"), "act": "main"})
	_body.text = tr("Procurando salas na rede...") if Net.hosts.is_empty() else tr("Escolha a sala do astronauta:")
	_hint.text = tr("W / S: escolher     F ou Enter: entrar     Esc: voltar")
	_sel = clampi(_sel, 0, _items.size() - 1)


func _render() -> void:
	for i in _rows.size():
		_rows[i].visible = i < _items.size()
		if i < _items.size():
			_rows[i].text = _items[i]["label"]
	_cursor.visible = not _items.is_empty()
	_sel = clampi(_sel, 0, maxi(0, _items.size() - 1))
	_cursor.position = Vector2(PANEL.position.x + 60, PANEL.position.y + 300 + _sel * 52 + 6)


# ---------------------------------------------------------------- eventos
func _on_lobby_changed() -> void:
	if _state == S.HOSTING:
		_refresh_hosting()
		_render()
	elif _state == S.BROWSE:
		_refresh_browse()
		_render()


func _on_connected() -> void:
	_go(S.WAITING)


func _on_conn_failed() -> void:
	if _state == S.JOINING or _state == S.WAITING:
		_go(S.MAIN)
		_body.text = tr("Não foi possível conectar (ou o host saiu). Confira o IP e se os dois estão na mesma rede.")


func _on_start_requested() -> void:
	_begin()


func _input(event: InputEvent) -> void:
	# Esc volta (em _input: o campo de IP consome teclas antes do _unhandled_input)
	if not _starting and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_back()


func _unhandled_input(event: InputEvent) -> void:
	if _starting:
		return
	if _state == S.IP or _items.is_empty():
		return
	if event.is_action_pressed("move_up", true):
		_sel = (_sel - 1 + _items.size()) % _items.size()
		_render()
	elif event.is_action_pressed("move_down", true):
		_sel = (_sel + 1) % _items.size()
		_render()
	elif event.is_action_pressed("interact") and not event.is_echo():
		_activate(_items[_sel])


func _back() -> void:
	match _state:
		S.MAIN:
			get_tree().change_scene_to_file(MENU_SCENE)
		_:
			_go(S.MAIN)


func _activate(item: Dictionary) -> void:
	Audio.sfx("select", 1.35, 0.5)
	match String(item["act"]):
		"host":
			var err := Net.host_game()
			if err != OK:
				_body.text = tr("Não foi possível criar a sala (porta %d em uso?).") % Net.PORT
				return
			_go(S.HOSTING)
		"browse":
			_go(S.BROWSE)
		"ip":
			_go(S.IP)
		"join":
			_join(String(item["arg"]), int(item["port"]))
		"start":
			if Net.partner_connected:
				Net.start_game()
				_begin()
		"main":
			_go(S.MAIN)
		"back":
			get_tree().change_scene_to_file(MENU_SCENE)


func _join_ip(ip: String) -> void:
	if ip.strip_edges() == "":
		return
	_join(ip, Net.PORT)


func _join(ip: String, port: int) -> void:
	if Net.join_game(ip, port) != OK:
		_go(S.MAIN)
		_body.text = tr("Endereço inválido.")
		return
	_go(S.JOINING)


## Os dois lados comecam juntos: zera o estado e vai para a cutscene inicial e depois para o jogo.
func _begin() -> void:
	if _starting:
		return
	_starting = true
	Net.begin_game()
	GameState.reset()
	await UI.fade_to(1.0, 0.5)
	get_tree().change_scene_to_file(GAME_SCENE)
