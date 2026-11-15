class_name ItemIcons
extends RefCounted
## Imagens dos itens (assets/items). O cafe e animado (3 quadros com fumaca).
## Itens sem imagem aqui continuam aparecendo como quadrado colorido com 2 letras.

const FRAME_TIME := 0.35

const PATHS := {
	"cafe": ["res://assets/items/cafe_0.png", "res://assets/items/cafe_1.png", "res://assets/items/cafe_2.png"],
	"bolacha": ["res://assets/items/bolacha.png"],
	"refri": ["res://assets/items/refri.png"],
	"amostra": ["res://assets/items/amostra.png"],
	"agua": ["res://assets/items/agua.png"],
	"racao": ["res://assets/items/racao.png"],
	"pacote_fungos": ["res://assets/items/pacote_fungos.png"],
	"pacote_quente": ["res://assets/items/pacote_quente.png"],
}

static var _cache: Dictionary = {}


static func has_icon(id: String) -> bool:
	return PATHS.has(id)


static func frames(id: String) -> Array:
	if not _cache.has(id):
		var list: Array = []
		for p in PATHS.get(id, []):
			list.append(load(p))
		_cache[id] = list
	return _cache[id]


## Quadro da animacao para o tempo t (em segundos).
static func frame_at(id: String, t: float) -> Texture2D:
	var f := frames(id)
	if f.is_empty():
		return null
	return f[int(t / FRAME_TIME) % f.size()]
