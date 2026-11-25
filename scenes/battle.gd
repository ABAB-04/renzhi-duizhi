extends Control

# ============================================================
# battle.gd — 主战斗场景
# 每回合：读 BOSS 姿态 → 从 3 句台词里接话 → 影响理智/信念/舆论
# ============================================================

const GameData = preload("res://core/game_data.gd")
const ICON_DIR := "res://assets/icons/"
const IMG_DIR := "res://assets/images/"

var _icon_cache := {}
func _get_icon(name: String) -> Texture2D:
	if _icon_cache.has(name):
		return _icon_cache[name]
	var p: Resource = load(ICON_DIR + name + ".svg") if ResourceLoader.exists(ICON_DIR + name + ".svg") else null
	_icon_cache[name] = p if p is Texture2D else null
	return _icon_cache[name]

# AI 生成的位图（PNG）：有就用，没有就回退到 SVG 图标或程序化渐变
# 支持 boss.png / bg_<场景>.png / boss_<姿态>.png / boss_<阶段>.png
var _img_cache := {}
func _get_image(name: String) -> Texture2D:
	if _img_cache.has(name):
		return _img_cache[name]
	var p: Resource = load(IMG_DIR + name + ".png") if ResourceLoader.exists(IMG_DIR + name + ".png") else null
	_img_cache[name] = p if p is Texture2D else null
	return _img_cache[name]

func _gradient(bg_node: ColorRect, t: Color, b: Color) -> void:
	var tex := GradientTexture2D.new()
	var g := Gradient.new()
	g.add_point(0.0, t)
	g.add_point(1.0, b)
	tex.gradient = g
	tex.fill_to = Vector2(0, 1)
	var layer := TextureRect.new()
	layer.texture = tex
	layer.stretch_mode = TextureRect.STRETCH_SCALE
	bg_node.add_child(layer)
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.z_index = 0
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE

# 6 场景差异化渐变：按 scene_setup 关键词选色
# 外卖→暖橙+冷蓝 / 热搜→灰青+深蓝 / 养生→冷绿+深灰
# 室友→暖紫+灰蓝 / 游戏→暗紫+近黑 / 电影→暖红+深褐
func _scene_palette() -> Array:
	var setup: String = GlobalData.scene_setup
	if setup.contains("外卖") or setup.contains("午休"):
		return [Color(0.18, 0.12, 0.1, 1), Color(0.05, 0.05, 0.1, 1)]
	if setup.contains("热搜") or setup.contains("聚会"):
		return [Color(0.08, 0.1, 0.14, 1), Color(0.02, 0.03, 0.08, 1)]
	if setup.contains("养生") or setup.contains("家族"):
		return [Color(0.08, 0.13, 0.1, 1), Color(0.03, 0.06, 0.05, 1)]
	if setup.contains("合租") or setup.contains("室友"):
		return [Color(0.1, 0.08, 0.15, 1), Color(0.03, 0.03, 0.06, 1)]
	if setup.contains("游戏") or setup.contains("组队"):
		return [Color(0.08, 0.05, 0.15, 1), Color(0.01, 0.01, 0.04, 1)]
	if setup.contains("电影") or setup.contains("品味"):
		return [Color(0.16, 0.08, 0.08, 1), Color(0.05, 0.03, 0.03, 1)]
	# 默认（不该走到这）
	return [Color(0.06, 0.08, 0.16, 1), Color(0.02, 0.03, 0.08, 1)]

# 6 场景对应的 AI 背景图名（不含 .png），与 _scene_palette 的关键词一一对应
# 图放在 res://assets/images/ 下，没有则回退到程序化渐变
func _scene_bg_name() -> String:
	var setup: String = GlobalData.scene_setup
	if setup.contains("外卖") or setup.contains("午休"):
		return "bg_takeout"
	if setup.contains("热搜") or setup.contains("聚会"):
		return "bg_hotsearch"
	if setup.contains("养生") or setup.contains("家族"):
		return "bg_health"
	if setup.contains("合租") or setup.contains("室友"):
		return "bg_roommate"
	if setup.contains("游戏") or setup.contains("组队"):
		return "bg_game"
	if setup.contains("电影") or setup.contains("品味"):
		return "bg_movie"
	return ""

# UI 引用
@onready var sanity_bar: ProgressBar = $TopBar/SanityBox/SanityBar
@onready var belief_bar: ProgressBar = $TopBar/BeliefBox/BeliefBar
@onready var public_bar: ProgressBar = $TopBar/PublicBox/PublicBar
@onready var sanity_label: Label = $TopBar/SanityBox/SanityLabel
@onready var belief_label: Label = $TopBar/BeliefBox/BeliefLabel
@onready var public_label: Label = $TopBar/PublicBox/PublicLabel
@onready var round_label: Label = $TopBar/RoundLabel
@onready var stage_label: Label = $TopBar/StageLabel
@onready var persona_label: Label = $TopBar/PersonaLabel

@onready var boss_name: Label = $BossArea/BossInfo/BossName
@onready var boss_portrait: ColorRect = $BossArea/BossPortrait
@onready var boss_line: RichTextLabel = $DialogArea/BossLine

@onready var stance_label: Label = $ActionPanel/VBox/StanceLabel
@onready var hint_label: Label = $ActionPanel/VBox/HintLabel
@onready var options_box: HBoxContainer = $ActionPanel/VBox/OptionsBox
@onready var btn_evidence: Button = $ActionPanel/VBox/UtilBox/BtnEvidence
@onready var btn_withdraw: Button = $ActionPanel/VBox/UtilBox/BtnWithdraw

# 弹窗层
@onready var quiz_popup: Control = $QuizPopup
@onready var quiz_question: Label = $QuizPopup/Margin/VBox/QuestionLabel
@onready var quiz_options: VBoxContainer = $QuizPopup/Margin/VBox/OptionsContainer
@onready var quiz_submit: Button = $QuizPopup/Margin/VBox/SubmitBtn

@onready var explain_popup: Control = $ExplainPopup
@onready var explain_label: RichTextLabel = $ExplainPopup/Margin/VBox/ExplainLabel
@onready var explain_continue: Button = $ExplainPopup/Margin/VBox/ContinueBtn

@onready var withdraw_popup: Control = $WithdrawPopup
@onready var withdraw_react: Label = $WithdrawPopup/Margin/VBox/ReactLabel
@onready var withdraw_yes: Button = $WithdrawPopup/Margin/VBox/HBox/BtnEnd
@onready var withdraw_no: Button = $WithdrawPopup/Margin/VBox/HBox/BtnContinue

@onready var ending_popup: Control = $EndingPopup
@onready var ending_title: Label = $EndingPopup/Margin/VBox/EndTitle
@onready var ending_sub: Label = $EndingPopup/Margin/VBox/EndSub
@onready var ending_grade: Label = $EndingPopup/Margin/VBox/GradeLabel
@onready var ending_text: RichTextLabel = $EndingPopup/Margin/VBox/EndText
@onready var ending_summary: RichTextLabel = $EndingPopup/Margin/VBox/SummaryLabel
@onready var ending_new_ach: Label = $EndingPopup/Margin/VBox/NewAchLabel
@onready var ending_btn_back: Button = $EndingPopup/Margin/VBox/BtnBack

# 视觉特效层
@onready var feedback_label: Label = $FeedbackLabel
@onready var hit_layer: Control = $HitLayer
@onready var vignette_layer: ColorRect = $VignetteLayer
@onready var noise_layer: ColorRect = $NoiseLayer

# 临时状态
var selected_quiz_options: Array = []
var quiz_round_num: int = 0
var option_buttons: Array = []
var used_evidence_this_round: bool = false
var choice_locked: bool = true
var boss_icon: TextureRect = null  # BOSS 头像图标（动态创建，按阶段上色）
var _stance_layer: TextureRect = null  # 当前回合姿态图标层（叠在 boss_icon 之上）
var _stance_anim: Tween = null         # 姿态循环动画 tween
var _btn_help: Button = null           # 顶栏「?」玩法帮助入口
var _help_open: bool = false           # 帮助浮层是否已打开（防重复点击）
var _quit_confirm: Control = null      # ESC 退出确认浮层
var _prev_sanity: int = 0              # 上次理智值（用于浮动数值）
var _prev_belief: int = 0              # 上次信心值（用于浮动数值）
var _type_tween: Tween = null      # 打字机补间
var _first_stage_sync: bool = true # 首次同步阶段不播仪式
var _last_kw_count: int = 0        # 上次论据数量（用于 Toast）
var _toast_slots: Array = []       # 活跃 Toast（用于堆叠位置）
var _hb_tween: Tween = null         # 理智心跳脉冲循环
var _stutter_tween: Tween = null    # 理智卡壳循环
var _last_public_val: int = 50      # 上次舆论值（用于弹幕）
var _public_warned_low: bool = false   # 是否已提示过舆论崩盘风险
var _public_warned_high: bool = false  # 是否已提示过舆论捧杀风险
var _bet_mode: bool = false           # false=稳着说（默认），true=当众拆穿 1.5x 放大正负
var _btn_bet_steady: Button = null   # 押注按钮对：稳着说
var _btn_bet_aggressive: Button = null  # 押注按钮对：当众拆穿
var _boss_is_png: bool = false        # BOSS 立绘是否为 AI 生成的 PNG（染色策略不同）

