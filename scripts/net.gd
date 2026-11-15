extends Node
## Multiplayer (autoload "Net"). Cooperativo assimetrico, ate 4 jogadores:
##   HOST     = astronauta/comandante na estacao (roda TODA a simulacao: necessidades, viagem, eventos...)
##   CLIENTES = cientista (base na Terra), engenheiro de voo e astronauta 2 (na estacao). Os autoloads
##              deles sao um ESPELHO do host; o papel e atribuido na ordem de entrada (e pode ser trocado).
## - Transportes: ENet/UDP (LAN, com descoberta) ou WebSocket (internet / navegador). O host e sempre um
##   executavel desktop; clientes web entram por ws:// ou wss://.
## - A posicao de cada jogador e replicada (host -> todos, ~12x/s) para os "fantasmas" na mesma sala.
## - O host envia um "snapshot" do estado (GameState, Missions, Voyage, Solar) ~10x por segundo.
## - As decisoes da base (veredito, alerta, analise da amostra...) sao pedidas pelo cliente ao host via
##   call_host(); o host executa a regra de verdade e devolve o resultado (e um snapshot na hora).
## - Eventos pontuais do host (avisos, game over, decisao de reiniciar) chegam por RPC.
## - Descoberta automatica: o host anuncia a sala por broadcast UDP; o cliente lista as salas da rede.
## Sem multiplayer (mode == OFFLINE) nada daqui muda o comportamento do jogo.

signal lobby_changed                # alguem entrou/saiu ou a lista de salas mudou
signal connected_to_host            # (cliente) conexao estabelecida
signal connection_failed            # (cliente) nao foi possivel conectar
signal host_left                    # (cliente) o host caiu no meio da partida
signal partner_left                 # (host) o cliente saiu
signal game_start_requested         # (cliente) o host mandou comecar
signal restart_decided(choice: int) # (cliente) decisao do host no game over: 0 recomecar, 1 menu
signal partner_room_changed
signal roster_changed              # a lista de jogadores/papeis mudou

enum Mode { OFFLINE, HOST, CLIENT }
enum Role { ASTRONAUT, SCIENTIST, ENGINEER, ASTRONAUT2 }
enum Transport { ENET, WEBSOCKET }

const MAX_CLIENTS := 3                       # host + 3 = 4 jogadores
const CLIENT_ROLE_ORDER := [Role.SCIENTIST, Role.ENGINEER, Role.ASTRONAUT2]
const ROLE_NAMES := {
	Role.ASTRONAUT: "Astronauta (comandante)",
	Role.SCIENTIST: "Base (cientista)",
	Role.ENGINEER: "Engenheiro de voo",
	Role.ASTRONAUT2: "Astronauta 2",
}
const WS_PORT := 24567
const POSE_INTERVAL := 0.08

const PORT := 24565
const DISCOVERY_PORT := 24566
const MAGIC := "NASA-SPACE-APPS-LAN/1"
const SNAPSHOT_INTERVAL := 0.1
const ANNOUNCE_INTERVAL := 1.0
const HOST_TIMEOUT := 3.5           # sala some da lista se nao anunciar por este tempo

## Variaveis replicadas do host para o cliente (autoload -> variaveis).
const SYNC := {
	"GameState": ["running", "food", "thirst", "sleep", "health", "heat", "heat_extra_rate", "meltdown_left",
		"inventory", "storage", "output_rations", "capsule_item", "capsule_left", "capsule_hold",
		"capsule_ready", "route", "conditions", "tutorial_done"],
	"Missions": ["active", "step", "finished", "flags", "heater_state", "heating_left", "analyzed",
		"data_sent", "sample_color", "sample_ok", "result_lines"],
	"Voyage": ["active", "route", "travel_time", "time_left", "progress", "energy", "fuel", "mass",
		"energy_mult", "next_event", "next_in", "event", "blackout_left", "asteroid", "reactor", "base_alert"],
	"Solar": ["real", "base_flux", "base_angle", "decided", "alert_sent", "countdown", "shield_on",
		"resolved", "inverted_left", "last_result", "_t", "source_tag", "source_label"],
	"MissionState": ["planned", "objective", "cml_done", "params", "decisions", "accepted_risks", "mitigated",
		"log", "stats", "report"],
}

