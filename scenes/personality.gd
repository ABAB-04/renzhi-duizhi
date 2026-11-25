extends Control

# ============================================================
# personality.gd — 开辩前的性格选择（美化版）
# ============================================================

const GameData = preload("res://core/game_data.gd")
const ICON_DIR := "res://assets/icons/"

var _icons := {}
func _get_icon(name: String) -> Texture2D:
	if _icons.has(name):
		return _icons[name]
	var p: Resource = load(ICON_DIR + name + ".svg") if ResourceLoader.exists(ICON_DIR + name + ".svg") else null
	_icons[name] = p if p is Texture2D else null
	return _icons[name]

func _persona_icon_file(id: String) -> String:
	match id:
		"hot": return "fire"
		"calm": return "ice"
		"nice": return "tea"
		"social": return "megaphone"
		"plain": return "mask"
	return ""

@onready var grid: GridContainer = $Margin/VBox/Grid
@onready var btn_back: Button = $Margin/VBox/BottomBox/BtnBack
@onready var btn_start: Button = $Margin/VBox/BottomBox/BtnStart
@onready var hard_toggle: CheckButton = $Margin/VBox/BottomBox/HardToggle

var buttons: Dictionary = {}
var selected: String = "hot"
var card_borders: Dictionary = {}

func _ready() -> void:
	selected = GlobalData.personality
	if not GameData.PERSONALITIES.has(selected):
		selected = "hot"

	# 渐变背景
	_gradient_background()

	_build_cards()
	_refresh_selection()

	btn_back.pressed.connect(func(): Audio.play_sfx("click"))
	btn_back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	btn_start.pressed.connect(func(): Audio.play_sfx("open"))
	btn_start.pressed.connect(_on_start)
	_bottom_buttons_style()

	# 通关过任意结局后，才显示困难模式开关
	hard_toggle.visible = GlobalData.beaten_once
	hard_toggle.button_pressed = GlobalData.hard_mode
	hard_toggle.toggled.connect(func(on: bool): GlobalData.hard_mode = on)

func _gradient_background() -> void:
	var bg: ColorRect = $Bg
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.add_point(0.0, Color(0.07, 0.07, 0.16, 1))
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

func _bottom_buttons_style() -> void:
	_btn_style(btn_back, Color(0.2, 0.25, 0.35, 0.9), 10)
	_btn_style(btn_start, Color(0.29, 0.56, 0.85, 0.95), 12)

func _btn_style(btn: Button, color: Color, radius: int) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = Color(color.r * 1.5, color.g * 1.5, color.b * 1.5, 0.5)
	s.set_border_width_all(1)
	s.content_margin_left = 20
	s.content_margin_right = 20
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", s)
	var h := s.duplicate(); h.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", h)
	var p := s.duplicate(); p.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", p)

func _build_cards() -> void:
	for id in GameData.PERSONALITIES.keys():
		var p: Dictionary = GameData.PERSONALITIES[id]
		var color := Color.html(p.get("color", "#ffffff"))

		# 卡片容器（MarginContainer 带内边距）
		var card := Button.new()
		card.custom_minimum_size = Vector2(0, 150)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.text = ""
		card.pressed.connect(func(): Audio.play_sfx("select"))
		card.pressed.connect(_on_card_pressed.bind(id))
		# 卡片悬停时稍微抬起来
		card.mouse_entered.connect(func(): _animate_card(card, 1.015))
		card.mouse_exited.connect(func(): _animate_card(card, 1.0))

		# 卡片内边距
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 14)
		margin.add_theme_constant_override("margin_right", 14)
		margin.add_theme_constant_override("margin_top", 10)
		margin.add_theme_constant_override("margin_bottom", 10)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 14)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(hbox)

		# 图标
		var icon_name: String = _persona_icon_file(id)
		var icon_tex: Texture2D = _get_icon(icon_name)
		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(48, 48)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP
		icon_rect.modulate = color
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if icon_tex:
			icon_rect.texture = icon_tex
		else:
			var lbl := Label.new()
			lbl.text = p.get("icon", "")
			lbl.add_theme_font_size_override("font_size", 32)
			lbl.add_theme_color_override("font_color", color)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			icon_rect.add_child(lbl)
		hbox.add_child(icon_rect)

		# 右侧文字区
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(vbox)

		var name_l := Label.new()
		name_l.text = p.get("name", "")
		name_l.add_theme_font_size_override("font_size", 20)
		name_l.add_theme_color_override("font_color", Color(0.95, 0.97, 1, 1))
		vbox.add_child(name_l)

		var desc_l := Label.new()
		desc_l.text = p.get("desc", "")
		desc_l.add_theme_font_size_override("font_size", 12)
		desc_l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85, 1))
		desc_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_l)

		var bonus_l := Label.new()
		bonus_l.text = _persona_bonus_text(p)
		bonus_l.add_theme_font_size_override("font_size", 11)
		bonus_l.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.85))
		bonus_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(bonus_l)

		grid.add_child(card)
		buttons[id] = card

