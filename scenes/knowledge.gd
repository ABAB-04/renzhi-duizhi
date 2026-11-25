extends Control

const GameData = preload("res://core/game_data.gd")
const ICON_DIR := "res://assets/icons/"

var _icon_cache := {}
func _get_icon(name: String) -> Texture2D:
	if _icon_cache.has(name):
		return _icon_cache[name]
	var p: Resource = load(ICON_DIR + name + ".svg") if ResourceLoader.exists(ICON_DIR + name + ".svg") else null
	_icon_cache[name] = p if p is Texture2D else null
	return _icon_cache[name]

@onready var container: VBoxContainer = $Margin/VBox/ScrollContainer/VBox
@onready var btn_back: Button = $Margin/VBox/BackBtn
@onready var lock_label: Label = $Margin/VBox/LockLabel

func _ready() -> void:
	_gradient_bg()
	_refresh()
	btn_back.pressed.connect(func(): Audio.play_sfx("click"))
	btn_back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_btn_style(btn_back, Color(0.29, 0.56, 0.85, 0.9), 10)

func _gradient_bg() -> void:
	var bg: ColorRect = $Bg
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.add_point(0.0, Color(0.06, 0.08, 0.14, 1))
	g.add_point(1.0, Color(0.02, 0.02, 0.08, 1))
	tex.gradient = g
	tex.fill_to = Vector2(0, 1)
	var layer := TextureRect.new()
	layer.texture = tex
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	bg.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _btn_style(btn: Button, color: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(1)
	s.border_color = Color(1, 1, 1, 0.15)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate(); h.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", h)
	var p := s.duplicate(); p.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", p)

func _refresh() -> void:
	var unlocked: bool = GlobalData.is_ach_unlocked("ach_logic_break") or GlobalData.is_ach_unlocked("ach_critical")

	if not unlocked:
		lock_label.visible = true
		lock_label.text = "🔒 完成一次完整争辩通关后解锁（击破逻辑 或 两道题全对）"
		return

	lock_label.visible = false

	var icons: Texture2D = _get_icon("reason")

	for entry in GameData.KNOWLEDGE_BASE:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 3)

		# 名称行（图标 + ◆ 名称）
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 8)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(18, 18)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP
		if icons:
			icon_rect.texture = icons
			icon_rect.modulate = Color(0.78, 0.88, 1, 0.9)
		name_row.add_child(icon_rect)

		var name_l := Label.new()
		name_l.text = entry.get("name", "")
		name_l.add_theme_font_size_override("font_size", 20)
		name_l.add_theme_color_override("font_color", Color(0.85, 0.92, 1, 1))
		name_row.add_child(name_l)
		name_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		box.add_child(name_row)

		var desc_l := Label.new()
		desc_l.text = "    定义：" + entry.get("desc", "")
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_l.add_theme_font_size_override("font_size", 15)
		desc_l.add_theme_color_override("font_color", Color(0.7, 0.78, 0.9, 1))
		box.add_child(desc_l)

		var ex_l := Label.new()
		ex_l.text = "    示例：" + entry.get("example", "")
		ex_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ex_l.add_theme_font_size_override("font_size", 14)
		ex_l.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7, 1))
		box.add_child(ex_l)

		var sep := HSeparator.new()
		sep.add_theme_stylebox_override("separator", _sep_style(Color(0.25, 0.28, 0.38, 0.4)))
		box.add_child(sep)

		container.add_child(box)

func _sep_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