## Chamadas que o cliente (base) pode pedir ao host: autoload -> metodos permitidos.
const REMOTE_CALLS := {
	"Missions": ["analyze_sample", "verdict"],
	"Voyage": ["set_estimate", "send_alert"],
	"Solar": ["decide", "activate_shield"],
	"GameState": ["crew_cool_core"],
}

## Quem pode pedir cada chamada (por papel). Chamada fora desta tabela = qualquer cliente.
const CALL_ROLES := {
	"Missions.analyze_sample": [Role.SCIENTIST],
	"Missions.verdict": [Role.SCIENTIST],
	"Voyage.set_estimate": [Role.SCIENTIST],
	"Voyage.send_alert": [Role.SCIENTIST],
	"Solar.decide": [Role.SCIENTIST],
	"Solar.activate_shield": [Role.ENGINEER, Role.ASTRONAUT2],
	"GameState.crew_cool_core": [Role.ENGINEER, Role.ASTRONAUT2],
}

var mode := Mode.OFFLINE
var player_name := "Jogador"
var in_game := false                # a partida ja comecou (host: recusa novas conexoes)
var partner_connected := false      # host: ha cliente conectado
var partner_room := ""              # sala onde o parceiro esta agora (texto para o HUD)
var hosts: Dictionary = {}          # ip -> {"name": String, "port": int, "seen": float}
var pending_decision := -1

var transport := Transport.ENET
var my_role := Role.ASTRONAUT
## id do peer -> {"name", "role", "room", "scene", "pos", "facing"}. O host e o id 1.
var roster: Dictionary = {}

var _peer: MultiplayerPeer
var _pose_left := 0.0
var _pose_dirty := false
var _my_pose := {"scene": "", "pos": Vector2.ZERO, "facing": 0}
var _port := PORT
var _udp_out: PacketPeerUDP
var _udp_in: PacketPeerUDP
var _announce_left := 0.0
var _snap_left := 0.0
var _last_snap: Dictionary = {}
var _req_id := 0
var _results: Dictionary = {}
var _waiting: Dictionary = {}    # ids de chamadas esperando resposta do host
signal _result_ready


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	GameState.notice.connect(_on_notice)
	GameState.failed.connect(_on_failed)
	GameState.exploded.connect(_on_exploded)
	var host := OS.get_environment("COMPUTERNAME") if OS.has_environment("COMPUTERNAME") else OS.get_environment("HOSTNAME")
	if host != "":
		player_name = host.left(20)


# ---------------------------------------------------------------- estado
func is_online() -> bool:
	return mode != Mode.OFFLINE


func is_host() -> bool:
	return mode == Mode.HOST


## O jogador e o CLIENTE (cientista): seus autoloads so espelham o host.
func is_client() -> bool:
	return mode == Mode.CLIENT


## Ha dois jogadores de verdade na partida (host com cliente ou cliente conectado).
func has_partner() -> bool:
	return (mode == Mode.HOST and partner_connected) or mode == Mode.CLIENT


## Cliente que joga na estacao (engenheiro / astronauta 2): anda na nave, mas so usa os sistemas da sua funcao.
func is_crew_client() -> bool:
	return is_client() and (my_role == Role.ENGINEER or my_role == Role.ASTRONAUT2)


func role_name(role: int) -> String:
	return tr(String(ROLE_NAMES.get(role, "Jogador")))


## Os outros jogadores (sem mim): lista de {"id", "name", "role", "room", "scene", "pos", "facing"}.
func others() -> Array:
	var me := 1 if is_host() else multiplayer.get_unique_id()
	var out: Array = []
	for id in roster:
		if int(id) != me:
			var e: Dictionary = (roster[id] as Dictionary).duplicate()
			e["id"] = id
			out.append(e)
	return out


func local_ips() -> Array[String]:
	var out: Array[String] = []
	for ip in IP.get_local_addresses():
		if ip.contains(":") or ip.begins_with("127.") or ip.begins_with("169.254."):
			continue
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			out.append(ip)
	return out


