extends Control

@onready var toggle_reduce: CheckBox = $Margin/VBox/ReduceGroup/ToggleReduce
@onready var btn_back: Button = $Margin/VBox/BackBtn

func _ready() -> void:
	_gradient_bg()
	toggle_reduce.button_pressed = GlobalData.reduce_motion
	toggle_reduce.toggled.connect(_on_toggled)
	_btn_style(btn_back, Color(0.29, 0.56, 0.85, 0.9), 10)
	btn_back.pressed.connect(func(): Audio.play_sfx("click"))
	btn_back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_build_audio_ui()

func _gradient_bg() -> void:
	var bg: ColorRect = $Bg
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.add_point(0.0, Color(0.08, 0.08, 0.14, 1))
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

func _on_toggled(pressed: bool) -> void:
	GlobalData.reduce_motion = pressed

func _build_audio_ui() -> void:
	var vbox: VBoxContainer = $Margin/VBox
	var group := VBoxContainer.new()
	group.name = "AudioGroup"
	group.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "♪ 音量"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.85, 0.92, 1, 1))
	group.add_child(title)

	group.add_child(_make_slider_row("背景音乐", Audio.bgm_volume, func(v: float): Audio.set_bgm_volume(v)))
	group.add_child(_make_slider_row("音效", Audio.sfx_volume, func(v: float): Audio.set_sfx_volume(v)))

	var mute := CheckBox.new()
	mute.text = "静音"
	mute.button_pressed = Audio.muted
	mute.add_theme_font_size_override("font_size", 18)
	mute.toggled.connect(func(p: bool): Audio.set_muted(p))
	group.add_child(mute)

	vbox.add_child(group)
	vbox.move_child(group, vbox.get_child_count() - 2)

func _make_slider_row(label_text: String, value: float, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.92, 1))
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(320, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float): cb.call(v))
	row.add_child(slider)
	return row
