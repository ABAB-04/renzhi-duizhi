extends Control

# 图标路径
const ICON_DIR := "res://assets/icons/"
const IMG_DIR := "res://assets/images/"
const GameData = preload("res://core/game_data.gd")

var _icons := {}
var _btn_continue: Button = null

func _get_icon(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var p: Resource = load(ICON_DIR + name + ".svg") if ResourceLoader.exists(ICON_DIR + name + ".svg") else null
	if p is Texture2D:
		_icons[name] = p
	else:
		_icons[name] = null
	return _icons[name]

func _get_image(name: String) -> Texture2D:
	var path := IMG_DIR + name + ".png"
	if ResourceLoader.exists(path):
		var p: Resource = load(path)
		if p is Texture2D:
			return p
	return null

@onready var btn_start: Button = $CenterContainer/VBoxContainer/BtnStart
@onready var btn_achievements: Button = $CenterContainer/VBoxContainer/BtnAchievements
@onready var btn_endings: Button = $CenterContainer/VBoxContainer/BtnEndings
@onready var btn_knowledge: Button = $CenterContainer/VBoxContainer/BtnKnowledge
@onready var btn_settings: Button = $CenterContainer/VBoxContainer/BtnSettings
@onready var btn_quit: Button = $CenterContainer/VBoxContainer/BtnQuit

func _ready() -> void:
	# 背景：优先用 AI 海报图（poster.png），没有则回退到程序化渐变
	var poster: Texture2D = _get_image("poster")
	if poster:
		var bg: ColorRect = $Background
		var bg_layer := TextureRect.new()
		bg_layer.texture = poster
		bg_layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg_layer.modulate = Color(1, 1, 1, 0.35)  # 压暗，让按钮文字清晰
		bg.add_child(bg_layer)
		bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_layer.z_index = 0
		bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		var bg: ColorRect = $Background
		var tex := GradientTexture2D.new()
		var g := Gradient.new()
		g.add_point(0.0, Color(0.08, 0.08, 0.18, 1))
		g.add_point(1.0, Color(0.02, 0.02, 0.08, 1))
		tex.gradient = g
		tex.fill_to = Vector2(0, 1)
		var bg_layer := TextureRect.new()
		bg_layer.texture = tex
		bg_layer.stretch_mode = TextureRect.STRETCH_SCALE
		bg.add_child(bg_layer)
		bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg_layer.z_index = 0
		bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 按钮样式 + 图标 + 信号
	_setup_main_btn(btn_start, "play", Color(0.29, 0.56, 0.85, 0.9), func(): get_tree().change_scene_to_file("res://scenes/personality.tscn"))
	_setup_sec_btn(btn_achievements, "star", Color(0.2, 0.25, 0.35, 0.9), func(): get_tree().change_scene_to_file("res://scenes/achievements.tscn"))
	_setup_sec_btn(btn_endings, "door", Color(0.22, 0.2, 0.35, 0.9), func(): get_tree().change_scene_to_file("res://scenes/endings.tscn"))
	_setup_sec_btn(btn_knowledge, "book", Color(0.2, 0.25, 0.35, 0.9), func(): get_tree().change_scene_to_file("res://scenes/knowledge.tscn"))
	_setup_sec_btn(btn_settings, "gear", Color(0.2, 0.25, 0.35, 0.9), func(): get_tree().change_scene_to_file("res://scenes/settings.tscn"))
	_setup_sec_btn(btn_quit, "close", Color(0.35, 0.2, 0.2, 0.9), func(): get_tree().quit())

	# 继续游戏按钮（有中途存档时显示在「开始争辩」上方）
	_add_continue_button()

	# 标题加发光效果
	var title: Label = $TopBar/TitleLabel
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.25, 0.45, 0.6))
	title.add_theme_constant_override("outline_size", 4)

	Audio.start_bgm()

func _setup_main_btn(btn: Button, icon_name: String, color: Color, cb: Callable) -> void:
	btn.pressed.connect(func(): Audio.play_sfx("select"))
	btn.pressed.connect(cb)
	_make_button_icon(btn, icon_name, Color(1, 1, 1, 1))
	_style_btn_states(btn, color, 12)

func _setup_sec_btn(btn: Button, icon_name: String, color: Color, cb: Callable) -> void:
	btn.pressed.connect(func(): Audio.play_sfx("click"))
	btn.pressed.connect(cb)
	_make_button_icon(btn, icon_name, Color(0.85, 0.88, 0.95, 1))
	_style_btn_states(btn, color, 10)

func _make_button_icon(btn: Button, icon_name: String, icon_color: Color) -> void:
	btn.text = ""
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var tex: Texture2D = _get_icon(icon_name)
	if tex:
		var icon := TextureRect.new()
		icon.texture = tex
		icon.stretch_mode = TextureRect.STRETCH_SCALE
		icon.custom_minimum_size = Vector2(20, 20)
		icon.modulate = icon_color
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(icon)

	var lbl := Label.new()
	lbl.text = _button_label(btn.name)
	lbl.add_theme_color_override("font_color", icon_color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(lbl)

	btn.add_child(hbox)
	hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _button_label(name: String) -> String:
	var hover_color := color.lightened(0.15)
	var press_color := color.darkened(0.15)
	var dis_color := Color(color.r, color.g, color.b, 0.4)
	btn.add_theme_stylebox_override("normal", _make_stylebox(color, radius))
	btn.add_theme_stylebox_override("hover", _make_stylebox(hover_color, radius))
	btn.add_theme_stylebox_override("pressed", _make_stylebox(press_color, radius))
	btn.add_theme_stylebox_override("focus", _make_stylebox(hover_color, radius))
	btn.add_theme_stylebox_override("disabled", _make_stylebox(dis_color, radius))

func _make_stylebox(bg: Color, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.border_color = Color(bg.r * 1.4, bg.g * 1.4, bg.b * 1.4, 0.4)
	s.set_border_width_all(1)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s
