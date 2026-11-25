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
	g.add_point(0.0, Color(0.08, 0.07, 0.14, 1))
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
	for c in container.get_children():
		c.queue_free()

	var star_icon: Texture2D = _get_icon("star")
	var locked_icon: Texture2D = _get_icon("close")

	var ids := GameData.ACHIEVEMENTS.keys()
	ids.sort()
	for id in ids:
		var info: Dictionary = GameData.ACHIEVEMENTS[id]
		var unlocked: bool = GlobalData.is_ach_unlocked(id)
		var hidden: bool = info.get("hidden", false)
		var title: String = info.get("title", "")
		var desc: String = info.get("desc", "")

		var display_title: String = title
		var display_desc: String = desc
		if hidden and not unlocked:
			display_title = "???"
			display_desc = "尚未解锁"

		# 卡片容器
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 2)

		# 标题行（图标 + 标题）
		var title_box := HBoxContainer.new()
		title_box.add_theme_constant_override("separation", 10)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(22, 22)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP
		if unlocked and star_icon:
			icon_rect.texture = star_icon
			icon_rect.modulate = Color(1, 0.85, 0.5, 1)
		elif not unlocked and not hidden and locked_icon:
			icon_rect.texture = locked_icon
			icon_rect.modulate = Color(0.45, 0.45, 0.5, 1)
		else:
			icon_rect.modulate = Color(0.45, 0.45, 0.5, 0.3)
		title_box.add_child(icon_rect)

		var t := Label.new()
		t.text = display_title
		t.add_theme_font_size_override("font_size", 18)
		t.add_theme_color_override("font_color", Color(1, 0.85, 0.5, 1) if unlocked else Color(0.55, 0.55, 0.6, 1))
		title_box.add_child(t)
		title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		card.add_child(title_box)

		var d := Label.new()
		d.text = "   " + display_desc
		d.add_theme_font_size_override("font_size", 14)
		d.add_theme_color_override("font_color", Color(0.65, 0.68, 0.78, 1))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(d)

		var sep := HSeparator.new()
		sep.add_theme_stylebox_override("separator", _sep_style(Color(0.25, 0.28, 0.38, 0.4)))
		card.add_child(sep)

		container.add_child(card)

func _sep_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s