# ============================================================
# 初始化
# ============================================================
func _ready() -> void:
	# 先记下初始值，避免第一帧就飘出一个虚假的 +60
	_prev_sanity = GlobalData.sanity
	_prev_belief = GlobalData.belief
	GlobalData.sanity_changed.connect(_on_sanity_changed)
	GlobalData.belief_changed.connect(_on_belief_changed)
	GlobalData.public_changed.connect(_on_public_changed)
	GlobalData.stage_changed.connect(_on_stage_changed)
	GlobalData.keyword_changed.connect(_on_keyword_changed)
	GlobalData.combo_changed.connect(_on_combo_changed)
	GlobalData.achievement_unlocked.connect(_on_achievement_toast)

	# 隐藏所有弹窗
	quiz_popup.visible = false
	explain_popup.visible = false
	withdraw_popup.visible = false
	ending_popup.visible = false
	ending_new_ach.visible = false
	feedback_label.modulate.a = 0.0

	# 连接按钮信号
	btn_evidence.pressed.connect(_on_evidence_pressed)
	btn_withdraw.pressed.connect(_on_withdraw_pressed)
	quiz_submit.pressed.connect(_on_quiz_submit_pressed)
	explain_continue.pressed.connect(_on_quiz_continue)
	withdraw_yes.pressed.connect(_on_withdraw_yes)
	withdraw_no.pressed.connect(_on_withdraw_no)
	ending_btn_back.pressed.connect(_on_ending_back_pressed)

	# 结局页「再来一局」：与「返回主菜单」并排，不额外占纵向空间
	var ending_box: VBoxContainer = $EndingPopup/Margin/VBox
	var btn_again := Button.new()
	btn_again.text = "再来一局"
	btn_again.custom_minimum_size = Vector2(0, 46)
	_btn_style(btn_again, Color(0.29, 0.56, 0.85))
	btn_again.pressed.connect(func():
		_sfx("open")
		GlobalData.reset_game()
		GlobalData.clear_run_save()  # 再来一局，清除旧的中途存档
		get_tree().change_scene_to_file("res://scenes/battle.tscn"))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	var back_idx: int = ending_btn_back.get_index()
	ending_box.remove_child(ending_btn_back)
	ending_box.add_child(btn_row)
	ending_box.move_child(btn_row, back_idx)
	btn_row.add_child(btn_again)
	btn_row.add_child(ending_btn_back)
	btn_again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ending_btn_back.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# 按钮样式
	_btn_style(btn_evidence, Color(0.42, 0.34, 0.2))
	_btn_style(btn_withdraw, Color(0.3, 0.3, 0.35))
	_btn_style(quiz_submit, Color(0.29, 0.56, 0.85))
	_btn_style(explain_continue, Color(0.29, 0.56, 0.85))
	_btn_style(withdraw_yes, Color(0.6, 0.3, 0.3))
	_btn_style(withdraw_no, Color(0.3, 0.5, 0.3))
	_btn_style(ending_btn_back, Color(0.29, 0.56, 0.85))

	_update_all_bars()
	_update_keyword_ui()
	_update_persona_ui()
	_on_stage_changed(GlobalData.battle_stage)
	_first_stage_sync = false
	_last_kw_count = GlobalData.keyword_count()

	# 背景：优先用 AI 生成的场景图（res://assets/images/bg_<场景>.png），没有则回退到程序化渐变
	var bg_name: String = _scene_bg_name()
	var bg_tex: Texture2D = _get_image(bg_name) if bg_name != "" else null
	if bg_tex:
		var bg_layer := TextureRect.new()
		bg_layer.texture = bg_tex
		bg_layer.stretch_mode = TextureRect.STRETCH_SCALE
		bg_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		$Bg.add_child(bg_layer)
		bg_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		var bg_colors: Array = _scene_palette()
		_gradient($Bg, bg_colors[0], bg_colors[1])

	# BOSS 头像区：四层视觉——光效环（后）+ 主 BOSS 图标 + 姿态表情层 + 暗角盖（前）
	# 先做光效环：径向渐变光晕，给 BOSS 一个聚光灯感
	var aura := TextureRect.new()
	var aura_tex := GradientTexture2D.new()
	var aura_g := Gradient.new()
	aura_g.add_point(0.0, Color(0.3, 0.5, 0.9, 0.5))
	aura_g.add_point(0.5, Color(0.15, 0.25, 0.5, 0.25))
	aura_g.add_point(1.0, Color(0.02, 0.03, 0.08, 0.0))
	aura_tex.gradient = aura_g
	aura_tex.fill_to = Vector2(0.5, 0.5)
	aura.texture = aura_tex
	aura.stretch_mode = TextureRect.STRETCH_SCALE
	aura.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_portrait.add_child(aura)
	aura.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	aura.z_index = -1

	# 主 BOSS 立绘：优先用 AI 生成的 boss.png，没有则回退到 boss.svg 图标
	# PNG 立绘本身有完整色彩，modulate 只做微色温暗示；SVG 图标靠强染色体现阶段
	var boss_tex: Texture2D = _get_image("boss")
	_boss_is_png = boss_tex != null
	if boss_tex == null:
		boss_tex = _get_icon("boss")
	if boss_tex:
		boss_icon = TextureRect.new()
		boss_icon.texture = boss_tex
		boss_icon.stretch_mode = TextureRect.STRETCH_SCALE
		boss_icon.modulate = Color(0.92, 0.96, 1.0) if _boss_is_png else Color(0.25, 0.45, 0.7)
		boss_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		boss_portrait.add_child(boss_icon)
		boss_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# boss_portrait 本身变成深蓝底板，光效环叠在后面
	boss_portrait.color = Color(0.05, 0.07, 0.14, 1)

	# BOSS 立绘：姿态表情层（叠在主图标上）
	_stance_layer = TextureRect.new()
	_stance_layer.stretch_mode = TextureRect.STRETCH_KEEP
	_stance_layer.modulate = Color(1, 1, 1, 0.0)
	_stance_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_portrait.add_child(_stance_layer)
	_stance_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 暗角盖：最上层，BOSS 头像中心亮、边缘暗，突出主体
	# alpha 降到 0.3，确保不会完全盖住下面的姿态表情层
	var vignette_cap := TextureRect.new()
	var vg_tex := GradientTexture2D.new()
	var vg := Gradient.new()
	vg.add_point(0.0, Color(0, 0, 0, 0.0))
	vg.add_point(0.55, Color(0, 0, 0, 0.0))
	vg.add_point(1.0, Color(0, 0, 0, 0.3))
	vg_tex.gradient = vg
	vg_tex.fill_to = Vector2(0.5, 0.5)
	vignette_cap.texture = vg_tex
	vignette_cap.stretch_mode = TextureRect.STRETCH_SCALE
	vignette_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_cap.z_index = 1  # 显式置顶，但 alpha 温和，不会吃掉姿态层
	boss_portrait.add_child(vignette_cap)
	vignette_cap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 「?」帮助入口：放在行动栏右侧，随时可查玩法，方便评委/新玩家无协助试玩
	_btn_help = Button.new()
	_btn_help.text = "?"
	_btn_help.tooltip_text = "玩法说明"
	_btn_help.focus_mode = Control.FOCUS_NONE
	_btn_help.custom_minimum_size = Vector2(40, 40)
	_btn_style(_btn_help, Color(0.22, 0.28, 0.4))
	_btn_help.pressed.connect(_on_help_pressed)
	$ActionPanel/VBox/UtilBox.add_child(_btn_help)

	# 押注切换：稳着说（默认）vs 当众拆穿（×1.5 放大正负）
	# 本质是「你对自己的判断有多大信心」——猜错就要多承担，猜对就能多收获
	var bet_row := HBoxContainer.new()
	bet_row.add_theme_constant_override("separation", 4)
	var btn_steady := Button.new()
	btn_steady.text = "稳着说"
	btn_steady.custom_minimum_size = Vector2(80, 36)
	var btn_bet := Button.new()
	btn_bet.text = "🔊 押注加码"
	btn_bet.custom_minimum_size = Vector2(130, 36)
	btn_bet.tooltip_text = "猜对(顶/拆)：额外信念-3、舆论+3 ｜ 猜错(弱/背)：额外理智-4"
	_btn_style(btn_steady, Color(0.2, 0.3, 0.35))
	_btn_style(btn_bet, Color(0.4, 0.28, 0.2))
	bet_row.add_child(btn_steady)
	bet_row.add_child(btn_bet)
	# 押注行加在证据按钮和撤离按钮之间（UtilBox 顺序：[bet_row] [BtnEvidence] [BtnWithdraw] [?]）
	var util_box: HBoxContainer = $ActionPanel/VBox/UtilBox
	util_box.add_child(bet_row)
	util_box.move_child(bet_row, 0)
	# 存引用
	_btn_bet_steady = btn_steady
	_btn_bet_aggressive = btn_bet
	btn_steady.pressed.connect(_on_bet_steady)
	btn_bet.pressed.connect(_on_bet_aggressive)
	_refresh_bet_buttons()

	_setup_readability()

	# 继续游戏：如果有中途存档，从存档回合开始；否则从第 1 回合开始
	var start_r: int = 1
	if GlobalData.has_run_save() and GlobalData.load_run():
		start_r = GlobalData.current_round
	_start_round(start_r)

# ============================================================
# 可读性：台词与选项加不透明底板，氛围遮罩压到内容层之下
# 否则后期理智过低时，红色渐晕会把选项文字糊掉
# ============================================================
func _setup_readability() -> void:
	# 台词：更亮、更大、加描边，在暗底上立得住
	boss_line.add_theme_font_size_override("font_size", 21)
	boss_line.add_theme_color_override("default_color", Color(0.97, 0.97, 1.0, 1.0))
	boss_line.add_theme_constant_override("outline_size", 4)
	boss_line.add_theme_color_override("font_outline_color", Color(0.02, 0.02, 0.06, 0.9))

	_add_backdrop($DialogArea, Color(0.06, 0.08, 0.14, 0.86))
	_add_backdrop($ActionPanel, Color(0.05, 0.07, 0.12, 0.92))

	# 谬误弹窗从"考试"改成"抓破绽"，标题与字号同步调整
	var quiz_header: Label = $QuizPopup/Margin/VBox/Header
	quiz_header.text = "🔍 抓破绽"
	quiz_header.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	quiz_question.add_theme_font_size_override("font_size", 15)

	# 渐晕与噪点移到内容层下方（Bg 之后）：氛围还在，但永远不盖在文字上
	move_child(vignette_layer, 1)
	move_child(noise_layer, 2)

