extends Control

# ============================================================
# endings.gd — 结局图鉴：已解锁显示全文，未解锁显示剪影
# ============================================================

const GameData = preload("res://core/game_data.gd")
const ICON_DIR := "res://assets/icons/"

var _icon_cache := {}
func _get_icon(name: String) -> Texture2D:
	if _icon_cache.has(name):
		return _icon_cache[name]
	var p: Resource = load(ICON_DIR + name + ".svg") if ResourceLoader.exists(ICON_DIR + name + ".svg") else null
	_icon_cache[name] = p if p is Texture2D else null
	return _icon_cache[name]

# 展示顺序：好结局 → 普通 → 坏结局
const ORDER: Array = [
	"logic_break_public",
	"logic_break",
	"logic_break_pyrric",
	"dignified_public",
	"dignified",
	"dignified_lonely",
	"withdraw_early",
	"withdraw_mid",
	"withdraw_late",
	"emotional_break",
	"public_crushed",
	"public_idolized"
]

# 未解锁时的提示（不剧透文案，只指路）
const HINTS: Dictionary = {
	"logic_break_public": "击破他的逻辑，且围观者站在你这边",
	"logic_break": "击破他的逻辑",
	"logic_break_pyrric": "与他同归于尽",
	"dignified_public": "撑到最后，且围观者支持你",
	"dignified": "撑到最后",
	"dignified_lonely": "撑到最后，但没什么人支持你",
	"withdraw_early": "开局不久就撤离",
	"withdraw_mid": "中途撤离",
	"withdraw_late": "快结束时撤离",
	"emotional_break": "理智归零",
	"public_crushed": "让围观舆论跌到谷底",
	"public_idolized": "让围观舆论捧到顶点"
}

@onready var container: VBoxContainer = $Margin/VBox/ScrollContainer/VBox
@onready var btn_back: Button = $Margin/VBox/BackBtn
@onready var count_label: Label = $Margin/VBox/CountLabel

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
	g.add_point(0.0, Color(0.09, 0.07, 0.16, 1))
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

	var unlocked_n := GlobalData.unlocked_ending_count()
	count_label.text = "已解锁 %d / %d" % [unlocked_n, ORDER.size()]

	var star_icon: Texture2D = _get_icon("star")
	var mask_icon: Texture2D = _get_icon("mask")

	for key in ORDER:
		var info: Dictionary = GameData.ENDINGS.get(key, {})
		var unlocked := GlobalData.is_ending_unlocked(key)

		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", _card_style(unlocked))

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 16)
		margin.add_theme_constant_override("margin_right", 16)
		margin.add_theme_constant_override("margin_top", 12)
		margin.add_theme_constant_override("margin_bottom", 12)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(margin)

		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 3)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(vb)

		# 标题行：图标 + 结局名 + 副标题
		var title_box := HBoxContainer.new()
		title_box.add_theme_constant_override("separation", 10)
		title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(title_box)

		var icon_rect := TextureRect.new()
		icon_rect.custom_minimum_size = Vector2(22, 22)
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP
		icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if unlocked and star_icon:
			icon_rect.texture = star_icon
			icon_rect.modulate = Color(0.95, 0.8, 1, 1)
		elif not unlocked and mask_icon:
			icon_rect.texture = mask_icon
			icon_rect.modulate = Color(0.4, 0.4, 0.46, 0.8)
		title_box.add_child(icon_rect)

		var t := Label.new()
		t.text = info.get("title", "") if unlocked else "？？？"
		t.add_theme_font_size_override("font_size", 19)
		t.add_theme_color_override("font_color",
			Color(0.92, 0.85, 1, 1) if unlocked else Color(0.5, 0.5, 0.56, 1))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_box.add_child(t)

		var sub := Label.new()
		sub.text = "· " + (info.get("sub", "") if unlocked else "尚未抵达")
		sub.add_theme_font_size_override("font_size", 14)
		sub.add_theme_color_override("font_color",
			Color(0.7, 0.65, 0.85, 0.9) if unlocked else Color(0.45, 0.45, 0.5, 0.8))
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_box.add_child(sub)

		# 正文 / 剪影提示
		var d := Label.new()
		d.text = info.get("text", "") if unlocked else "◆ 解锁条件：%s" % HINTS.get(key, "")
		d.add_theme_font_size_override("font_size", 14)
		d.add_theme_color_override("font_color",
			Color(0.72, 0.76, 0.86, 1) if unlocked else Color(0.48, 0.5, 0.58, 0.85))
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(d)

		container.add_child(card)

func _card_style(unlocked: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	if unlocked:
		s.bg_color = Color(0.13, 0.11, 0.2, 0.9)
		s.border_color = Color(0.55, 0.45, 0.8, 0.45)
	else:
		s.bg_color = Color(0.08, 0.08, 0.12, 0.75)
		s.border_color = Color(0.3, 0.3, 0.36, 0.35)
	s.set_corner_radius_all(10)
	s.set_border_width_all(1)
	return s
