extends Control
## Tela de grade de itens: Inventario (6 espacos) e Armario (20 espacos).
## Usa as imagens recortadas dos menus (assets/ui/menu_*.png).
## Navegue com W A S D / setas, F ou Enter escolhe, Esc fecha (I / Tab tambem fecha o inventario).
## O dono da tela espera:  var i = await grid.picked   (indice do espaco, ou -1 para fechar)

signal picked(index: int)

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")
const INK := Color("1b2a5c")
const CURSOR_COLOR := Color("1f5cff")
const ICON_COLORS := {
	"cafe": Color("8a5a3a"), "croquete": Color("e0963a"),
	"refri": Color("d44a4a"), "racao": Color("5aa860"),
	"pacote_fungos": Color("7a5aa8"), "pacote_quente": Color("c8602a"), "amostra": Color("2a9aa8"),
}
const VIEW := Vector2(1536, 1024)
const SHOW_HEIGHT := 940.0   # altura da imagem na tela

# posicoes medidas nas imagens recortadas: [x, y, largura, altura]
const ARM_SLOTS := [
	[80, 254, 228, 208], [330, 254, 228, 208], [575, 254, 228, 208], [820, 254, 228, 208], [1065, 254, 228, 208],
	[80, 482, 228, 208], [330, 482, 228, 208], [575, 482, 228, 208], [820, 482, 228, 208], [1065, 482, 228, 208],
	[80, 710, 228, 208], [330, 710, 228, 208], [575, 710, 228, 208], [820, 710, 228, 208], [1065, 710, 228, 208],
	[80, 937, 228, 208], [330, 937, 228, 208], [575, 937, 228, 208], [820, 937, 228, 208], [1065, 937, 228, 208]]
const ARM_DESC := [45, 1222, 1340, 290]
const INV_SLOTS := [
	[115, 612, 220, 183], [366, 612, 260, 183], [650, 612, 245, 183],
	[110, 816, 232, 181], [366, 816, 260, 181], [650, 816, 245, 181]]
const INV_DESC := [40, 1045, 920, 215]
const INV_PREVIEW := [40, 155, 920, 400]

var kind := "inventory"
var cols := 3
var slots: Array[Rect2] = []
var items: Array = []            # id do item em cada espaco ("" = vazio)
var selected := 0
var desc_provider: Callable      # (indice, id) -> texto da descricao
var close_actions: Array[String] = ["ui_cancel"]

var _scale := 1.0
var _origin := Vector2.ZERO
var _desc_rect := Rect2()
var _preview_rect := Rect2()
var _icons: Array[ColorRect] = []
var _icon_labels: Array[Label] = []
var _cursor: Control
var _desc: Label
var _prev_icon: ColorRect
var _prev_label: Label
var _prev_name: Label


## kind: "inventory" ou "storage"
func configure(which: String) -> void:
	kind = which
	var tex: Texture2D
	var raw_slots: Array
	if which == "storage":
		tex = load("res://assets/ui/menu_armario.png")
		raw_slots = ARM_SLOTS
		cols = 5
		_desc_rect = _rect(ARM_DESC)
	else:
		tex = load("res://assets/ui/menu_inventario.png")
		raw_slots = INV_SLOTS
		cols = 3
		_desc_rect = _rect(INV_DESC)
		_preview_rect = _rect(INV_PREVIEW)
		close_actions = ["ui_cancel", "inventory"]
	for r in raw_slots:
		slots.append(_rect(r))
	_scale = SHOW_HEIGHT / float(tex.get_height())
	_origin = Vector2((VIEW.x - tex.get_width() * _scale) / 2.0, (VIEW.y - SHOW_HEIGHT) / 2.0)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var bg := TextureRect.new()
	bg.texture = tex
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.position = _origin
	bg.size = tex.get_size() * _scale
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	for i in slots.size():
		var box := _to_screen(slots[i]).grow(-14.0)
		var icon := ColorRect.new()
		icon.position = box.position
		icon.size = box.size
		icon.visible = false
		add_child(icon)
		var lab := _label("", 32, Color.WHITE)
		lab.position = Vector2.ZERO
		lab.size = box.size
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		icon.add_child(lab)
		_icons.append(icon)
		_icon_labels.append(lab)

	_cursor = Control.new()
	_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor.draw.connect(_draw_cursor)
	add_child(_cursor)

	var d := _to_screen(_desc_rect)
	_desc = _label("", 24, INK)
	_desc.position = d.position + Vector2(26, 18)
	_desc.size = d.size - Vector2(52, 30)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_desc)

	if _preview_rect.size.x > 0.0:
		var p := _to_screen(_preview_rect)
		_prev_icon = ColorRect.new()
		_prev_icon.size = Vector2(150, 150)
		_prev_icon.position = p.position + Vector2((p.size.x - 150.0) / 2.0, 36)
		_prev_icon.visible = false
		add_child(_prev_icon)
		_prev_label = _label("", 64, Color.WHITE)
		_prev_label.size = _prev_icon.size
		_prev_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_prev_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_prev_icon.add_child(_prev_label)
		_prev_name = _label("", 32, Color("dfe9ff"))
		_prev_name.position = Vector2(p.position.x, p.position.y + p.size.y - 76)
		_prev_name.size = Vector2(p.size.x, 40)
		_prev_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(_prev_name)