func _add_backdrop(target: Control, color: Color) -> void:
	var panel := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.45, 0.65, 0.25)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	target.add_child(panel)
	target.move_child(panel, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _on_help_pressed() -> void:
	if _help_open or ending_popup.visible or quiz_popup.visible:
		return
	_help_open = true
	await _show_tutorial(false)
	_help_open = false

func _update_persona_ui() -> void:
	var p: Dictionary = GlobalData.personality_info()
	if p.is_empty():
		persona_label.text = ""
		return
	persona_label.text = "%s %s ｜ 🎯 %s" % [p.get("icon", ""), p.get("name", ""), GlobalData.goal_info().get("name", "")]
	persona_label.add_theme_color_override("font_color", Color.html(p.get("color", "#ff9d7a")))

func _btn_style(btn: Button, c: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(8)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", s)
	btn.add_theme_stylebox_override("hover", s)
	btn.add_theme_stylebox_override("pressed", s)

# ============================================================
# 回合流程
# ============================================================
func _start_round(r: int) -> void:
	GlobalData.current_round = r
	GlobalData.save_run()  # 每回合开始自动存盘，支持「继续游戏」
	round_label.text = "第 %d / %d 回合" % [r, GlobalData.MAX_ROUND]
	stage_label.text = _stage_name(GlobalData.battle_stage)
	used_evidence_this_round = false
	_bet_mode = false  # 每回合重置押注，让玩家基于新线索重新判断
	_refresh_bet_buttons()

	# 首回合引导浮层（只弹一次，看过就存档）
	if r == 1 and not GlobalData.seen_tutorial:
		await _show_tutorial()

	_pop_round_label()

	# 随机事件插播（空壳阶段不再触发）
	if not GlobalData.is_empty_shell:
		var ev: Dictionary = GlobalData.get_event(r)
		if not ev.is_empty():
			_set_choice_enabled(false)
			await _play_event(ev, r)
			if GlobalData.current_round != r:
				return

	# 打字机输出 BOSS 台词，打完才允许接话
	var stance_id: String = GlobalData.get_stance(r)
	_boss_set_stance(stance_id)

	var full_text: String = ""
	if r == 1:
		var gi: Dictionary = GlobalData.goal_info()
		full_text += "[color=#6a7a9a][i]" + GlobalData.scene_setup + "[/i][/color]\n"
		full_text += "[color=%s]🎯 本局目标：%s · %s[/color]\n\n" % [
			gi.get("color", "#c8d4e8"), gi.get("name", ""), gi.get("desc", "")
		]
	full_text += "自洽先生： " + GlobalData.get_boss_line(r)

	# ★ BOSS 内心独白：30% 概率闪一句真心话（和他嘴上说的矛盾）
	if randf() < 0.3 and not GlobalData.is_quiz_round(r) and not GlobalData.is_empty_shell:
		var inner: String = GameData.BOSS_INNER_VOICE[randi() % GameData.BOSS_INNER_VOICE.size()]
		full_text += "\n\n[color=#4a5468][i]%s[/i][/color]" % inner
	var dur := _type_boss_line(full_text)

	if GlobalData.is_quiz_round(r):
		choice_locked = true
		_clear_options()
		stance_label.text = "📝 逻辑辨识 · 找出这段话里的谬误"
		stance_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
		hint_label.text = "多选，选全才算对"
		_set_choice_enabled(false)
		await get_tree().create_timer(maxf(dur, 0.5)).timeout
		if GlobalData.current_round != r:
			return
		_open_quiz(r)
	else:
		_render_choices(r)
		if dur > 0.0:
			_set_choice_enabled(false)
			await get_tree().create_timer(dur).timeout
			# 打字期间回合未被推进才恢复按钮
			if GlobalData.current_round == r and not ending_popup.visible and not quiz_popup.visible:
				_set_choice_enabled(true)

# ============================================================
# 演出：打字机 / 回合过渡 / 阶段仪式 / Toast
# ============================================================
# 逐字显示 BOSS 台词，返回总时长（秒）
func _type_boss_line(full_text: String) -> float:
	boss_line.clear()
	boss_line.append_text(full_text)
	if GlobalData.reduce_motion:
		boss_line.visible_ratio = 1.0
		return 0.0
	boss_line.visible_ratio = 0.0
	var n: int = boss_line.get_parsed_text().length()
	var dur: float = clampf(n * 0.02, 0.5, 1.8)
	if _type_tween and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = create_tween()
	_type_tween.tween_property(boss_line, "visible_ratio", 1.0, dur)
	return dur

# 点击跳过打字机：覆盖全屏未处理点击，守卫不变
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _type_tween and _type_tween.is_valid():
			_type_tween.kill()
			boss_line.visible_ratio = 1.0
			_type_tween = null
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER:
			if _type_tween and _type_tween.is_valid():
				_type_tween.kill()
				boss_line.visible_ratio = 1.0
				_type_tween = null
		elif not _is_modal_open():
			# 数字键 1/2/3 直接选择对应接话，免去移动鼠标
			var idx: int = -1
			match event.keycode:
				KEY_1, KEY_KP_1: idx = 0
				KEY_2, KEY_KP_2: idx = 1
				KEY_3, KEY_KP_3: idx = 2
			if idx >= 0 and not choice_locked and idx < option_buttons.size():
				option_buttons[idx].pressed.emit()
		elif event.keycode == KEY_ESCAPE and not _is_modal_open():
			_show_quit_confirm()

func _is_modal_open() -> bool:
	return _help_open or _quit_confirm != null or quiz_popup.visible \
		or explain_popup.visible or withdraw_popup.visible or ending_popup.visible

# ESC 退出确认：放弃本局并回到主菜单（不结算、不记入结局图鉴）
func _show_quit_confirm() -> void:
	if _quit_confirm != null:
		return

	var mask := Control.new()
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask.modulate = Color(1, 1, 1, 0.0)
	add_child(mask)
	_quit_confirm = mask

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(dim)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.14, 0.24, 0.98)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.5, 0.8, 0.5)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 22
	sb.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", sb)
	card.anchor_left = 0.5
	card.anchor_right = 0.5
	card.anchor_top = 0.5
	card.anchor_bottom = 0.5
	card.offset_left = -230
	card.offset_right = 230
	card.offset_top = -88
	card.offset_bottom = 88
	mask.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 14)
	card.add_child(vbox)

	var lbl := Label.new()
	lbl.text = "放弃这一局？\n进度不会保存，也不会记入结局图鉴。"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 1))
	vbox.add_child(lbl)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	vbox.add_child(row)

	var btn_quit := Button.new()
	btn_quit.text = "返回主菜单"
	btn_quit.custom_minimum_size = Vector2(130, 38)
	_btn_style(btn_quit, Color(0.55, 0.3, 0.3))
	row.add_child(btn_quit)

	var btn_stay := Button.new()
	btn_stay.text = "继续对峙"
	btn_stay.custom_minimum_size = Vector2(130, 38)
	_btn_style(btn_stay, Color(0.29, 0.56, 0.85))
	row.add_child(btn_stay)

	btn_stay.pressed.connect(func():
		_sfx("click")
		_close_quit_confirm())
	btn_quit.pressed.connect(func():
		_sfx("click")
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))

	var tw_in := create_tween()
	tw_in.tween_property(mask, "modulate", Color(1, 1, 1, 1), 0.18)

func _close_quit_confirm() -> void:
	if _quit_confirm == null:
		return
	var m: Control = _quit_confirm
	_quit_confirm = null
	m.queue_free()

func _pop_round_label() -> void:
	if GlobalData.reduce_motion:
		return
	round_label.pivot_offset = round_label.size * 0.5
	round_label.scale = Vector2(1.3, 1.3)
	var tw := create_tween()
	tw.tween_property(round_label, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# ============================================================
# 首回合引导浮层
# 遮罩 + 居中卡片，await 玩家点击「开始」才继续打字机
# ============================================================
func _show_tutorial(is_first_run: bool = true) -> void:
	var mask := Control.new()
	mask.mouse_filter = Control.MOUSE_FILTER_STOP
	mask.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mask.modulate = Color(1, 1, 1, 0.0)
	add_child(mask)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.05, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(dim)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.14, 0.24, 0.98)
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.35, 0.5, 0.8, 0.5)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 24
	sb.content_margin_bottom = 24
	card.add_theme_stylebox_override("panel", sb)
	card.anchor_left = 0.5; card.anchor_right = 0.5
	card.anchor_top = 0.5; card.anchor_bottom = 0.5
	card.offset_left = -290; card.offset_right = 290
	card.offset_top = -170; card.offset_bottom = 170
	card.pivot_offset = card.size * 0.5
	mask.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 12)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "📖 怎么玩"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.92, 0.95, 1))
	vbox.add_child(title)

	var tips := [
		"读他的语气线索，选你接得住的话。",
		"· 他施压时——接台阶",
		"· 他示弱时——别被带偏",
		"· 他讲大道理——抓他绕开的地方",
		"· 他拉围观者——别让你成了主角",
		"",
		"💧 理智归零 → 崩",
		"🔩 信念归零 → 赢",
		"👥 舆论两头杀人：太低没人听，太高被架成符号",
		"",
		"💡 攒两句「论据」可以亮出反击，也可以拼合爆发"
	]
	for line in tips:
		var l := Label.new()
		l.text = line
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", Color(0.78, 0.84, 0.95))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if line.begins_with("·"):
			l.add_theme_color_override("font_color", Color(0.65, 0.72, 0.88))
		vbox.add_child(l)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	bottom.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_child(bottom)

	var chk: CheckBox = null
	if is_first_run:
		chk = CheckBox.new()
		chk.text = "不再提示"
		chk.add_theme_font_size_override("font_size", 14)
		chk.add_theme_color_override("font_color", Color(0.65, 0.72, 0.85))
		bottom.add_child(chk)

	bottom.add_child(Control.new())

	var btn := Button.new()
	btn.text = "开始" if is_first_run else "知道了"
	btn.custom_minimum_size = Vector2(100, 36)
	var s2 := StyleBoxFlat.new()
	s2.bg_color = Color(0.29, 0.56, 0.85, 0.95)
	s2.set_corner_radius_all(8)
	s2.content_margin_left = 20; s2.content_margin_right = 20
	s2.content_margin_top = 8; s2.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", s2)
	var h2 := s2.duplicate(); h2.bg_color = Color(0.35, 0.62, 0.9, 1)
	btn.add_theme_stylebox_override("hover", h2)
	var p2 := s2.duplicate(); p2.bg_color = Color(0.22, 0.45, 0.7, 1)
	btn.add_theme_stylebox_override("pressed", p2)
	bottom.add_child(btn)

	mask.modulate = Color(1, 1, 1, 0.0)
	var tw_in := create_tween()
	tw_in.tween_property(mask, "modulate", Color(1, 1, 1, 1), 0.35)
	await btn.button_up

	_sfx("select")
	if is_first_run and chk != null and chk.button_pressed:
		GlobalData.seen_tutorial = true
		GlobalData.save_achievements()

	var tw_out := create_tween()
	tw_out.tween_property(mask, "modulate", Color(1, 1, 1, 0.0), 0.2)
	await tw_out.finished
	mask.queue_free()

# 阶段切换全屏仪式：压暗 + 大字提示
func _play_stage_ceremony(stage: int) -> void:
	var text: String = ""
	var color := Color.WHITE
	match stage:
		GlobalData.Stage.STUBBORN:
			text = "他收起了笑，开始防备了"
			color = Color(0.9, 0.72, 0.78)
		GlobalData.Stage.COLLAPSE:
			text = "他的逻辑，开始松动了"
			color = Color(1, 0.6, 0.55)
		GlobalData.Stage.EMPTY_SHELL:
			text = "他……没话可说了"
			color = Color(0.72, 0.74, 0.8)
	if text.is_empty():
		return
	if GlobalData.reduce_motion:
		_show_custom_feedback(text, color)
		return

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 44)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 8)
	lbl.modulate.a = 0.0
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(lbl)
	lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var tw := create_tween()
	tw.tween_property(overlay, "color", Color(0, 0, 0, 0.55), 0.22)
	tw.parallel().tween_property(lbl, "modulate:a", 1.0, 0.22)
	tw.tween_interval(0.7)
	tw.tween_property(overlay, "color", Color(0, 0, 0, 0), 0.35)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.3)
	tw.tween_callback(overlay.queue_free)