# ---------------------------------------------------------------- host
## ws=false: LAN (ENet/UDP, anunciada por broadcast). ws=true: WebSocket (internet; so em executavel desktop).
func host_game(port: int = PORT, ws: bool = false) -> Error:
	leave()
	var peer: MultiplayerPeer
	if ws:
		var wp := WebSocketMultiplayerPeer.new()
		var werr := wp.create_server(port)
		if werr != OK:
			return werr
		peer = wp
	else:
		var ep := ENetMultiplayerPeer.new()
		var eerr := ep.create_server(port, MAX_CLIENTS)
		if eerr != OK:
			return eerr
		peer = ep
	_peer = peer
	_port = port
	transport = Transport.WEBSOCKET if ws else Transport.ENET
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	my_role = Role.ASTRONAUT
	in_game = false
	partner_connected = false
	pending_decision = -1
	_last_snap = {}
	roster = {1: {"name": player_name, "role": Role.ASTRONAUT, "room": "", "scene": "", "pos": Vector2.ZERO, "facing": 0}}
	if not ws:
		_udp_out = PacketPeerUDP.new()
		_udp_out.set_broadcast_enabled(true)
	_announce_left = 0.0
	lobby_changed.emit()
	roster_changed.emit()
	return OK


## Chamado pelos dois lados quando a partida realmente comeca (o host para de anunciar a sala).
func begin_game() -> void:
	in_game = true
	_close_udp_out()
	stop_browsing()


## Host: manda o cliente entrar no jogo junto com ele.
func start_game() -> void:
	if not is_host() or not partner_connected:
		return
	_rpc_start_game.rpc()


# ---------------------------------------------------------------- cliente
func join_game(ip: String, port: int = PORT) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip.strip_edges(), port)
	if err != OK:
		return err
	transport = Transport.ENET
	return _start_client(peer)


## Entra por WebSocket: url = "ws://host:24567" (ou "wss://..." atras de um proxy TLS). Funciona no navegador.
func join_url(url: String) -> Error:
	leave()
	var u := url.strip_edges()
	if not (u.begins_with("ws://") or u.begins_with("wss://")):
		u = "ws://" + u
	if u.split("://")[1].find(":") == -1 and u.begins_with("ws://"):
		u += ":%d" % WS_PORT
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(u)
	if err != OK:
		return err
	transport = Transport.WEBSOCKET
	return _start_client(peer)


func _start_client(peer: MultiplayerPeer) -> Error:
	_peer = peer
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	my_role = Role.SCIENTIST
	in_game = false
	pending_decision = -1
	_last_snap = {}
	roster = {}
	return OK


func start_browsing() -> void:
	stop_browsing()
	hosts.clear()
	if OS.has_feature("web"):
		return   # navegador nao tem UDP: so entra por ws://
	_udp_in = PacketPeerUDP.new()
	if _udp_in.bind(DISCOVERY_PORT) != OK:
		_udp_in = null  # porta ocupada (ex.: dois jogos na mesma maquina): segue so com IP manual


func stop_browsing() -> void:
	if _udp_in != null:
		_udp_in.close()
		_udp_in = null


func leave() -> void:
	stop_browsing()
	_close_udp_out()
	_fail_pending()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_peer = null
	mode = Mode.OFFLINE
	in_game = false
	partner_connected = false
	partner_room = ""
	pending_decision = -1
	_last_snap = {}
	roster = {}
	my_role = Role.ASTRONAUT
	lobby_changed.emit()
	roster_changed.emit()


func _close_udp_out() -> void:
	if _udp_out != null:
		_udp_out.close()
		_udp_out = null


# ---------------------------------------------------------------- loop
func _process(delta: float) -> void:
	if _udp_out != null:
		_announce_left -= delta
		if _announce_left <= 0.0:
			_announce_left = ANNOUNCE_INTERVAL
			var msg := ("%s|%s|%d" % [MAGIC, player_name, _port]).to_utf8_buffer()
			for target in _announce_targets():
				_udp_out.set_dest_address(target, DISCOVERY_PORT)
				_udp_out.put_packet(msg)
	if _udp_in != null:
		_poll_discovery()
	if is_host() and partner_connected and in_game:
		_snap_left -= delta
		if _snap_left <= 0.0:
			_snap_left = SNAPSHOT_INTERVAL
			_send_snapshot(false)
	if is_online() and in_game and has_partner():
		_pose_left -= delta
		if _pose_left <= 0.0:
			_pose_left = POSE_INTERVAL
			_flush_pose()


## Broadcast geral + broadcast da sub-rede (/24) de cada placa + localhost (teste na mesma maquina).
func _announce_targets() -> Array[String]:
	var out: Array[String] = ["255.255.255.255", "127.0.0.1"]
	for ip in local_ips():
		var p := ip.split(".")
		if p.size() == 4:
			var b := "%s.%s.%s.255" % [p[0], p[1], p[2]]
			if not out.has(b):
				out.append(b)
	return out


