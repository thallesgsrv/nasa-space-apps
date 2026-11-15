extends Node
## Audio do jogo (autoload "Audio"): musica/ambiente de cada sala (com fade entre uma e outra)
## e efeitos (menu, explosao). Para ADICIONAR o ambiente de uma sala: coloque o arquivo em
## assets/audio/music/ e acrescente a linha na tabela ROOM_MUSIC (chave = nome da cena da sala).
## Salas sem arquivo ficam em silencio.

const ROOM_MUSIC := {
	"cafeteria": "res://assets/audio/music/cafeteria.mp3",
	"laboratorio": "res://assets/audio/music/laboratorio.mp3",
	"sala_controle": "res://assets/audio/music/sala_controle.mp3",
	"dormitorio": "res://assets/audio/music/dormitorio.mp3",
	"armazem": "res://assets/audio/music/armazem.mp3",
	"camara_propulsao": "res://assets/audio/music/camara_propulsao.mp3",
	"sala_reator": "res://assets/audio/music/sala_reator.mp3",
}

const SFX := {
	"select": "res://assets/audio/sfx/select.wav",
	"explosao": "res://assets/audio/sfx/reator_explosao.mp3",
}

const MUSIC_DB := -8.0     # volume da musica
const SFX_DB := -2.0       # volume dos efeitos
const FADE_TIME := 0.9     # fade entre uma sala e outra

var current := ""          # sala cuja musica toca agora ("" = silencio)
var _music: Array[AudioStreamPlayer] = []
var _active := 0
var _sfx: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _cd: AudioStreamPlayer       # som da contagem do nucleo (termina na explosao)
var _cd_started := false
var _paused_room := ""     # sala que estava tocando quando a musica foi pausada (videos)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		add_child(p)
		_music.append(p)
	for i in 4:
		var p := AudioStreamPlayer.new()
		p.volume_db = SFX_DB
		add_child(p)
		_sfx.append(p)
	_cd = AudioStreamPlayer.new()
	_cd.volume_db = SFX_DB + 2.0
	add_child(_cd)


## Toca o ambiente da sala (com fade). Sala sem arquivo = silencio.
func play_room(room_id: String) -> void:
	if room_id == current:
		return
	current = room_id
	var path: String = ROOM_MUSIC.get(room_id, "")
	var old := _music[_active]
	_fade(old, -80.0, FADE_TIME, true)
	if path == "" or not ResourceLoader.exists(path):
		return
	_active = 1 - _active
	var p := _music[_active]
	var stream := load(path) as AudioStreamMP3
	stream.loop = true
	p.stream = stream
	p.volume_db = -80.0
	p.play()
	_fade(p, MUSIC_DB, FADE_TIME, false)


func stop_music(fade: float = 0.6) -> void:
	current = ""
	for p in _music:
		_fade(p, -80.0, fade, true)


## Pausa a musica (durante videos) e guarda qual era, para voltar depois.
func pause_music() -> void:
	_paused_room = current
	stop_music(0.3)


func resume_music() -> void:
	var r := _paused_room
	_paused_room = ""
	if r != "":
		play_room(r)


## Som da contagem do nucleo: o arquivo termina na explosao, entao ele entra quando faltam
## "duracao do arquivo" segundos e fica sincronizado com a contagem (pausa junto com os menus).
## remaining < 0 = sem contagem (para o som).
func sync_countdown(remaining: float, paused: bool) -> void:
	if remaining < 0.0:
		if _cd_started:
			_cd.stop()
			_cd_started = false
		return
	if not _cd_started and not paused:
		var path: String = SFX["explosao"]
		var stream := load(path) as AudioStream
		var length := stream.get_length()
		if remaining <= length:
			_cd.stream = stream
			_cd.play(length - remaining)
			_cd_started = true
	if _cd_started:
		_cd.stream_paused = paused


## Efeito sonoro curto. max_len > 0 corta o som depois desse tempo (em segundos).
func sfx(name: String, pitch: float = 1.0, max_len: float = 0.0) -> void:
	var path: String = SFX.get(name, "")
	if path == "" or not ResourceLoader.exists(path):
		return
	var p := _sfx[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx.size()
	p.stream = load(path)
	p.pitch_scale = pitch
	p.play()
	if max_len > 0.0:
		var tw := create_tween()
		tw.tween_property(p, "volume_db", -60.0, 0.12).set_delay(max_len)
		tw.tween_callback(func():
			p.stop()
			p.volume_db = SFX_DB)


func _fade(p: AudioStreamPlayer, to_db: float, time: float, stop_after: bool) -> void:
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, time)
	if stop_after:
		tw.tween_callback(func(): if p.volume_db <= -70.0: p.stop())