# 右上角 Toast：滑入 → 停留 → 淡出
func _show_toast(title: String, desc: String, color: Color) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.18, 0.95)
	sb.set_corner_radius_all(10)
	sb.border_color = Color(color.r, color.g, color.b, 0.55)
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 15)
	t.add_theme_color_override("font_color", color)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(t)
	if not desc.is_empty():
		var d := Label.new()
		d.text = desc
		d.add_theme_font_size_override("font_size", 12)
		d.add_theme_color_override("font_color", Color(0.7, 0.74, 0.84))
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(d)
	panel.add_child(vb)

	add_child(panel)
	var slot := _toast_slots.size()
	_toast_slots.append(panel)
	var top: float = 84.0 + float(slot) * 76.0
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	# 起始位置在右侧屏外，终点贴右缘留 16px 边距
	panel.offset_left = -296.0
	panel.offset_right = 64.0
	panel.offset_top = top
	panel.offset_bottom = top + 64.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN

	if GlobalData.reduce_motion:
		panel.modulate.a = 1.0
		panel.offset_left = -376.0
		panel.offset_right = -16.0
	else:
		panel.modulate.a = 0.0
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(panel, "modulate:a", 1.0, 0.18)
		tw.tween_property(panel, "offset_left", -376.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(panel, "offset_right", -16.0, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	await get_tree().create_timer(2.2).timeout
	if not is_instance_valid(panel):
		return
	_toast_slots.erase(panel)
	var tw2 := create_tween()
	tw2.tween_property(panel, "modulate:a", 0.0, 0.3)
	tw2.tween_callback(panel.queue_free)

func _on_achievement_toast(id: String) -> void:
	var info: Dictionary = GameData.ACHIEVEMENTS.get(id, {})
	if info.is_empty():
		return
	_show_toast("★ 成就解锁 · %s" % info.get("title", ""), info.get("desc", ""), Color(1, 0.85, 0.45))

# 随机事件演出：独立 overlay，不覆盖 BOSS 台词
func _play_event(ev: Dictionary, r: int) -> void:
	GlobalData.apply_event(r)
	_update_all_bars()

	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 200)
	margin.add_theme_constant_override("margin_right", 200)
	margin.add_theme_constant_override("margin_top", 180)
	margin.add_theme_constant_override("margin_bottom", 180)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.14, 0.1, 0.2, 0.95)
	sb.set_corner_radius_all(14)
	sb.border_color = Color(0.5, 0.35, 0.7, 0.55)
	sb.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(vb)

	var tag := Label.new()
	tag.text = "—— 插曲 · %s ——" % ev.get("name", "")
	tag.add_theme_font_size_override("font_size", 22)
	tag.add_theme_color_override("font_color", Color(0.85, 0.75, 1, 0.95))
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(tag)

	var desc := Label.new()
	desc.text = ev.get("text", "")
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", Color(0.88, 0.86, 0.95, 1))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(desc)

	# 数值反馈行
	var effect: Dictionary = ev.get("effect", {})
	var feedback_text: String = ""
	var feedback_color: Color = Color.WHITE
	if effect.has("sanity"):
		var v: int = int(effect["sanity"])
		feedback_text = "理智 %+d" % v
		feedback_color = Color(0.6, 0.85, 1) if v >= 0 else Color(1, 0.5, 0.45)
	elif effect.has("public"):
		var pv: int = int(effect["public"])
		feedback_text = "围观 %+d" % pv
		feedback_color = Color(0.9, 0.85, 0.5)
	elif bool(effect.get("reroll_stance", false)):
		feedback_text = "他变招了！"
		feedback_color = Color(1, 0.7, 0.5)

	var fb := Label.new()
	fb.text = feedback_text
	fb.add_theme_font_size_override("font_size", 22)
	fb.add_theme_color_override("font_color", feedback_color)
	fb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(fb)

	# 淡出动画
	overlay.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(overlay, "modulate:a", 1.0, 0.25)
	tw.tween_interval(1.4)
	tw.tween_property(overlay, "modulate:a", 0.0, 0.3)
	tw.tween_callback(overlay.queue_free)
	await get_tree().create_timer(1.95).timeout  # 等事件播完

func _render_choices(r: int) -> void:
	if GlobalData.is_empty_shell:
		_render_empty_shell()
		return

	if GlobalData.hard_mode:
		# 困难模式：连线索也不给，只让玩家读台词
		stance_label.text = "他在说话……这招得靠你自己读"
		stance_label.add_theme_color_override("font_color", Color(0.72, 0.62, 0.85))
	else:
		# 普通模式：只给两条语气线索，姿态名不再直接显示
		var clues: Array = GlobalData.get_stance_clues(r)
		if clues.size() >= 2:
			stance_label.text = "对方语气｜%s ｜ %s" % [clues[0], clues[1]]
		elif clues.size() == 1:
			stance_label.text = "对方语气｜%s" % clues[0]
		else:
			stance_label.text = "他在说话，先听语气"
		# 中性色：姿态自身的颜色也会泄露答案
		stance_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))

	_clear_options()

	var opts: Array = GlobalData.get_options(r)
	# 兜底：数据缺失也要能继续，绝不让玩家卡在"只能撤离"
	if opts.is_empty():
		opts = _fallback_options()
	for i in range(opts.size()):
		var opt: Dictionary = opts[i]
		var aid: String = opt.get("type", "firm")
		var ai := GlobalData.approach_info(aid)
		var btn := Button.new()
		var display_text: String = opt.get("text", "")
		# 去掉 icon/name/tag 标签，只留台词本身，让玩家从文字读性质
		# tooltip 保留 approach 名作为悬停时的轻量提示（新手友好）
		btn.text = display_text
		btn.tooltip_text = "[%s] %s" % [ai.get("name", ""), display_text]
		btn.custom_minimum_size = Vector2(0, 64)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		if "autowrap_mode" in btn:
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		else:
			btn.text = display_text.substr(0, 24)
		_btn_style(btn, Color(0.18, 0.22, 0.3))
		_wire_option_hover(btn)
		btn.pressed.connect(_on_option_pressed.bind(aid))
		options_box.add_child(btn)
		option_buttons.append(btn)

	_set_choice_enabled(true)
	_update_hint()

# 兜底选项：数据缺失时也能继续推进
func _fallback_options() -> Array:
	return [
		{"type": "probe", "text": "先指出他这句话里的漏洞。"},
		{"type": "firm", "text": "直接顶回去，别跟着他的节奏。"},
		{"type": "soothe", "text": "先给个台阶，别把话堵死。"}
	]

# 选项的悬停抬升与按下闪白：给纯文字按钮一点"被摸到"的实感
func _wire_option_hover(btn: Button) -> void:
	btn.mouse_entered.connect(func():
		if btn.disabled or GlobalData.reduce_motion:
			return
		btn.pivot_offset = btn.size * 0.5
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2(1.03, 1.03), 0.12))
	btn.mouse_exited.connect(func():
		if GlobalData.reduce_motion:
			return
		var tw := create_tween()
		tw.tween_property(btn, "scale", Vector2.ONE, 0.12))
	btn.pressed.connect(func():
		if GlobalData.reduce_motion:
			return
		var tw := create_tween()
		tw.tween_property(btn, "modulate", Color(1.7, 1.7, 1.7), 0.05)
		tw.tween_property(btn, "modulate", Color.WHITE, 0.18))

func _render_empty_shell() -> void:
	stance_label.text = "空壳 · 他已经没有话术可用了"
	stance_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))
	hint_label.text = "对方已经说不下去了，听完就可以走"
	hint_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.72))

	_clear_options()
	var btn := Button.new()
	btn.text = "……（听他把话说完）"
	btn.custom_minimum_size = Vector2(0, 70)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 15)
	_btn_style(btn, Color(0.2, 0.23, 0.3))
	btn.pressed.connect(_on_empty_shell_continue)
	options_box.add_child(btn)
	option_buttons.append(btn)
	_set_choice_enabled(true)

func _on_empty_shell_continue() -> void:
	choice_locked = true
	_set_choice_enabled(false)
	GlobalData.change_sanity(2)
	_update_all_bars()
	await get_tree().create_timer(0.4).timeout
	var result := GlobalData.resolve_turn_end(GlobalData.current_round, false)
	if result != GlobalData.EndingType.NONE:
		_show_ending(result)
	else:
		_start_round(GlobalData.current_round + 1)

func _clear_options() -> void:
	option_buttons.clear()
	for child in options_box.get_children():
		child.queue_free()

func _set_choice_enabled(enabled: bool) -> void:
	choice_locked = not enabled
	for b in option_buttons:
		if is_instance_valid(b):
			b.disabled = not enabled
	btn_withdraw.disabled = not enabled
	btn_evidence.disabled = (not enabled) or GlobalData.keyword_count() <= 0 or used_evidence_this_round
	# 押注按钮：锁定时禁用（防止中途切换）
	if _btn_bet_steady != null:
		_btn_bet_steady.disabled = not enabled
	if _btn_bet_aggressive != null:
		_btn_bet_aggressive.disabled = not enabled

# ============================================================
# 押注切换：稳着说 vs 当众拆穿
# 押注不是"加难度"而是"加决策"——去标签后玩家第一次要考虑的是
# 「我敢不敢在这个回合放话压他？」，而不是"我选哪个答案"
# ============================================================
func _on_bet_steady() -> void:
	_bet_mode = false
	_refresh_bet_buttons()
	_sfx("click", 0.02, 1.0, 0.9)

func _on_bet_aggressive() -> void:
	_bet_mode = true
	_refresh_bet_buttons()
	_sfx("open", 0.02, 1.05, 1.0)

func _refresh_bet_buttons() -> void:
	if _btn_bet_steady == null or _btn_bet_aggressive == null:
		return
	if _bet_mode:
		_btn_bet_steady.modulate = Color(0.7, 0.7, 0.7, 1.0)
		_btn_bet_aggressive.modulate = Color(1.2, 0.95, 0.75, 1.0)
	else:
		_btn_bet_steady.modulate = Color(1.0, 1.0, 1.0, 1.0)
		_btn_bet_aggressive.modulate = Color(1.0, 1.0, 1.0, 1.0)

func _update_hint() -> void:
	var persona: Dictionary = GlobalData.personality_info()
	var persona_text := "%s %s · %s" % [
		persona.get("icon", ""), persona.get("name", ""), persona.get("short", "")
	]

	if GlobalData.combo >= 2:
		hint_label.text = "连击 ×%d ｜ %s" % [GlobalData.combo, persona_text]
		hint_label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	elif GlobalData.keyword_count() > 0:
		hint_label.text = "已收集论据：%s ｜ 亮出会中断连击" % "、".join(PackedStringArray(GlobalData.keywords))
		hint_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.55))
	elif GlobalData.hard_mode:
		hint_label.text = persona_text + " ｜ 听他说话的语气，选一句合适的话"
		hint_label.add_theme_color_override("font_color", Color(0.68, 0.6, 0.85))
	else:
		hint_label.text = persona_text + " ｜ 选一句最克他这招的话（按 1/2/3 也可选）"
		hint_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))

