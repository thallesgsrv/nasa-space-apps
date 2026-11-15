extends Control
## Lobby do multiplayer (LAN ou internet). Telas: principal -> (criar sala | procurar salas | entrar por IP/URL) -> aguardando.
## Host = astronauta/comandante. Clientes: cientista, engenheiro de voo, astronauta 2 (ate 4 jogadores).
## W/S escolhem, F/Enter confirma, Esc volta.

const BG := preload("res://assets/ui/start_bg.png")
const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const INK := Color("1b2a5c")
const LIGHT := Color("dfe9ff")
const GAME_SCENE := "res://scenes/cutscene_intro.tscn"
const MENU_SCENE := "res://scenes/start_menu.tscn"
const TEX_PANEL := preload("res://assets/ui/panel_menu.png")
const PANEL_W := 1020.0
const PAD := 64.0           # folga entre a borda da moldura e o conteudo
const ROW_H := 58.0

enum S { MAIN, HOSTING, BROWSE, IP, JOINING, WAITING }

var _state := S.MAIN
var _sel := 0
var _title: Label
var _body: Label
var _rows: Array[Label] = []
var _cursor: Polygon2D
var _panel: NinePatchRect
var _hint: Label
var _ip_edit: LineEdit
var _items: Array = []      # [{"label": String, "act": String, "arg": Variant}]
var _starting := false
var _url_mode := false      # tela de entrada: true = endereco ws://, false = IP da LAN
var _web := OS.has_feature("web")


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
	# moldura NinePatchRect (cantos fixos, miolo estica): a altura se ajusta ao conteudo em _layout()
	_panel = NinePatchRect.new()
	_panel.texture = TEX_PANEL
	for side in ["left", "right", "top", "bottom"]:
		_panel.set("patch_margin_" + side, 30)
	add_child(_panel)
	_title = _label(40, INK, Vector2.ZERO, Vector2(PANEL_W - 2.0 * PAD, 52))
	_body = _label(24, INK, Vector2.ZERO, Vector2(PANEL_W - 2.0 * PAD, 40))
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_constant_override("line_spacing", 8)
	for i in 6:
		_rows.append(_label(30, INK, Vector2.ZERO, Vector2(PANEL_W - 2.0 * PAD - 60.0, 44)))
	_cursor = Polygon2D.new()
	_cursor.polygon = PackedVector2Array([Vector2(0, 0), Vector2(0, 30), Vector2(22, 15)])
	_cursor.color = INK
	add_child(_cursor)
	_hint = _label(24, Color("dfe9ff"), Vector2(0, 962), Vector2(1536, 30))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ip_edit = LineEdit.new()
	_ip_edit.add_theme_font_override("font", FONT)
	_ip_edit.add_theme_font_size_override("font_size", 30)
	_ip_edit.size = Vector2(520, 56)
	_ip_edit.placeholder_text = "192.168.0.10"
	_ip_edit.max_length = 15
	_ip_edit.visible = false
	_ip_edit.text_submitted.connect(func(_t: String) -> void: _join_ip(_ip_edit.text))
	add_child(_ip_edit)
	Net.lobby_changed.connect(_on_lobby_changed)
	Net.roster_changed.connect(_on_lobby_changed)
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
			_title.text = tr("MULTIPLAYER")
			_body.text = tr("Até 4 jogadores. O HOST é o astronauta comandante na estação; os outros entram como BASE na Terra (cientista), engenheiro de voo e astronauta 2.")
			_items = []
			if _web:
				_body.text += "\n" + tr("No navegador só é possível ENTRAR numa sala por endereço ws:// ou wss://.")
			else:
				_items.append({"label": tr("CRIAR SALA NA LAN (ser o comandante)"), "act": "host"})
				_items.append({"label": tr("CRIAR SALA NA INTERNET (WebSocket)"), "act": "host_ws"})
				_items.append({"label": tr("PROCURAR SALAS NA LAN"), "act": "browse"})
				_items.append({"label": tr("ENTRAR POR IP"), "act": "ip"})
			_items.append({"label": tr("ENTRAR POR ENDEREÇO (ws://)"), "act": "url"})
			_items.append({"label": tr("VOLTAR"), "act": "back"})
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
			_title.text = tr("ENTRAR POR ENDEREÇO") if _url_mode else tr("ENTRAR POR IP")
			_body.text = tr("Digite o endereço da sala (ex.: ws://meu-servidor:24567) e aperte Enter.") if _url_mode else tr("Digite o IP do host (aparece na tela dele) e aperte Enter.")
			_items = []
			_ip_edit.max_length = 120 if _url_mode else 15
			_ip_edit.placeholder_text = "ws://192.168.0.10:24567" if _url_mode else "192.168.0.10"
			_ip_edit.size = Vector2(900 if _url_mode else 520, 56)
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
			_refresh_waiting()
	_render()


