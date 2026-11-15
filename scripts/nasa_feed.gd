extends Node
## Eventos solares para o jogo (autoload "NasaFeed").
## Ordem de fontes: (1) feed vivo baixado de NASA_FEED_URL (servico proprio, sem chave no navegador),
## (2) cache em user://nasa_feed.json, (3) arquivo local res://data/space_events.json (sempre existe).
## O jogo NUNCA chama api.nasa.gov direto: a chave fica em tools/nasa_feed_proxy.py (servidor).
## Formato: {"source": "DONKI"|"archive", "events": [{"kind": "flare", "class": "X9.0", "date": "AAAA-MM-DD", "title": "..."}]}
## Cada evento escolhido vira um selo REAL (intensidade real; a direcao da ejecao e sempre simulada).

signal loaded

const ARCHIVE_PATH := "res://data/space_events.json"
const CACHE_PATH := "user://nasa_feed.json"

var enabled := true
var source := "archive"       # "archive" (registro historico) ou o nome do servico (ex.: DONKI)
var events: Array = []
var _http: HTTPRequest


func _ready() -> void:
	load_best()
	var url := _feed_url()
	if url != "" and not Net.is_client():
		refresh(url)


func _feed_url() -> String:
	var env := OS.get_environment("NASA_FEED_URL")
	if env != "":
		return env
	return String(ProjectSettings.get_setting("nasa/feed_url", ""))


func load_best() -> void:
	for path in [CACHE_PATH, ARCHIVE_PATH]:
		if FileAccess.file_exists(path) and _parse(FileAccess.get_file_as_string(path)):
			return
	events = []


func _parse(text: String) -> bool:
	var json := JSON.new()
	if json.parse(text) != OK:
		return false
	var data: Variant = json.data
	if not (data is Dictionary) or not (data.get("events") is Array):
		return false
	var ok: Array = []
	for e in data["events"]:
		if e is Dictionary and e.get("kind") == "flare" and String(e.get("class", "")).length() >= 2 and String(e.get("date", "")) != "":
			ok.append(e)
	if ok.is_empty():
		return false
	events = ok
	source = String(data.get("source", "archive"))
	loaded.emit()
	return true


## Baixa o feed (so o host). Qualquer falha mantem o que ja esta carregado.
func refresh(url: String) -> void:
	if _http == null:
		_http = HTTPRequest.new()
		_http.timeout = 8.0
		add_child(_http)
		_http.request_completed.connect(_on_done)
	if _http.request(url) != OK:
		push_warning("NasaFeed: nao foi possivel iniciar o download")


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var text := body.get_string_from_utf8()
	if _parse(text):
		var f := FileAccess.open(CACHE_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()


## Intensidade de jogo (escala do terminal solar; >= Solar.HIT_FLUX e perigosa) a partir da classe da erupcao.
func flux_for(flare_class: String) -> float:
	var letter := flare_class.substr(0, 1).to_upper()
	var num := flare_class.substr(1).to_float()
	match letter:
		"X":
			return 6.5 + minf(3.0, num / 4.0)
		"M":
			return minf(5.9, 4.0 + num / 10.0)
		_:
			return minf(3.9, 2.0 + num / 5.0)


## Sorteia um evento do feed. Devolve {} se nao ha eventos (ai o jogo usa o sorteio antigo).
func pick_flare() -> Dictionary:
	if not enabled or events.is_empty():
		return {}
	var e: Dictionary = events.pick_random()
	var live := source != "archive"
	var label := tr("REAL: erupção %s de %s (%s). Intensidade real; direção simulada.") % [
		e["class"], e["date"], tr("dado recente da NASA") if live else tr("registro histórico"),
	]
	return {"tag": MissionState.TAG_REAL, "label": label, "class": e["class"], "date": e["date"], "flux": flux_for(String(e["class"]))}