func _update_keyword_ui() -> void:
	btn_evidence.text = "🧩 亮出论据（%d）" % GlobalData.keyword_count()
	btn_evidence.disabled = choice_locked or GlobalData.keyword_count() <= 0 or used_evidence_this_round
	if GlobalData.keyword_count() >= 2:
		btn_evidence.text = "🧩 拼合论据（%d）" % GlobalData.keyword_count()

# ============================================================
# 玩家接话
# ============================================================
func _on_option_pressed(approach_id: String) -> void:
	if choice_locked:
		return
	_perform_choice(approach_id)

func _perform_choice(approach_id: String) -> void:
	choice_locked = true
	_set_choice_enabled(false)

	var r := GlobalData.current_round
	var stance_id := GlobalData.get_stance(r)
	var base_rating := GlobalData.evaluate(stance_id, approach_id)
	var rating := GlobalData.apply_personality_rating(base_rating, approach_id)
	var persona: Dictionary = GlobalData.personality_info()

	var deltas: Dictionary = GameData.RATING_DELTAS.get(rating, GameData.RATING_DELTAS["weak"])
	var scale: float = GameData.ROUND_SCALE.get(r, 1.0)

	var san_delta: int = int(deltas["sanity"]) + randi_range(-2, 2)
	var bel_delta: int = int(round(int(deltas["belief"]) * scale))
	var pub_delta: int = int(deltas["public"])

	# 性格：理智消耗倍率 / 拿手方式额外伤害 / 给台阶回理智 / 舆论倍率
	var san_mult: float = float(persona.get("sanity_mult", 1.0))
	if san_delta < 0:
		san_delta = int(round(san_delta * san_mult))
	if approach_id == "soothe" and persona.has("soothe_refund"):
		san_delta += int(persona["soothe_refund"])

	var persona_boost := false
	if approach_id == persona.get("up", "") and (rating == "perfect" or rating == "good"):
		var bonus := int(persona.get("belief_bonus", 0))
		if bonus > 0:
			bel_delta -= bonus
			persona_boost = true

	if pub_delta > 0:
		pub_delta = int(round(pub_delta * float(persona.get("public_mult", 1.0))))

	# 舆论主动化：选 appeal 是"打给围观者看"，额外 +3 舆论（但被带偏时 BOSS 更气）
	if approach_id == "appeal":
		pub_delta += 3
		if rating == "backfire":
			bel_delta += 4  # BOSS 觉得被围观拆穿，信念反加

	# 连击加成：第 3 次起，识破额外削信念
	var next_combo := GlobalData.combo + 1
	if rating == "perfect" and next_combo >= 3:
		bel_delta -= GameData.COMBO_BONUS
		pub_delta += 1

	# 押注：当众拆穿（_bet_mode=true）给条件性额外奖励/惩罚
	# 猜对多收，猜错多痛，但不直接 ×1.5 放大全部 delta
	# 这样不会和性格 san_mult 打架导致火爆脾气天生不可玩
	if _bet_mode:
		match rating:
			"perfect", "good":
				bel_delta -= 3      # 额外削信念
				pub_delta += 3      # 额外涨舆论
				# 升调 open：押注赢了有上扬的"赚了"感，主反馈音效在后面播
				_sfx("open", 0.02, 1.2, 1.1)
			"weak":
				san_delta -= 4
				# hit 前奏 + 降调 backfire：押注落空比稳着更沉
				_sfx("hit", 0.04, 0.9, 0.9)
				_sfx("backfire", 0.03, 0.85, 1.0)
			"backfire":
				san_delta -= 4
				# hit 强打 + backfire 更深：押注+完全接错 = 最痛
				_sfx("hit", 0.05, 0.8, 1.1)
				_sfx("backfire", 0.03, 0.75, 1.15)

	GlobalData.change_sanity(san_delta)
	if not GlobalData.is_empty_shell or bel_delta < 0:
		GlobalData.change_belief(bel_delta)
	GlobalData.change_public(pub_delta)
	GlobalData.note_rating(rating)

	_show_rating_feedback(rating, next_combo, persona_boost, _bet_mode)
	_play_hit_fx(bel_delta, rating, persona_boost)
	_append_reaction(rating)
	_spawn_combo_banner(next_combo)
	_update_all_bars()
	_update_keyword_ui()

	await get_tree().create_timer(0.7).timeout

	var result := GlobalData.resolve_turn_end(r, false)
	if result != GlobalData.EndingType.NONE:
		_show_ending(result)
	else:
		_start_round(r + 1)

# ============================================================
# 状态音效：同一音效随三条数值变化而变调、变轻
# 理智越低 → 声音越沉、越闷；对方快崩 → 声音越亮；连击越高 → 音高越上扬
# ============================================================
func _sfx(id: String, pitch_var: float = 0.03, base_pitch: float = 1.0, vol: float = 1.0) -> void:
	Audio.play_sfx(id, pitch_var, _state_pitch(base_pitch), _state_vol(vol))

func _state_pitch(base: float) -> float:
	var p: float = base
	if GlobalData.sanity <= 20:
		p *= 0.88
	elif GlobalData.sanity <= 45:
		p *= 0.95
	if GlobalData.belief <= 25:
		p *= 1.07
	elif GlobalData.belief <= 50:
		p *= 1.03
	if GlobalData.combo >= 3:
		p *= 1.02
	return clampf(p, 0.6, 1.6)

func _state_vol(base: float) -> float:
	var v: float = base
	if GlobalData.sanity <= 20:
		v *= 0.82
	return clampf(v, 0.1, 1.0)

func _show_rating_feedback(rating: String, combo: int, persona_boost: bool = false, bet_mode: bool = false) -> void:
	var text: String = ""
	var color := Color(0.8, 0.9, 1)
	match rating:
		"perfect":
			text = "识破！"
			color = Color(1, 0.85, 0.35)
			_sfx("perfect", 0.02, 1.0 + minf(combo, 4) * 0.015)
			if combo >= 3:
				text = "识破 ×%d 连击！" % combo
		"good":
			text = "接住了"
			color = Color(0.55, 0.85, 0.75)
			_sfx("good")
		"weak":
			text = "没接住"
			color = Color(0.65, 0.7, 0.8)
			_sfx("wrong")
		"backfire":
			text = "被带偏了"
			color = Color(1, 0.42, 0.38)
			_sfx("backfire")
	if persona_boost:
		text += "（性格加成）"
	# 押注结果明示：让玩家清楚感知自己赌对还是赌错
	if bet_mode:
		if rating == "perfect" or rating == "good":
			text += "  🎯 押中"
			color = color.lerp(Color(1, 0.95, 0.6), 0.3)
		else:
			text += "  💔 押亏"
			color = color.lerp(Color(1, 0.5, 0.4), 0.3)

	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_label.pivot_offset = feedback_label.size * 0.5
	feedback_label.modulate.a = 0.0
	feedback_label.scale = Vector2(0.88, 0.88)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(feedback_label, "modulate:a", 1.0, 0.12)
	tw.tween_property(feedback_label, "scale", Vector2(1, 1), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.35)
	tw.chain().tween_property(feedback_label, "modulate:a", 0.0, 0.25)

	if rating == "backfire" and not GlobalData.reduce_motion:
		noise_layer.color = Color(0.5, 0.08, 0.08, 0.3)
		var tw2 := create_tween()
		tw2.tween_property(noise_layer, "color", Color(0.15, 0.05, 0.05, 0.22), 0.35)

func _append_reaction(rating: String) -> void:
	var react: String = GameData.RATING_REACT.get(rating, "")
	if react.is_empty():
		return
	var color := "#8fa0b8"
	if rating == "perfect":
		color = "#ffd76a"
	elif rating == "backfire":
		color = "#ff7a6b"
	boss_line.append_text("\n[color=%s]%s[/color]" % [color, react])

# ============================================================
# BOSS 受击反馈
# ============================================================
func _play_hit_fx(bel_delta: int, rating: String, persona_boost: bool) -> void:
	if bel_delta >= 0:
		return

	_sfx("hit", 0.06, 1.0, clampf(0.55 + float(-bel_delta) / 20.0, 0.55, 1.0))
	_spawn_damage_number(-bel_delta, rating, persona_boost)

	if GlobalData.reduce_motion:
		return

	boss_portrait.pivot_offset = boss_portrait.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(boss_portrait, "modulate", Color(1.7, 0.7, 0.7), 0.06)
	tw.tween_property(boss_portrait, "scale", Vector2(1.06, 0.94), 0.06)
	tw.chain().tween_property(boss_portrait, "modulate", Color(1, 1, 1), 0.2)
	tw.parallel().tween_property(boss_portrait, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	if rating == "perfect" or persona_boost:
		var tw2 := create_tween()
		tw2.tween_property(boss_portrait, "rotation", 0.035, 0.05)
		tw2.tween_property(boss_portrait, "rotation", -0.03, 0.07)
		tw2.tween_property(boss_portrait, "rotation", 0.0, 0.06)

	# ★ 新增：BOSS 破防演出——perfect 时白闪 + glitch
	if rating == "perfect" and not GlobalData.reduce_motion:
		# HitLayer 白闪
		var flash := ColorRect.new()
		flash.color = Color(1, 1, 1, 0.7)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hit_layer.add_child(flash)
		flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var tw3 := create_tween()
		tw3.tween_property(flash, "modulate:a", 0.0, 0.18)
		tw3.tween_callback(flash.queue_free)

		# BOSS 头像剧烈 glitch（连续左右抖动 + 色调闪红）
		if boss_icon and is_instance_valid(boss_icon):
			boss_icon.pivot_offset = boss_icon.size * 0.5
			var glitch := create_tween()
			glitch.set_parallel(true)
			glitch.tween_property(boss_icon, "position", Vector2(randi_range(-12, 12), randi_range(-8, 8)), 0.04)
			glitch.tween_property(boss_icon, "modulate", Color(1, 0.3, 0.3), 0.04)
			glitch.tween_interval(0.05)
			glitch.tween_property(boss_icon, "position", Vector2(randi_range(-10, 10), randi_range(-6, 6)), 0.04)
			glitch.tween_property(boss_icon, "modulate", Color(0.3, 1, 0.3), 0.04)
			glitch.tween_interval(0.05)
			glitch.tween_property(boss_icon, "position", Vector2(randi_range(-6, 6), randi_range(-4, 4)), 0.04)
			glitch.tween_property(boss_icon, "modulate", Color(1, 1, 1), 0.04)
			glitch.tween_property(boss_icon, "position", Vector2.ZERO, 0.1)

# ★ combo≥3 时的"终结句"大字横幅
func _spawn_combo_banner(combo: int) -> void:
	if GlobalData.reduce_motion or combo < 3:
		return
	var banner := Label.new()
	banner.text = "🔥 %d 连击！" % combo
	banner.add_theme_font_size_override("font_size", 68)
	banner.add_theme_color_override("font_color", Color(1, 0.75, 0.35))
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	banner.add_theme_constant_override("outline_size", 10)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(banner)
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.anchor_top = 0.5
	banner.anchor_bottom = 0.5
	banner.offset_top = -40
	banner.offset_bottom = 40
	banner.offset_left = -400
	banner.offset_right = 400
	banner.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	banner.modulate.a = 0.0
	banner.scale = Vector2(1.8, 1.8)
	banner.pivot_offset = banner.size * 0.5

	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.15)
	tw.parallel().tween_property(banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.5)
	tw.tween_property(banner, "modulate:a", 0.0, 0.25)
	tw.tween_callback(banner.queue_free)