func _poll_discovery() -> void:
	var changed := false
	var now := Time.get_ticks_msec() / 1000.0
	while _udp_in.get_available_packet_count() > 0:
		var pkt := _udp_in.get_packet().get_string_from_utf8()
		var ip := _udp_in.get_packet_ip()
		var parts := pkt.split("|")
		if parts.size() != 3 or parts[0] != MAGIC or ip == "":
			continue
		if not hosts.has(ip):
			changed = true
		hosts[ip] = {"name": parts[1], "port": int(parts[2]), "seen": now}
	for ip in hosts.keys():
		if now - float(hosts[ip]["seen"]) > HOST_TIMEOUT:
			hosts.erase(ip)
			changed = true
	if changed:
		lobby_changed.emit()


# ---------------------------------------------------------------- conexao
func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	if in_game or roster.size() > MAX_CLIENTS:
		_kick(id)   # sala cheia ou partida em andamento
		return
	var role := _free_role()
	if role < 0:
		_kick(id)
		return
	roster[id] = {"name": "Jogador", "role": role, "room": "", "scene": "", "pos": Vector2.ZERO, "facing": 0}
	partner_connected = true
	_broadcast_roster()
	lobby_changed.emit()
	roster_changed.emit()


func _kick(id: int) -> void:
	if _peer is WebSocketMultiplayerPeer:
		(_peer as WebSocketMultiplayerPeer).disconnect_peer(id)
	elif _peer is ENetMultiplayerPeer:
		(_peer as ENetMultiplayerPeer).disconnect_peer(id)


func _free_role(wanted: int = -1) -> int:
	var used := {}
	for id in roster:
		if int(id) != 1:
			used[int(roster[id]["role"])] = true
	if wanted >= 0:
		return wanted if (wanted in CLIENT_ROLE_ORDER and not used.has(wanted)) else -1
	for r in CLIENT_ROLE_ORDER:
		if not used.has(int(r)):
			return int(r)
	return -1


func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not roster.has(id):
		return
	roster.erase(id)
	partner_connected = roster.size() > 1
	if not partner_connected:
		partner_room = ""
		_last_snap = {}
	_broadcast_roster()
	lobby_changed.emit()
	roster_changed.emit()
	partner_left.emit()


func _on_connected_to_server() -> void:
	_rpc_hello.rpc_id(1, player_name)
	connected_to_host.emit()


func _on_connection_failed() -> void:
	leave()
	connection_failed.emit()


func _on_server_disconnected() -> void:
	var was_in_game := in_game
	leave()
	if was_in_game:
		host_left.emit()
		UI.dismiss_all()
		GameState.reset()
		get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
		UI.toast(tr("O host saiu da partida. Voltando ao menu."), 5.0)
	else:
		connection_failed.emit()


# ---------------------------------------------------------------- snapshot (host -> cliente)
func snapshot() -> Dictionary:
	var out := {}
	for node_name in SYNC:
		var n := get_node("/root/" + String(node_name))
		var d := {}
		for v in SYNC[node_name]:
			var val: Variant = n.get(v)
			d[v] = val.duplicate(true) if (val is Array or val is Dictionary) else val
		out[node_name] = d
	return out


func apply_snapshot(snap: Dictionary) -> void:
	for node_name in SYNC:
		if not snap.has(node_name):
			continue
		var n := get_node("/root/" + String(node_name))
		var d: Dictionary = snap[node_name]
		var before: Dictionary = _last_snap.get(node_name, {})
		if before == d:
			continue
		for v in d:
			var cur: Variant = n.get(v)
			if cur is Array:
				(cur as Array).assign(d[v])   # mantem o tipo (Array[String]) e a referencia
			elif d[v] is Dictionary:
				n.set(v, (d[v] as Dictionary).duplicate(true))
			else:
				n.set(v, d[v])
	# avisa a interface so do que mudou
	var inv_changed := false
	for k in ["inventory", "storage", "capsule_item", "capsule_ready", "capsule_hold"]:
		if _section(snap, "GameState").get(k) != _section(_last_snap, "GameState").get(k):
			inv_changed = true
	if _section(snap, "GameState") != _section(_last_snap, "GameState"):
		GameState.changed.emit()
	if inv_changed:
		GameState.inventory_changed.emit()
	if _section(snap, "Missions") != _section(_last_snap, "Missions"):
		Missions.changed.emit()
	if _section(snap, "Voyage") != _section(_last_snap, "Voyage"):
		Voyage.changed.emit()
	if _section(snap, "Solar") != _section(_last_snap, "Solar"):
		Solar.changed.emit()
	if _section(snap, "MissionState") != _section(_last_snap, "MissionState"):
		MissionState.changed.emit()
	_last_snap = snap