## Define o conteudo (lista de ids); espacos alem do fim ficam vazios.
func set_items(list: Array) -> void:
	items.clear()
	for i in slots.size():
		items.append(str(list[i]) if i < list.size() else "")
	selected = clampi(selected, 0, slots.size() - 1)
	refresh()


func refresh() -> void:
	for i in slots.size():
		var id: String = items[i]
		_icons[i].visible = id != ""
		if id != "":
			_icons[i].color = ICON_COLORS.get(id, Color("6a7ad0"))
			_icon_labels[i].text = GameState.item_short(id)
	var sel_id: String = items[selected]
	_desc.text = str(desc_provider.call(selected, sel_id)) if desc_provider.is_valid() else sel_id
	if _prev_icon != null:
		_prev_icon.visible = sel_id != ""
		if sel_id != "":
			_prev_icon.color = ICON_COLORS.get(sel_id, Color("6a7ad0"))
			_prev_label.text = GameState.item_short(sel_id)
		_prev_name.text = GameState.item_name(sel_id) if sel_id != "" else "Vazio"
	var r := _to_screen(slots[selected]).grow(6.0)
	_cursor.position = r.position
	_cursor.size = r.size
	_cursor.queue_redraw()


func _draw_cursor() -> void:
	var s := _cursor.size
	var l := 30.0
	var t := 7.0
	var c := CURSOR_COLOR
	for corner in [Vector2(0, 0), Vector2(s.x, 0), Vector2(0, s.y), Vector2(s.x, s.y)]:
		var sx := 1.0 if corner.x == 0.0 else -1.0
		var sy := 1.0 if corner.y == 0.0 else -1.0
		_cursor.draw_line(corner + Vector2(0, sy * t / 2.0), corner + Vector2(sx * l, sy * t / 2.0), c, t)
		_cursor.draw_line(corner + Vector2(sx * t / 2.0, 0), corner + Vector2(sx * t / 2.0, sy * l), c, t)


# Fica quieto enquanto um menu de escolha ou dialogo estiver aberto (a UI cuida das teclas).
func _input(event: InputEvent) -> void:
	if not visible or UI._menu_active or UI._dialog_active:
		return
	var move := Vector2i.ZERO
	if event.is_action_pressed("move_left", true):
		move = Vector2i(-1, 0)
	elif event.is_action_pressed("move_right", true):
		move = Vector2i(1, 0)
	elif event.is_action_pressed("move_up", true):
		move = Vector2i(0, -1)
	elif event.is_action_pressed("move_down", true):
		move = Vector2i(0, 1)
	if move != Vector2i.ZERO:
		get_viewport().set_input_as_handled()
		_move(move)
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		picked.emit(selected)
		return
	for a in close_actions:
		if event.is_action_pressed(a) and not event.is_echo():
			get_viewport().set_input_as_handled()
			picked.emit(-1)
			return


func _move(d: Vector2i) -> void:
	var col := selected % cols
	var row := selected / cols
	col = clampi(col + d.x, 0, cols - 1)
	row = clampi(row + d.y, 0, (slots.size() - 1) / cols)
	selected = mini(row * cols + col, slots.size() - 1)
	refresh()


func _rect(a: Array) -> Rect2:
	return Rect2(a[0], a[1], a[2], a[3])


func _to_screen(r: Rect2) -> Rect2:
	return Rect2(_origin + r.position * _scale, r.size * _scale)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