func _spawn_damage_number(amount: int, rating: String, persona_boost: bool) -> void:
	var l := Label.new()
	l.text = "-%d" % amount
	var color := Color(0.95, 0.95, 1)
	var font_size := 26
	match rating:
		"perfect":
			color = Color(1, 0.85, 0.35)
			font_size = 34
		"good":
			color = Color(0.7, 0.95, 0.85)
		"weak":
			color = Color(0.7, 0.74, 0.8)
	l.add_theme_font_size_override("font_size", font_size + (4 if persona_boost else 0))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	hit_layer.add_child(l)

	var start := boss_portrait.get_global_rect().position + Vector2(boss_portrait.size.x * 0.5 - 18, 40)
	l.position = start
	var end := start + Vector2(randi_range(-16, 16), -86)

	if persona_boost:
		l.text = "-%d ·性格" % amount

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position", end, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)

# ============================================================
# 关键词论据
# ============================================================
func _on_evidence_pressed() -> void:
	if choice_locked or used_evidence_this_round or GlobalData.keyword_count() <= 0:
		return

	used_evidence_this_round = true
	choice_locked = true
	_set_choice_enabled(false)

	var is_burst := GlobalData.keyword_count() >= 2

	if not is_burst:
		# 单张亮出：消耗 1 张，不再中断连击
		GlobalData.consume_keywords(1)
		GlobalData.change_sanity(-3)
		GlobalData.change_belief(-GameData.KEYWORD_SINGLE_BELIEF)
		GlobalData.change_public(5)
		_sfx("good")
		_show_custom_feedback("亮出论据！连击保住了", Color(1, 0.85, 0.45))
		boss_line.append_text("\n[color=#ffd76a]（你甩出一句他一直绕开的话。）[/color]")
		_update_all_bars()
		_update_keyword_ui()
		_play_hit_fx(-GameData.KEYWORD_SINGLE_BELIEF, "good", false)
	else:
		# 拼合论据：威力更大，但有概率被他抓住破绽反打
		GlobalData.consume_keywords(2)
		if randf() < GameData.KEYWORD_BURST_BACKFIRE:
			GlobalData.break_combo()
			GlobalData.change_sanity(-10)
			GlobalData.change_belief(10)
			GlobalData.change_public(-6)
			_sfx("backfire")
			_show_custom_feedback("他抓住破绽反打了！", Color(1, 0.45, 0.4))
			boss_line.append_text("\n[color=#ff7a6b]（他把你的两张论据翻过来，反过来将了你一军。）[/color]")
			_update_all_bars()
			_update_keyword_ui()
			if not GlobalData.reduce_motion:
				noise_layer.color = Color(0.5, 0.08, 0.08, 0.35)
				var tw := create_tween()
				tw.tween_property(noise_layer, "color", Color(0.15, 0.05, 0.05, 0.22), 0.4)
		else:
			GlobalData.change_sanity(-5)
			GlobalData.change_belief(-GameData.KEYWORD_COMBO_BELIEF)
			GlobalData.change_public(10)
			GlobalData._unlock_achievement("ach_burst")
			_show_custom_feedback("两句话拼到一起，他没词了！", Color(1, 0.92, 0.6))
			boss_line.append_text("\n[color=#ffd76a]（你把两张论据拼成一句话，他张了张嘴，没接上。）[/color]")
			_update_all_bars()
			_update_keyword_ui()
			_play_hit_fx(-GameData.KEYWORD_COMBO_BELIEF, "perfect", false)

	await get_tree().create_timer(0.9).timeout

	var result := GlobalData.resolve_turn_end(GlobalData.current_round, false)
	if result != GlobalData.EndingType.NONE:
		_show_ending(result)
	else:
		_start_round(GlobalData.current_round + 1)

func _show_custom_feedback(text: String, color: Color) -> void:
	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_label.pivot_offset = feedback_label.size * 0.5
	feedback_label.modulate.a = 0.0
	feedback_label.scale = Vector2(0.88, 0.88)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(feedback_label, "modulate:a", 1.0, 0.12)
	tw.tween_property(feedback_label, "scale", Vector2(1, 1), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.4)
	tw.chain().tween_property(feedback_label, "modulate:a", 0.0, 0.25)

# ============================================================
# 答题弹窗
# ============================================================
func _open_quiz(r: int) -> void:
	quiz_round_num = r
	var data: Dictionary = GlobalData.get_quiz_data(r)
	var quote: String = data.get("question", "")
	# 不做成"考术语"的题：先摆出他刚说的那段话，让玩家自己指认哪里站不住
	quiz_question.text = "他刚才那段话——\n「%s」\n\n哪两处是他硬凑出来的因果？" % quote

	for child in quiz_options.get_children():
		child.queue_free()
	selected_quiz_options = []

	var options: Dictionary = data.get("options", {})
	var keys_sorted: Array = options.keys()
	keys_sorted.sort()
	for key in keys_sorted:
		var cb := CheckBox.new()
		# 只显示"他做了什么"，术语留到答完之后再讲，避免答题像背课本
		cb.text = "%s.  %s" % [key, _strip_term(options[key])]
		cb.add_theme_font_size_override("font_size", 16)
		cb.toggled.connect(_on_quiz_option_toggled.bind(key))
		quiz_options.add_child(cb)

	quiz_submit.text = "指认这两处"
	quiz_submit.disabled = true
	quiz_popup.visible = true

# 去掉选项里的学术名词前缀（"滑坡谬误：从…" → "从…"）
func _strip_term(text: String) -> String:
	for sep in ["：", ":"]:
		var idx: int = text.find(sep)
		if idx > 0 and idx <= 12:
			return text.substr(idx + sep.length())
	return text

# Godot 4 CheckBox.toggled(pressed: bool)
func _on_quiz_option_toggled(pressed: bool, key: String) -> void:
	if pressed:
		if not selected_quiz_options.has(key):
			selected_quiz_options.append(key)
	else:
		selected_quiz_options.erase(key)
	quiz_submit.disabled = selected_quiz_options.is_empty()

func _on_quiz_submit_pressed() -> void:
	quiz_popup.visible = false
	var data: Dictionary = GlobalData.get_quiz_data(quiz_round_num)
	var correct_keys: Array = data.get("correct", [])

	var sorted_sel: Array = selected_quiz_options.duplicate()
	sorted_sel.sort()
	var sorted_cor: Array = correct_keys.duplicate()
	sorted_cor.sort()
	var is_correct: bool = (sorted_sel == sorted_cor)

	var deltas: Dictionary = GameData.get_quiz_deltas(quiz_round_num, is_correct)
	GlobalData.change_sanity(int(deltas.get("sanity", 0)))
	if not GlobalData.is_empty_shell:
		GlobalData.change_belief(int(deltas.get("belief", 0)))
	GlobalData.change_public(int(deltas.get("public", 0)))

	GlobalData.on_quiz_answered(quiz_round_num, is_correct)

	# 答题后果：答对得关键词论据；答错下回合被嘲讽（但第 11 回合是决战前最后一次答题，不能覆盖第 12 回合决战台词）
	var consequence: String = ""
	if is_correct:
		var kw: String = data.get("keyword", "")
		if not kw.is_empty():
			GlobalData.add_keyword(kw)
		consequence = "[color=#ffd76a]★ 答对奖励：获得论据「%s」，可在任意回合亮出。[/color]" % kw
	else:
		if quiz_round_num >= 11:
			# 第 12 回合是决战，保留原台词，不替换
			consequence = "[color=#ff7a6b]⚠ 答错后果：理智 -%d，决战前心力更紧。[/color]" % GameData.QUIZ_WRONG_SANITY
		else:
			var next_r := quiz_round_num + 1
			GlobalData.boss_overrides[next_r] = GameData.BOSS_TAUNT_AFTER_WRONG.pick_random()
			consequence = "[color=#ff7a6b]⚠ 答错后果：理智 -%d，第 %d 回合他会更来劲。[/color]" % [GameData.QUIZ_WRONG_SANITY, next_r]

	var exp_text: String = ""
	if is_correct:
		exp_text += "[color=#7fe0a8]✓ 回答正确！[/color]\n\n"
	else:
		exp_text += "[color=#ff7a6b]✗ 回答错误[/color]\n\n"
	exp_text += "[b]正确答案：[/b]" + "、".join(PackedStringArray(correct_keys)) + "\n"
	exp_text += "[b]谬误类型：[/b]" + data.get("category", "") + "\n\n"
	exp_text += "[b]解析：[/b]" + data.get("explanation", "") + "\n\n"
	# 追加知识库条目（即时学习闭环）
	var cat: String = data.get("category", "")
	var kb_entry: Dictionary = GameData.lookup_knowledge(cat)
	if not kb_entry.is_empty():
		exp_text += "[color=#8fbcff]📘 知识库：[/color][b]%s[/b]\n" % kb_entry.get("name", "")
		exp_text += "[color=#aac4dd]%s[/color]\n" % kb_entry.get("desc", "")
		exp_text += "[color=#aac4dd]例：%s[/color]\n\n" % kb_entry.get("example", "")
	exp_text += consequence
	explain_label.text = exp_text

	boss_line.clear()
	var post: String = GlobalData.boss_post_quiz.get(quiz_round_num, "")
	boss_line.append_text("自洽先生： " + post)

	_update_all_bars()
	_update_keyword_ui()
	explain_popup.visible = true