func _section(snap: Dictionary, key: String) -> Dictionary:
	var d: Dictionary = snap.get(key, {})
	if key == "Solar" and d.has("_t"):
		d = d.duplicate()
		d.erase("_t")   # o relogio do terminal solar muda sempre: nao conta como mudanca
	return d


func _send_snapshot(_reliable_now: bool) -> void:
	if not is_host() or not partner_connected:
		return
	_rpc_snapshot.rpc(snapshot())


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(snap: Dictionary) -> void:
	if is_client():
		apply_snapshot(snap)


# ---------------------------------------------------------------- chamadas da base ao host
## Executa autoload.metodo(args) NO HOST e devolve o resultado. Offline/host: chama direto.
## `fallback` volta se a conexao cair no meio.
func call_host(target: String, method: String, args: Array = [], fallback: Variant = null) -> Variant:
	if not is_client():
		return get_node("/root/" + target).callv(method, args)
	if not _linked():
		return fallback   # sem conexao: ninguem vai responder
	_req_id += 1
	var id := _req_id
	_waiting[id] = true
	_rpc_call.rpc_id(1, id, target, method, args)
	while not _results.has(id):
		await _result_ready
	var r: Variant = _results[id]
	_results.erase(id)
	_waiting.erase(id)
	return fallback if r == null else r


@rpc("any_peer", "call_remote", "reliable")
func _rpc_call(id: int, target: String, method: String, args: Array) -> void:
	if not is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	var result: Variant = null
	var key := "%s.%s" % [target, method]
	var allowed: bool = REMOTE_CALLS.has(target) and (REMOTE_CALLS[target] as Array).has(method)
	if allowed and CALL_ROLES.has(key):
		var role: int = int(roster.get(sender, {}).get("role", -1))
		allowed = (CALL_ROLES[key] as Array).has(role)
	if allowed:
		result = get_node("/root/" + target).callv(method, args)
	else:
		push_warning("Net: chamada remota recusada: %s" % key)
	# snapshot ANTES do resultado (canal confiavel e ordenado): quando call_host() volta no cliente,
	# o espelho do estado ja inclui o efeito da decisao.
	_send_snapshot(true)
	_rpc_result.rpc_id(sender, id, result)


@rpc("authority", "call_remote", "reliable")
func _rpc_result(id: int, result: Variant) -> void:
	_results[id] = result
	_result_ready.emit()


func _fail_pending() -> void:
	# conexao caiu: libera quem esta esperando o host (call_host devolve o fallback)
	for i in _waiting.keys():
		if not _results.has(i):
			_results[i] = null
	_result_ready.emit()


# ---------------------------------------------------------------- eventos pontuais
@rpc("authority", "call_remote", "reliable")
func _rpc_start_game() -> void:
	if is_client():
		game_start_requested.emit()


func _on_notice(text: String) -> void:
	if is_host() and partner_connected and in_game:
		_rpc_notice.rpc(text)


@rpc("authority", "call_remote", "reliable")
func _rpc_notice(text: String) -> void:
	if is_client():
		UI.toast(text, 4.0)