func _animate_card(card: Button, s: float) -> void:
	card.pivot_offset = card.size * 0.5
	card.scale = Vector2(s, s)

func _persona_bonus_text(p: Dictionary) -> String:
	var up_id: String = p.get("up", "")
	var down_id: String = p.get("down", "")
	if up_id.is_empty() and down_id.is_empty():
		return "· 所有接话方式判定保持原样\n· 没有加成，也没有短板"
	var up_name: String = GameData.APPROACHES.get(up_id, {}).get("name", "")
	var down_name: String = GameData.APPROACHES.get(down_id, {}).get("name", "")
	var lines: Array = []
	lines.append("▲ %s：判定升一档" % up_name)
	lines.append("▼ %s：判定降一档" % down_name)
	if p.has("belief_bonus") and int(p["belief_bonus"]) > 0:
		lines.append("拿手方式命中额外 -%d 信念" % int(p["belief_bonus"]))
	if p.has("soothe_refund"):
		lines.append("给台阶时回复 %d 理智" % int(p["soothe_refund"]))
	if float(p.get("sanity_mult", 1.0)) > 1.0:
		lines.append("理智消耗 +%d%%" % int(round((float(p["sanity_mult"]) - 1.0) * 100)))
	elif float(p.get("sanity_mult", 1.0)) < 1.0:
		lines.append("理智消耗 -%d%%" % int(round((1.0 - float(p["sanity_mult"])) * 100)))
	if float(p.get("public_mult", 1.0)) != 1.0:
		lines.append("舆论收益 ×%.1f" % float(p["public_mult"]))
	return "\n".join(PackedStringArray(lines))

func _on_card_pressed(id: String) -> void:
	selected = id
	_refresh_selection()

func _refresh_selection() -> void:
	for id in buttons.keys():
		var p: Dictionary = GameData.PERSONALITIES[id]
		var color := Color.html(p.get("color", "#ffffff"))
		var btn: Button = buttons[id]
		if id == selected:
			_style_selected(btn, color)
		else:
			_style_normal(btn, color)

func _style_selected(btn: Button, color: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = color.darkened(0.5)
	s.border_color = color
	s.set_border_width_all(2)
	s.set_corner_radius_all(14)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)
	# 发光效果
	btn.modulate = Color(1, 1, 1, 1)

func _style_normal(btn: Button, color: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.11, 0.13, 0.2, 0.85)
	s.border_color = Color(color.r * 0.4, color.g * 0.4, color.b * 0.4, 0.5)
	s.set_border_width_all(1)
	s.set_corner_radius_all(14)
	s.content_margin_left = 4
	s.content_margin_right = 4
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", _hover_style(s, color))
	btn.add_theme_stylebox_override("pressed", s)

func _hover_style(base: StyleBoxFlat, color: Color) -> StyleBoxFlat:
	var s := base.duplicate()
	s.border_color = Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, 0.7)
	s.bg_color = Color(base.bg_color.r * 1.2, base.bg_color.g * 1.2, base.bg_color.b * 1.2, base.bg_color.a)
	return s

func _on_start() -> void:
	GlobalData.personality = selected
	GlobalData.reset_game()
	GlobalData.clear_run_save()  # 开始新局，清除旧的中途存档
	get_tree().change_scene_to_file("res://scenes/battle.tscn")