func _on_quiz_continue() -> void:
	explain_popup.visible = false

	var result := GlobalData.resolve_turn_end(GlobalData.current_round, false)
	if result != GlobalData.EndingType.NONE:
		_show_ending(result)
	else:
		_start_round(GlobalData.current_round + 1)

# ============================================================
# 撤离二次确认
# ============================================================
func _show_withdraw_confirm() -> void:
	_set_choice_enabled(false)
	var r := GlobalData.current_round
	var react: String = GameData.WITHDRAW_REACT.get(r, "确定要结束这场争辩吗？")
	withdraw_react.text = react
	withdraw_popup.visible = true

func _on_withdraw_pressed() -> void:
	_show_withdraw_confirm()

func _on_withdraw_yes() -> void:
	withdraw_popup.visible = false
	GlobalData.resolve_turn_end(GlobalData.current_round, true)
	_show_ending(GlobalData.EndingType.WITHDRAW)

func _on_withdraw_no() -> void:
	withdraw_popup.visible = false
	_set_choice_enabled(true)

# ============================================================
# 结局
# ============================================================
func _show_ending(ending: int) -> void:
	var key: String = ""
	match ending:
		GlobalData.EndingType.WITHDRAW:
			if GlobalData.current_round <= 4:
				key = "withdraw_early"
			elif GlobalData.current_round <= 8:
				key = "withdraw_mid"
			else:
				key = "withdraw_late"
		GlobalData.EndingType.DIGNIFIED_LEAVE:
			key = "dignified"
		GlobalData.EndingType.DIGNIFIED_PUBLIC:
			key = "dignified_public"
		GlobalData.EndingType.DIGNIFIED_LONELY:
			key = "dignified_lonely"
		GlobalData.EndingType.LOGIC_BREAK:
			key = "logic_break"
		GlobalData.EndingType.LOGIC_BREAK_PUBLIC:
			key = "logic_break_public"
		GlobalData.EndingType.LOGIC_BREAK_PYRRIC:
			key = "logic_break_pyrric"
		GlobalData.EndingType.EMOTIONAL_BREAK:
			key = "emotional_break"
		GlobalData.EndingType.PUBLIC_CRUSHED:
			key = "public_crushed"
		GlobalData.EndingType.PUBLIC_IDOLIZED:
			key = "public_idolized"
	if key in ["logic_break", "logic_break_public", "logic_break_pyrric", "dignified", "dignified_public", "dignified_lonely"]:
		_sfx("win", 0.0, 1.0)
	elif key in ["emotional_break", "public_crushed", "public_idolized"]:
		_sfx("lose", 0.0, 0.95)
	else:
		_sfx("open")
	var data: Dictionary = GameData.ENDINGS.get(key, {})
	var is_new_ending := not GlobalData.is_ending_unlocked(key)
	GlobalData.unlock_ending(key)
	GlobalData.clear_run_save()  # 结局达成，清除中途存档

	ending_title.text = data.get("title", "")
	ending_sub.text = data.get("sub", "")
	ending_text.text = data.get("text", "")

	# 结局综述：评级 + 本局数据 + 一句评价
	var summary: Dictionary = GlobalData.build_summary(ending)
	var grade: String = summary.get("grade", "D")
	ending_grade.text = grade
	ending_grade.add_theme_color_override("font_color", _grade_color(grade))
	ending_summary.text = (
		"[center][b][color=#c8d4e8]评级 %s · %s ｜ 综合 %d 分[/color][/b][/center]\n" % [
			grade, summary.get("grade_title", ""), summary.get("score", 0)
		]
		+ "[center][color=#8fa0b8]%s[/color][/center]\n\n" % summary.get("verdict", "")
		+ GlobalData.build_summary_text(ending, summary)
		+ "\n\n[center][color=#9fb0c8]%s[/color][/center]" % GlobalData.summary_comment(summary)
	)

	var ach_list: Array = []
	for id in GlobalData.achievements.keys():
		var info: Dictionary = GameData.ACHIEVEMENTS.get(id, {})
		if not info.is_empty() and GlobalData.is_ach_unlocked(id):
			ach_list.append(info.get("title", ""))

	var bottom_msgs: Array = []
	if is_new_ending:
		bottom_msgs.append("[color=#c9a8ff]🎬 新结局解锁 · %s[/color]" % data.get("title", ""))
	if ach_list.size() > 0:
		bottom_msgs.append("[color=#ffd87a]★ 成就：%s[/color]" % "、".join(PackedStringArray(ach_list)))

	if bottom_msgs.size() > 0:
		ending_new_ach.visible = true
		ending_new_ach.text = "\n".join(bottom_msgs)
	else:
		ending_new_ach.visible = false

	ending_popup.visible = true

func _grade_color(grade: String) -> Color:
	match grade:
		"S": return Color(1, 0.85, 0.35)
		"A": return Color(0.55, 0.9, 0.75)
		"B": return Color(0.6, 0.78, 0.95)
		"C": return Color(0.78, 0.78, 0.72)
	return Color(0.7, 0.68, 0.68)

func _on_ending_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# ============================================================
# 数值 UI 更新
# ============================================================
func _update_all_bars() -> void:
	_tween_bar(sanity_bar, GlobalData.sanity)
	_tween_bar(belief_bar, GlobalData.belief)
	_tween_bar(public_bar, GlobalData.public_opinion)
	sanity_label.text = "理智  %d" % GlobalData.sanity
	belief_label.text = "信念  %d" % GlobalData.belief
	_refresh_public_label(GlobalData.public_opinion)
	_update_keyword_ui()
	_prev_sanity = GlobalData.sanity
	_prev_belief = GlobalData.belief

# 进度条平滑过渡：数值变化时用 tween 流动到目标值，避免生硬跳动
func _tween_bar(bar: ProgressBar, target: float) -> void:
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.set_ease(Tween.EASE_OUT)
	tw.tween_property(bar, "value", target, 0.35)

func _on_sanity_changed(v: int) -> void:
	_tween_bar(sanity_bar, v)
	sanity_label.text = "理智  %d" % v
	_float_delta(sanity_label, v - _prev_sanity)
	_prev_sanity = v
	_apply_sanity_fx(v)

func _on_belief_changed(v: int) -> void:
	_tween_bar(belief_bar, v)
	belief_label.text = "信念  %d" % v
	_float_delta(belief_label, v - _prev_belief)
	_prev_belief = v

# 数值变化时在进度条旁飘一个 +N / -N，让每次选择都有即时回响
func _float_delta(anchor: Control, delta: int) -> void:
	if delta == 0 or GlobalData.reduce_motion:
		return
	var lbl := Label.new()
	lbl.text = ("+%d" % delta) if delta > 0 else ("%d" % delta)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color",
		Color(0.45, 0.92, 0.6) if delta > 0 else Color(1, 0.45, 0.4))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lbl)
	lbl.position = anchor.global_position + Vector2(anchor.size.x - 6, 0)

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(lbl, "position:y", lbl.position.y - 26.0, 0.7)
	tw.tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.25)
	tw.chain().tween_callback(lbl.queue_free)

func _on_public_changed(v: int) -> void:
	_tween_bar(public_bar, v)
	_refresh_public_label(v)
	if v <= GlobalData.PUBLIC_COLLAPSE + 5 and not _public_warned_low:
		_public_warned_low = true
		_show_toast("围观快散了", "舆论再跌到 %d，你会被当场轰下台。" % GlobalData.PUBLIC_COLLAPSE, Color(1, 0.45, 0.4))
	elif v >= GlobalData.PUBLIC_IDOLIZE - 12 and not _public_warned_high:
		_public_warned_high = true
		_show_toast("你被推上去了", "舆论再涨到 %d，你会被架成符号，话都不再是自己的。" % GlobalData.PUBLIC_IDOLIZE, Color(1, 0.75, 0.35))
	_spawn_crowd_comment(v - _last_public_val)
	_last_public_val = v

# 舆论接近双向死亡线时变色警示（让玩家知道"再推会出事"）
func _refresh_public_label(v: int) -> void:
	if v <= GlobalData.PUBLIC_COLLAPSE + 5:
		public_label.text = "围观  %d  ⚠ 没人听" % v
		public_label.add_theme_color_override("font_color", Color(1, 0.45, 0.4))
	elif v >= GlobalData.PUBLIC_IDOLIZE - 12:
		public_label.text = "围观  %d  ⚠ 捧太高" % v
		public_label.add_theme_color_override("font_color", Color(1, 0.75, 0.35))
	else:
		public_label.text = "围观  %d" % v
		public_label.add_theme_color_override("font_color", Color(0.85, 0.8, 0.5))

# ★ 围观者弹幕：public 变化时底部飘评论条
const CROWD_POSITIVE: Array = [
	"有人点头了",
	"说的好像有道理",
	"等下，他好像说漏了？",
	"这人挺能说的",
	"……我信一半吧",
	"有点意思",
	"我站这边好像"
]
const CROWD_NEGATIVE: Array = [
	"有人窃笑",
	"这也能圆？",
	"不是吧……",
	"好尬",
	"这人强词夺理",
	"听得我尴尬癌都犯了",
	"等等，别吵了行不"
]