func _roster_text() -> String:
	var lines: Array[String] = []
	var all: Array = []
	for id in Net.roster:
		all.append(Net.roster[id])
	for e in all:
		lines.append("%s: %s" % [Net.role_name(int(e["role"])), e["name"]])
	return "\n".join(lines)


func _refresh_waiting() -> void:
	_body.text = tr("Você é: %s.\nJogadores:\n%s\n\nEscolha outro papel livre abaixo ou aguarde o host iniciar a missão.") % [Net.role_name(Net.my_role), _roster_text()]
	_items = []
	for r in Net.CLIENT_ROLE_ORDER:
		if int(r) != Net.my_role and _role_free(int(r)):
			_items.append({"label": tr("Trocar para: %s") % Net.role_name(int(r)), "act": "role", "arg": int(r)})
	_hint.text = tr("W / S: escolher     F ou Enter: confirmar     Esc: sair da sala")


func _role_free(role: int) -> bool:
	for id in Net.roster:
		if int(Net.roster[id]["role"]) == role:
			return false
	return true


func _refresh_hosting() -> void:
	var ips := Net.local_ips()
	var ip_text := ", ".join(ips) if not ips.is_empty() else tr("(não encontrado)")
	var status := tr("Jogadores conectados: %d de 4. Pode começar quando quiser.") % Net.roster.size() if Net.partner_connected else tr("Aguardando outros jogadores entrarem...")
	if Net.transport == Net.Transport.WEBSOCKET:
		_body.text = tr("Sala na internet (WebSocket). Seu IP na rede: %s   Porta: %d\nLibere a porta no roteador/firewall (ou use um túnel) e passe o endereço ws://SEU-IP:%d aos outros jogadores.\n\n%s\n%s") % [ip_text, Net.WS_PORT, Net.WS_PORT, status, _roster_text()]
	else:
		_body.text = tr("Seu IP na rede: %s   Porta: %d\nOs outros jogadores acham a sala sozinhos em PROCURAR SALAS.\n\n%s\n%s") % [ip_text, Net.PORT, status, _roster_text()]
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
	_layout()


## Calcula a altura da moldura pelo conteudo (titulo + texto + opcoes) e centraliza na tela.
func _layout() -> void:
	var inner_w := PANEL_W - 2.0 * PAD
	var y := 50.0
	_title.position = Vector2(PAD, y)
	y += 52.0 + 18.0
	var body_h := 0.0
	if _body.text != "":
		var sz := FONT.get_multiline_string_size(_body.text, HORIZONTAL_ALIGNMENT_LEFT, inner_w, 24)
		body_h = sz.y + float(_body.text.count("
") + 1) * 4.0 + 8.0
		_body.visible = true
		_body.position = Vector2(PAD, y)
		_body.size = Vector2(inner_w, body_h)
		y += body_h + 44.0
	else:
		_body.visible = false
	var rows_top := y
	for i in _items.size():
		_rows[i].position = Vector2(PAD + 60.0, rows_top + float(i) * ROW_H)
	if _ip_edit.visible:
		y += 70.0
	else:
		y += float(_items.size()) * ROW_H
	# a moldura cobre a caixa desenhada no fundo (start_bg.png, x 80-760, y 330-665): altura minima 380
	var h := maxf(y + 44.0, 380.0)
	var top := minf(clampf((1024.0 - h) / 2.0 - 20.0, 60.0, 400.0), 300.0)
	_panel.size = Vector2(PANEL_W, h)
	_panel.position = Vector2(60.0, top)
	# os rotulos sao filhos da cena (nao da moldura): converte para coordenadas da tela
	_title.position += _panel.position
	if _body.visible:
		_body.position += _panel.position
	for i in _items.size():
		_rows[i].position += _panel.position
	_cursor.position = Vector2(_panel.position.x + PAD + 10.0, _panel.position.y + rows_top + float(_sel) * ROW_H + 8.0)
	if _ip_edit.visible:
		_ip_edit.position = Vector2(_panel.position.x + PAD + 10.0, _panel.position.y + rows_top)


# ---------------------------------------------------------------- eventos
func _on_lobby_changed() -> void:
	if _state == S.WAITING:
		_refresh_waiting()
		_render()
	elif _state == S.HOSTING:
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
		"host", "host_ws":
			var use_ws := String(item["act"]) == "host_ws"
			var port := Net.WS_PORT if use_ws else Net.PORT
			var err := Net.host_game(port, use_ws)
			if err != OK:
				_body.text = tr("Não foi possível criar a sala (porta %d em uso?).") % port
				return
			_go(S.HOSTING)
		"browse":
			_go(S.BROWSE)
		"ip":
			_url_mode = false
			_go(S.IP)
		"url":
			_url_mode = true
			_go(S.IP)
		"role":
			Net.request_role(int(item["arg"]))
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
	if _url_mode:
		if Net.join_url(ip) != OK:
			_go(S.MAIN)
			_body.text = tr("Endereço inválido.")
			return
		_go(S.JOINING)
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
