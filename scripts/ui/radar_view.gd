extends Node2D
class_name RadarView
## Radar da nave (assets/ui/radar_frames.tres: octogono com varredura). Quando ha um objeto perto
## (asteroide visivel) o sprite do alvo (assets/ui/radar_blip_frames.tres) aparece em cima do radar,
## mais perto do centro quanto mais proximo o objeto. Sem viagem: octogono parado (radar.base).

const BASE := preload("res://assets/ui/radar/base.png")
const RADIUS_PX := 6.0      # raio util do radar, em pixels da arte (16x16)

var _sweep: AnimatedSprite2D
var _idle: Sprite2D
var _blip: AnimatedSprite2D
var _radar_scale := 1.0


func setup(radar_scale: float) -> void:
	_radar_scale = radar_scale
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_idle = Sprite2D.new()
	_idle.texture = BASE
	_idle.scale = Vector2.ONE * radar_scale
	add_child(_idle)
	_sweep = AnimatedSprite2D.new()
	_sweep.sprite_frames = load("res://assets/ui/radar_frames.tres")
	_sweep.scale = Vector2.ONE * radar_scale
	add_child(_sweep)
	_blip = AnimatedSprite2D.new()
	_blip.sprite_frames = load("res://assets/ui/radar_blip_frames.tres")
	_blip.scale = Vector2.ONE * radar_scale * 0.4
	_blip.visible = false
	add_child(_blip)
	set_state(false, -1.0, 0.0)


## active: radar ligado (viagem); dist: 0..1 (0 = em cima da nave, 1 = no limite) ou -1 = sem objeto;
## angle: direcao do objeto (radianos).
func set_state(active: bool, dist: float, angle: float) -> void:
	_idle.visible = not active
	_sweep.visible = active
	if active:
		if not _sweep.is_playing():
			_sweep.play("default")
	else:
		_sweep.stop()
	var show := active and dist >= 0.0
	_blip.visible = show
	if show:
		if not _blip.is_playing():
			_blip.play("default")
		var d := lerpf(1.5, RADIUS_PX, clampf(dist, 0.0, 1.0)) * _radar_scale
		_blip.position = Vector2(cos(angle), sin(angle)) * d


## Estado do radar a partir da viagem atual (objeto = asteroide ja visivel).
static func from_voyage() -> Dictionary:
	if not Voyage.active:
		return {"active": false, "dist": -1.0, "angle": 0.0}
	if Voyage.asteroid_visible():
		var eta := float(Voyage.asteroid["eta"])
		var ang := fposmod(float(Voyage.asteroid.get("speed", 1.0)) * 37.0, TAU)
		return {"active": true, "dist": clampf(eta / Voyage.SEE_ASTEROID_AT, 0.0, 1.0), "angle": ang}
	return {"active": true, "dist": -1.0, "angle": 0.0}