func _spawn_crowd_comment(delta: int) -> void:
	if GlobalData.reduce_motion or abs(delta) < 2:
		return

	var comment: String = ""
	var color := Color.WHITE
	if delta > 0:
		comment = CROWD_POSITIVE[randi() % CROWD_POSITIVE.size()]
		color = Color(0.65, 0.88, 0.72, 0.9)
	elif delta < 0:
		comment = CROWD_NEGATIVE[randi() % CROWD_NEGATIVE.size()]
		color = Color(1, 0.5, 0.5, 0.85)

	var label := Label.new()
	label.text = "▸ %s" % comment
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 从屏幕左下往上飘
	add_child(label)
	label.anchor_left = 0
	label.anchor_right = 0
	var x1: float = 20.0 + float(randi_range(0, 120))
	var x2: float = x1 + 200.0 + float(randi_range(0, 80))
	label.offset_left = x1
	label.offset_right = x2
	label.offset_top = 560
	label.offset_bottom = 580
	label.modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "modulate:a", 1.0, 0.3)
	tw.tween_property(label, "offset_top", 400 - randi_range(0, 80), 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "offset_bottom", 420 - randi_range(0, 80), 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.5)
	tw.tween_property(label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(label.queue_free)

func _on_keyword_changed(kws: Array) -> void:
	_update_keyword_ui()
	if kws.size() > _last_kw_count:
		_show_toast("🧩 获得论据", "「%s」已收入囊中" % kws.back(), Color(1, 0.85, 0.55))
	_last_kw_count = kws.size()

func _on_combo_changed(_combo: int) -> void:
	if GlobalData.current_round > 0 and not GlobalData.is_quiz_round(GlobalData.current_round):
		_update_hint()

func _on_stage_changed(stage: int) -> void:
	stage_label.text = _stage_name(stage)
	_apply_stage_visual(stage)
	if not _first_stage_sync:
		_play_stage_ceremony(stage)

# ============================================================
# 视觉反馈
# ============================================================
func _apply_sanity_fx(v: int) -> void:
	if GlobalData.reduce_motion:
		vignette_layer.color = Color(0, 0, 0, 0)
		noise_layer.color = Color(0, 0, 0, 0)
		return

	var intensity: float = 0.0
	if v <= 20:
		intensity = 1.0
	elif v <= 50:
		intensity = (50 - v) / 30.0

	# 颜色：san 越低越红、越黑
	var red_amount: float = intensity
	vignette_layer.color = Color(0.4 * red_amount, 0, 0, clampf(0.15 + intensity * 0.35, 0.15, 0.55))
	noise_layer.color = Color(0.35 * red_amount, 0.0, 0.0, clampf(intensity * 0.25, 0, 0.25))

	# 心跳脉冲（独立循环）
	if _hb_tween and _hb_tween.is_valid():
		_hb_tween.kill()
		_hb_tween = null
	if intensity > 0.01:
		var interval: float = lerp(0.7, 0.3, intensity)
		_hb_tween = create_tween().set_loops()
		_hb_tween.tween_interval(interval)
		_hb_tween.tween_property(vignette_layer, "modulate:a", 0.6 + intensity * 0.4, 0.08)
		_hb_tween.tween_property(vignette_layer, "modulate:a", 1.0, interval * 0.6)
	else:
		vignette_layer.modulate.a = 1.0

	# 极度过载（≤20）：BOSS 台词偶发"卡壳"（独立 timer）
	if _stutter_tween and _stutter_tween.is_valid():
		_stutter_tween.kill()
		_stutter_tween = null
	if v <= 20 and intensity > 0.5:
		_stutter_tween = create_tween().set_loops()
		_stutter_tween.tween_interval(2.2)
		_stutter_tween.tween_callback(_micro_stutter)

func _micro_stutter() -> void:
	if quiz_popup.visible or ending_popup.visible or GlobalData.is_empty_shell:
		return
	if randf() < 0.5:
		var base: float = boss_line.visible_ratio
		var tw := create_tween()
		tw.tween_property(boss_line, "visible_ratio", maxf(base - 0.22, 0.4), 0.06)
		tw.tween_property(boss_line, "visible_ratio", minf(base + 0.02, 1.0), 0.08)

func _apply_stage_visual(stage: int) -> void:
	var tint := Color.WHITE
	if _boss_is_png:
		# AI 立绘本身有完整色彩，modulate 只给极轻微的色温暗示，不破坏原画
		match stage:
			GlobalData.Stage.OPENING:
				tint = Color(0.92, 0.96, 1.0)      # 微冷蓝
			GlobalData.Stage.STUBBORN:
				tint = Color(1.0, 0.97, 0.95)      # 微暖
			GlobalData.Stage.COLLAPSE:
				tint = Color(1.0, 0.93, 0.93)      # 微红
			GlobalData.Stage.EMPTY_SHELL:
				tint = Color(0.9, 0.9, 0.92)       # 微灰
	else:
		# SVG 图标靠强染色体现阶段
		match stage:
			GlobalData.Stage.OPENING:
				tint = Color(0.25, 0.45, 0.7)
			GlobalData.Stage.STUBBORN:
				tint = Color(0.42, 0.33, 0.38)
			GlobalData.Stage.COLLAPSE:
				tint = Color(0.5, 0.24, 0.26)
			GlobalData.Stage.EMPTY_SHELL:
				tint = Color(0.28, 0.28, 0.32)
	if boss_icon:
		boss_icon.modulate = tint

	if GlobalData.reduce_motion:
		noise_layer.color = Color(0, 0, 0, 0)
		return
	match stage:
		GlobalData.Stage.OPENING:
			noise_layer.color = Color(0, 0, 0, 0)
		GlobalData.Stage.STUBBORN:
			noise_layer.color = Color(0.1, 0.05, 0.05, 0.08)
		GlobalData.Stage.COLLAPSE:
			noise_layer.color = Color(0.15, 0.05, 0.05, 0.22)
		GlobalData.Stage.EMPTY_SHELL:
			noise_layer.color = Color(0, 0, 0, 0.15)

func _boss_set_stance(stance_id: String) -> void:
	if _stance_anim and _stance_anim.is_valid():
		_stance_anim.kill()
		_stance_anim = null
	if _stance_layer == null:
		return

	# 空壳阶段：姿态层直接换成 mask 灰图标，不再做任何动画
	if GlobalData.is_empty_shell:
		var mask_tex: Texture2D = _get_icon("mask")
		_stance_layer.texture = mask_tex
		_stance_layer.modulate = Color(0.55, 0.58, 0.65, 1.0)
		return

	# 姿态差分立绘：如果有 boss_<姿态>.png，直接切换立绘本身的动作，不再叠加 SVG 图标
	var stance_png: Texture2D = _get_image("boss_" + stance_id)
	var using_stance_png: bool = stance_png != null and boss_icon != null
	if using_stance_png:
		boss_icon.texture = stance_png
		_stance_layer.modulate.a = 0.0  # 隐藏 SVG 姿态层，立绘本身已带姿态
	elif boss_icon != null:
		var base_tex: Texture2D = _get_image("boss")
		if base_tex:
			boss_icon.texture = base_tex

	var stance_tex: Texture2D = _get_icon(stance_id) if not using_stance_png else null
	if stance_tex:
		_stance_layer.texture = stance_tex
		var sc: String = GameData.STANCES.get(stance_id, {}).get("color", "#ffffff")
		_stance_layer.modulate = Color.from_string(sc, Color.WHITE)
	elif not using_stance_png:
		_stance_layer.texture = null
		_stance_layer.modulate = Color(1, 1, 1, 0.0)

	# 换招反馈：姿态层淡入 + 主 BOSS 闪白
	var has_visual: bool = (using_stance_png) or (stance_tex != null)
	if not GlobalData.reduce_motion and has_visual and boss_icon:
		_stance_layer.pivot_offset = _stance_layer.size * 0.5
		if not using_stance_png:
			_stance_layer.modulate.a = 0.0
			var tw_fade := create_tween()
			tw_fade.tween_property(_stance_layer, "modulate:a", 1.0, 0.35)
		boss_icon.pivot_offset = boss_icon.size * 0.5
		var tw_flash := create_tween()
		tw_flash.set_parallel(true)
		tw_flash.tween_property(boss_icon, "modulate", Color(2, 2, 2), 0.08)
		tw_flash.chain().tween_property(boss_icon, "modulate", _apply_stage_visual_return_tint(), 0.25)
	elif stance_tex != null:
		_stance_layer.modulate.a = 1.0

	# 按姿态启动循环动画（无动态设置直接用 color）
	if GlobalData.reduce_motion or stance_tex == null:
		return
	match stance_id:
		"provoke":
			_anim_provoke()
		"victim":
			_anim_victim()
		"reason":
			_anim_reason()
		"mob":
			_anim_mob()

# _apply_stage_visual 内部只赋值不 return，颜色给 stage_changed 用
# 这里提供一个查询当前阶段 boss_icon 应该用什么 tint 的函数
func _apply_stage_visual_return_tint() -> Color:
	var tint := Color.WHITE
	if _boss_is_png:
		match GlobalData.battle_stage:
			GlobalData.Stage.OPENING:
				tint = Color(0.92, 0.96, 1.0)
			GlobalData.Stage.STUBBORN:
				tint = Color(1.0, 0.97, 0.95)
			GlobalData.Stage.COLLAPSE:
				tint = Color(1.0, 0.93, 0.93)
			GlobalData.Stage.EMPTY_SHELL:
				tint = Color(0.9, 0.9, 0.92)
	else:
		match GlobalData.battle_stage:
			GlobalData.Stage.OPENING:
				tint = Color(0.25, 0.45, 0.7)
			GlobalData.Stage.STUBBORN:
				tint = Color(0.42, 0.33, 0.38)
			GlobalData.Stage.COLLAPSE:
				tint = Color(0.5, 0.24, 0.26)
			GlobalData.Stage.EMPTY_SHELL:
				tint = Color(0.28, 0.28, 0.32)
	return tint

func _anim_provoke() -> void:
	# 挑衅：快速左右抖动 ±4°
	_stance_layer.rotation = 0.0
	_stance_anim = create_tween().set_loops()
	_stance_anim.tween_property(_stance_layer, "rotation", 0.06, 0.05)
	_stance_anim.tween_property(_stance_layer, "rotation", -0.06, 0.05)

func _anim_victim() -> void:
	# 卖惨：缓慢下沉 5px 再回弹（呼吸感）
	var base_y: float = 0.0
	_stance_anim = create_tween().set_loops()
	_stance_anim.tween_property(_stance_layer, "position:y", base_y + 5.0, 1.2)
	_stance_anim.tween_property(_stance_layer, "position:y", base_y, 1.2)

func _anim_reason() -> void:
	# 讲理：微缩 0.97 缓慢还原（僵硬理性感）
	_stance_layer.scale = Vector2.ONE
	_stance_layer.pivot_offset = _stance_layer.size * 0.5
	_stance_anim = create_tween().set_loops()
	_stance_anim.tween_property(_stance_layer, "scale", Vector2(0.97, 0.97), 1.5)
	_stance_anim.tween_property(_stance_layer, "scale", Vector2.ONE, 1.2)

func _anim_mob() -> void:
	# 拉围观：脉冲放大（煽动气场）
	_stance_layer.scale = Vector2.ONE
	_stance_layer.pivot_offset = _stance_layer.size * 0.5
	var base_col: Color = _stance_layer.modulate
	_stance_anim = create_tween().set_loops()
	# loop + parallel 需显式分两组，chain 让每轮从头开始
	_stance_anim.set_parallel(true)
	_stance_anim.tween_property(_stance_layer, "scale", Vector2(1.06, 1.06), 0.6)
	_stance_anim.tween_property(_stance_layer, "modulate:a", 0.75, 0.6)
	_stance_anim.chain().set_parallel(true)
	_stance_anim.tween_property(_stance_layer, "scale", Vector2.ONE, 0.9)
	_stance_anim.tween_property(_stance_layer, "modulate:a", 1.0, 0.9)

func _stage_name(stage: int) -> String:
	match stage:
		GlobalData.Stage.OPENING: return "阶段 1 · 自洽开局"
		GlobalData.Stage.STUBBORN: return "阶段 2 · 固执防御"
		GlobalData.Stage.COLLAPSE: return "阶段 3 · 逻辑崩塌"
		GlobalData.Stage.EMPTY_SHELL: return "⚠ 空壳阶段"
	return ""