func _on_failed(reason: String) -> void:
	if is_host() and partner_connected and in_game:
		_send_snapshot(true)
		_rpc_failed.rpc(reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_failed(reason: String) -> void:
	if is_client():
		GameState.failed.emit(reason)


func _on_exploded() -> void:
	if is_host() and partner_connected and in_game:
		_send_snapshot(true)
		_rpc_exploded.rpc()


@rpc("authority", "call_remote", "reliable")
func _rpc_exploded() -> void:
	if is_client():
		GameState.exploded.emit()


## Host: decisao no game over (0 recomecar, 1 menu inicial).
func send_restart_decision(choice: int) -> void:
	if is_host() and partner_connected:
		_rpc_restart.rpc(choice)


@rpc("authority", "call_remote", "reliable")
func _rpc_restart(choice: int) -> void:
	if is_client():
		pending_decision = choice
		restart_decided.emit(choice)


## Cliente: espera o host decidir (ou volta ao menu se a conexao cair).
func wait_restart_decision() -> int:
	while pending_decision < 0:
		if not is_client():
			return 1
		await restart_decided
	var c := pending_decision
	pending_decision = -1
	return c


# ---------------------------------------------------------------- jogadores, papeis e posicao
func _broadcast_roster() -> void:
	if not is_host():
		return
	var pub := {}
	for id in roster:
		var e: Dictionary = roster[id]
		pub[id] = {"name": e["name"], "role": e["role"], "room": e["room"]}
	if multiplayer.get_peers().size() > 0:
		_rpc_roster.rpc(pub)


@rpc("authority", "call_remote", "reliable")
func _rpc_roster(pub: Dictionary) -> void:
	if not is_client():
		return
	var fresh := {}
	for id in pub:
		var old: Dictionary = roster.get(id, {})
		fresh[id] = {
			"name": pub[id]["name"], "role": int(pub[id]["role"]), "room": pub[id]["room"],
			"scene": old.get("scene", ""), "pos": old.get("pos", Vector2.ZERO), "facing": old.get("facing", 0),
		}
	roster = fresh
	my_role = int(roster.get(multiplayer.get_unique_id(), {}).get("role", Role.SCIENTIST))
	partner_connected = roster.size() > 1
	var host_room := String(roster.get(1, {}).get("room", ""))
	if host_room != partner_room:
		partner_room = host_room
		partner_room_changed.emit()
	roster_changed.emit()
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(pname: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		roster[id]["name"] = pname.strip_edges().left(20)
		_broadcast_roster()
		lobby_changed.emit()
		roster_changed.emit()


## Cliente (antes de comecar): pede para trocar de papel; o host valida e avisa todo mundo.
func request_role(role: int) -> void:
	if is_client() and _linked():
		_rpc_request_role.rpc_id(1, role)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_role(role: int) -> void:
	if not is_host() or in_game:
		return
	var id := multiplayer.get_remote_sender_id()
	if not roster.has(id) or _free_role(role) < 0:
		return
	roster[id]["role"] = role
	_broadcast_roster()
	lobby_changed.emit()
	roster_changed.emit()


## Chamado todo quadro pelo game.gd: a posicao so sai a cada POSE_INTERVAL.
func report_pose(scene_path: String, pos: Vector2, facing: int) -> void:
	_my_pose = {"scene": scene_path, "pos": pos, "facing": facing}
	_pose_dirty = true


## Ha um peer de verdade conectado (nos testes unitarios o modo e forcado sem rede).
func _linked() -> bool:
	var mp := multiplayer.multiplayer_peer
	return mp != null and not (mp is OfflineMultiplayerPeer) and mp.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


func _flush_pose() -> void:
	if not _pose_dirty or not _linked():
		return
	_pose_dirty = false
	if is_host():
		roster[1].merge(_my_pose, true)
		var poses := {}
		for id in roster:
			var e: Dictionary = roster[id]
			poses[id] = {"scene": e["scene"], "pos": e["pos"], "facing": e["facing"]}
		_rpc_poses.rpc(poses)
	elif is_client():
		_rpc_pose.rpc_id(1, String(_my_pose["scene"]), _my_pose["pos"], int(_my_pose["facing"]))


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_pose(scene_path: String, pos: Vector2, facing: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		roster[id]["scene"] = scene_path
		roster[id]["pos"] = pos
		roster[id]["facing"] = facing


@rpc("authority", "call_remote", "unreliable")
func _rpc_poses(poses: Dictionary) -> void:
	if not is_client():
		return
	for id in poses:
		if roster.has(id):
			roster[id].merge(poses[id], true)


# ---------------------------------------------------------------- presenca do parceiro
## Texto da sala onde estou (para o HUD dos outros). O host reenvia para todos.
func send_room(room_label: String) -> void:
	if not has_partner() or not _linked():
		return
	if is_host():
		roster[1]["room"] = room_label
		_broadcast_roster()
	else:
		_rpc_room.rpc_id(1, room_label)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_room(room_label: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if roster.has(id):
		roster[id]["room"] = room_label
		partner_room = room_label
		_broadcast_roster()
		partner_room_changed.emit()
