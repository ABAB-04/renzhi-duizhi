extends Node

# ============================================================
# GlobalData.gd — 全局状态管理（Autoload）
# ============================================================

const GameData = preload("res://core/game_data.gd")

signal sanity_changed(new_val: int)
signal belief_changed(new_val: int)
signal public_changed(new_val: int)
signal stage_changed(new_stage: int)
signal achievement_unlocked(id: String)
signal keyword_changed(keywords: Array)
signal combo_changed(combo: int)

# ---------- 游戏常量 ----------
const INIT_SANITY := 100
const HARD_INIT_SANITY := 80   # 困难模式理智起点
const INIT_BELIEF := 100
const INIT_PUBLIC := 50
const MAX_ROUND := 12
const PUBLIC_COLLAPSE := 15   # 舆论跌破此值：被围观者轰下台
const PUBLIC_IDOLIZE := 92    # 舆论涨过此值：被架成符号，失去自己

# BOSS 阶段枚举
enum Stage {
    OPENING,       # 阶段1 自洽开局  belief > 60
    STUBBORN,      # 阶段2 固执防御  20 < belief <= 60
    COLLAPSE,      # 阶段3 逻辑崩塌  0 < belief <= 20
    EMPTY_SHELL    # 空壳阶段 belief <= 0 && round < MAX_ROUND
}

# 结局枚举
enum EndingType {
    NONE,
    WITHDRAW,
    DIGNIFIED_LEAVE,
    DIGNIFIED_PUBLIC,
    DIGNIFIED_LONELY,
    LOGIC_BREAK,
    LOGIC_BREAK_PUBLIC,
    LOGIC_BREAK_PYRRIC,
    EMOTIONAL_BREAK,
    PUBLIC_CRUSHED,
    PUBLIC_IDOLIZED
}

# ---------- 运行时状态 ----------
var sanity: int = INIT_SANITY
var belief: int = INIT_BELIEF
var public_opinion: int = INIT_PUBLIC
var current_round: int = 1
var battle_stage: int = Stage.OPENING
var is_empty_shell: bool = false

# 关键词论据（答对谬误题获得，可单张亮出或两张拼合）
var keywords: Array = []
var keyword_earned: int = 0   # 本局收集总数
var keyword_used: int = 0     # 本局消耗总数
var combo: int = 0            # 连续识破次数
var best_combo: int = 0
var perfect_count: int = 0    # 本局识破次数
var backfire_count: int = 0   # 本局被带偏次数
var good_count: int = 0
var weak_count: int = 0
var rounds_played: int = 0

# 本局随机内容
var current_scene: Dictionary = {}
var scene_setup: String = ""
var boss_lines: Dictionary = {}
var boss_stances: Dictionary = {}     # {round: stance id}
var boss_options: Dictionary = {}     # {round: [ {type, text}, ... ]}
var quiz_data: Dictionary = {}
var boss_post_quiz: Dictionary = {}
var boss_overrides: Dictionary = {}
var run_events: Dictionary = {}       # {round: event id} 每局 1~2 个随机事件

# 玩家行为追踪（用于成就）
var quiz_correct: Dictionary = {}

# 设置
var reduce_motion: bool = false

# 玩家性格（开局前选择，跨局保留）
var personality: String = "hot"

# 成就持久化
var achievements: Dictionary = {}
const ACH_SAVE_PATH := "user://achievements.cfg"

# 中途存档（继续游戏用）—— 每回合结束自动存盘，防止演示中断后重来
const RUN_SAVE_PATH := "user://run_save.json"

# 结局图鉴 + 困难模式
var unlocked_endings: Dictionary = {}   # {ending_key: true}
var beaten_once: bool = false           # 通关任意结局后解锁困难模式
var hard_mode: bool = false             # 困难模式：理智 80 起步，不显示姿态名
var run_goal: String = ""               # 本局目标：crush / crowd / dignity
var seen_tutorial: bool = false         # 首回合引导浮层（只弹一次，存进存档）

func is_quiz_round(r: int) -> bool:
    return r == 3 or r == 7 or r == 11

# ---------- 初始化 ----------
func _ready() -> void:
    reset_game()
    load_achievements()

func reset_game() -> void:
    sanity = HARD_INIT_SANITY if hard_mode else INIT_SANITY
    belief = INIT_BELIEF
    public_opinion = INIT_PUBLIC
    current_round = 1
    battle_stage = Stage.OPENING
    is_empty_shell = false
    keywords.clear()
    keyword_earned = 0
    keyword_used = 0
    combo = 0
    best_combo = 0
    perfect_count = 0
    backfire_count = 0
    good_count = 0
    weak_count = 0
    rounds_played = 0
    quiz_correct.clear()
    _roll_run_content()

# 每局抽取一个场景，台词/姿态/选项/题目全部围绕它展开
func _roll_run_content() -> void:
    var idx := randi() % GameData.SCENES.size()
    current_scene = GameData.SCENES[idx].duplicate(true)

    scene_setup = current_scene.get("setup", "")

    boss_lines.clear()
    for r in current_scene.get("lines", {}).keys():
        boss_lines[r] = current_scene["lines"][r]

    boss_stances.clear()
    for r in current_scene.get("stances", {}).keys():
        boss_stances[r] = current_scene["stances"][r]

    boss_options.clear()
    for r in current_scene.get("options", {}).keys():
        var opts: Array = current_scene["options"][r].duplicate(true)
        opts.shuffle()
        boss_options[r] = opts

    quiz_data.clear()
    for r in current_scene.get("quiz", {}).keys():
        quiz_data[r] = current_scene["quiz"][r].duplicate(true)

    boss_post_quiz.clear()
    for r in current_scene.get("post_quiz", {}).keys():
        boss_post_quiz[r] = current_scene["post_quiz"][r]

    boss_overrides.clear()

    # 本局目标：随机抽一个，尽量不与上一局重复
    var goal_keys: Array = GameData.GOALS.keys()
    var pick: String = goal_keys[randi() % goal_keys.size()]
    if goal_keys.size() > 1 and pick == run_goal:
        pick = goal_keys[(goal_keys.find(pick) + 1) % goal_keys.size()]
    run_goal = pick
    _roll_events()

# 每局抽 1~2 个事件回合（避开第 1、答题、决战回合）
func _roll_events() -> void:
    run_events.clear()
    var pool: Array = [2, 4, 5, 6, 8, 9, 10]
    pool.shuffle()
    var count := 2 if randf() < 0.6 else 1
    var ids := GameData.RANDOM_EVENTS.keys()
    for i in range(count):
        run_events[pool[i]] = ids[randi() % ids.size()]

func get_event(r: int) -> Dictionary:
    if not run_events.has(r):
        return {}
    return GameData.RANDOM_EVENTS.get(run_events[r], {})

# 应用事件数值；返回事件触发的提示（供 UI 显示）
func apply_event(r: int) -> Dictionary:
    var ev := get_event(r)
    if ev.is_empty():
        return {}
    var effect: Dictionary = ev.get("effect", {})
    if effect.has("sanity"):
        change_sanity(int(effect["sanity"]))
    if effect.has("public"):
        change_public(int(effect["public"]))
    if effect.get("reroll_stance", false):
        var ids := GameData.STANCES.keys()
        var new_stance: String = ids[randi() % ids.size()]
        if new_stance != boss_stances.get(r, ""):
            boss_stances[r] = new_stance
    return ev

func get_boss_line(r: int) -> String:
    if boss_overrides.has(r):
        return boss_overrides[r]
    if is_empty_shell:
        return GameData.EMPTY_SHELL_LINES[(r - 1) % GameData.EMPTY_SHELL_LINES.size()]
    return boss_lines.get(r, "")

# 答题数据：当前回合 → 原数据映射（原 3/7/11 的题分配给回合 2/5）
func get_quiz_data(r: int) -> Dictionary:
    var legacy_map: Dictionary = {2: 3, 5: 7}
    var legacy_r: int = int(legacy_map.get(r, r))
    var result: Dictionary = quiz_data.get(legacy_r, {})
    return result

func get_post_quiz(r: int) -> String:
    var legacy_map: Dictionary = {2: 3, 5: 7}
    var legacy_r: int = int(legacy_map.get(r, r))
    return boss_post_quiz.get(legacy_r, "")

func get_stance(r: int) -> String:
    return boss_stances.get(r, "provoke")

func get_options(r: int) -> Array:
    return boss_options.get(r, [])

func stance_info(stance_id: String) -> Dictionary:
    return GameData.STANCES.get(stance_id, GameData.STANCES["provoke"])

func approach_info(approach_id: String) -> Dictionary:
    return GameData.APPROACHES.get(approach_id, {})

# 读招：返回 perfect / good / weak / backfire
func evaluate(stance_id: String, approach_id: String) -> String:
    return GameData.MATCH.get(stance_id, {}).get(approach_id, "weak")

# 性格修正：拿手的方式升一档，不擅长的降一档
func apply_personality_rating(base: String, approach_id: String) -> String:
    var p: Dictionary = GameData.PERSONALITIES.get(personality, {})
    if p.is_empty():
        return base
    var idx: int = GameData.RATING_ORDER.find(base)
    if idx < 0:
        return base
    if p.get("up", "") == approach_id:
        idx = clampi(idx + 1, 0, GameData.RATING_ORDER.size() - 1)
    elif p.get("down", "") == approach_id:
        idx = clampi(idx - 1, 0, GameData.RATING_ORDER.size() - 1)
    return GameData.RATING_ORDER[idx]

func personality_info() -> Dictionary:
    return GameData.PERSONALITIES.get(personality, {})

# ---------- 本局目标 ----------
func goal_info() -> Dictionary:
    return GameData.GOALS.get(run_goal, {})

func goal_reached() -> bool:
    match run_goal:
        "crush":
            return belief <= 0
        "crowd":
            return public_opinion >= 70
        "dignity":
            return sanity >= 40
    return false

# 普通模式：只给两条语气线索，玩家自己判断他在这招
# 同场景同回合结果固定（不会每帧闪变），不同场景/回合会换组合
func get_stance_clues(r: int) -> Array:
    var stance_id: String = get_stance(r)
    var info: Dictionary = GameData.STANCES.get(stance_id, {})
    var pool: Array = info.get("clues", [])
    if pool.is_empty():
        return []
    var base: int = r * 7 + scene_setup.length()
    var first: int = base % pool.size()
    if pool.size() < 2:
        return [pool[first]]
    var second: int = (first + 1 + (base / 3) % (pool.size() - 1)) % pool.size()
    return [pool[first], pool[second]]

# ---------- 数值变更 ----------
func change_sanity(delta: int) -> void:
    sanity = clamp(sanity + delta, 0, 100)
    sanity_changed.emit(sanity)

func change_belief(delta: int) -> void:
    belief = clamp(belief + delta, 0, 100)
    belief_changed.emit(belief)
    update_stage()

func change_public(delta: int) -> void:
    # 舆论越接近上限越难推：给玩家留出"收手"的回合，而不是一路平推直接自爆
    if delta > 0 and public_opinion >= 85:
        delta = maxi(1, int(round(delta * 0.5)))
    public_opinion = clamp(public_opinion + delta, 0, 100)
    public_changed.emit(public_opinion)

func add_keyword(kw: String) -> void:
    if kw.is_empty():
        return
    keywords.append(kw)
    keyword_earned += 1
    keyword_changed.emit(keywords.duplicate())

func consume_keywords(count: int) -> void:
    for i in range(count):
        if keywords.is_empty():
            break
        keywords.pop_back()
        keyword_used += 1
    keyword_changed.emit(keywords.duplicate())

func keyword_count() -> int:
    return keywords.size()

func can_burst() -> bool:
    return keywords.size() >= 2

func break_combo() -> void:
    combo = 0
    combo_changed.emit(combo)

# 记录一次读招结果，维护连击与成就
func note_rating(rating: String) -> void:
    rounds_played += 1
    if rating == "perfect":
        perfect_count += 1
        combo += 1
        if combo > best_combo:
            best_combo = combo
        if combo >= 3:
            _unlock_achievement("ach_combo3")
        if combo >= 5:
            _unlock_achievement("ach_combo5")
    else:
        if rating == "good":
            good_count += 1
        elif rating == "weak":
            weak_count += 1
        combo = 0
        if rating == "backfire":
            backfire_count += 1
            if backfire_count >= 3:
                _unlock_achievement("ach_backfire")
    combo_changed.emit(combo)

func update_stage() -> void:
    var old_stage := battle_stage
    var new_stage := battle_stage

    if is_empty_shell:
        new_stage = Stage.EMPTY_SHELL
    elif belief > 60:
        new_stage = Stage.OPENING
    elif belief > 20:
        new_stage = Stage.STUBBORN
    elif belief > 0:
        new_stage = Stage.COLLAPSE
    else:
        if current_round < MAX_ROUND:
            is_empty_shell = true
            new_stage = Stage.EMPTY_SHELL
        else:
            new_stage = Stage.COLLAPSE

    if new_stage != old_stage:
        battle_stage = new_stage
        stage_changed.emit(new_stage)

# ---------- 结局判定 ----------
func resolve_turn_end(round_index: int, did_withdraw: bool) -> int:
    sanity = clamp(sanity, 0, 100)
    belief = clamp(belief, 0, 100)
    public_opinion = clamp(public_opinion, 0, 100)

    # 撤离优先级最高
    if did_withdraw:
        _unlock_achievement("ach_withdraw")
        return EndingType.WITHDRAW

    # 同帧归零：惨胜
    if sanity <= 0 and belief <= 0:
        _unlock_achievement("ach_logic_break")
        return EndingType.LOGIC_BREAK_PYRRIC

    # 理智归零 → 情绪破防
    if sanity <= 0:
        _unlock_achievement("ach_emotional_break")
        return EndingType.EMOTIONAL_BREAK

    # 舆论双向死亡：被围观者抛弃 / 被围观者架成符号
    # 信念已破时跳过（那已经是玩家的胜利，不该被舆论反杀）
    if belief > 0:
        if public_opinion <= PUBLIC_COLLAPSE:
            return EndingType.PUBLIC_CRUSHED
        if public_opinion >= PUBLIC_IDOLIZE:
            return EndingType.PUBLIC_IDOLIZED

    # 信念提前归零，未到终局 → 进入空壳阶段
    if belief <= 0 and round_index < MAX_ROUND:
        is_empty_shell = true
        update_stage()
        return EndingType.NONE

    # 终局结算
    if round_index >= MAX_ROUND:
        if belief <= 0:
            _unlock_achievement("ach_logic_break")
            if public_opinion >= 60:
                return EndingType.LOGIC_BREAK_PUBLIC
            return EndingType.LOGIC_BREAK
        else:
            _unlock_achievement("ach_dignified")
            if public_opinion >= 70:
                _unlock_achievement("ach_public70")
            if public_opinion >= 60:
                return EndingType.DIGNIFIED_PUBLIC
            elif public_opinion <= 30:
                return EndingType.DIGNIFIED_LONELY
            return EndingType.DIGNIFIED_LEAVE

    return EndingType.NONE

# ---------- 结局综述 ----------
func quiz_correct_count() -> int:
    var n := 0
    for v in quiz_correct.values():
        if v:
            n += 1
    return n

# 综合评级：结局质量 + 剩余理智 + 舆论 + 识破表现 + 谬误辨识
func build_summary(ending: int) -> Dictionary:
    var base := 0
    var verdict := ""
    match ending:
        EndingType.LOGIC_BREAK_PUBLIC:
            base = 55
            verdict = "你把他的话说成了笑话，在场的人全看着。这一局，你赢得漂亮。"
        EndingType.LOGIC_BREAK:
            base = 48
            verdict = "他自己说不下去了。房间里也许没人为你鼓掌，但你知道自己赢了。"
        EndingType.LOGIC_BREAK_PYRRIC:
            base = 36
            verdict = "你拆穿了他，也把自己耗空了。赢是赢了，就是有点惨。"
        EndingType.DIGNIFIED_PUBLIC:
            base = 38
            verdict = "你没把他逼到墙角，却让所有人都看清了这场争论。这叫全身而退。"
        EndingType.DIGNIFIED_LEAVE:
            base = 26
            verdict = "你没赢，也没输。守住了自己，已经是这场争辩里少见的结局。"
        EndingType.DIGNIFIED_LONELY:
            base = 20
            verdict = "每一句你都说对了。可道理赢了，人散了。"
        EndingType.EMOTIONAL_BREAK:
            base = 5
            verdict = "你被拖进了他的节奏。这不怪你，很少有人能一直不生气。"
        EndingType.PUBLIC_CRUSHED:
            base = 6
            verdict = "你说了很多，可没人愿意再听。人群散开的时候，你才发现自己一直是在对空气讲道理。"
        EndingType.PUBLIC_IDOLIZED:
            base = 30
            verdict = "所有人都站到了你这边。你赢了掌声，却发现自己的话已经被他们改成了另一个意思。"
        EndingType.WITHDRAW:
            base = 12
            verdict = "你选择了不下场。有些争辩，退出就是最好的回答。"
        _:
            base = 15
            verdict = ""

    var san_score := int(sanity * 0.10)
    var pub_score := int(public_opinion * 0.10)
    var perfect_score := mini(perfect_count * 2, 20)
    var quiz_score := quiz_correct_count() * 4
    var combo_score := mini(best_combo * 2, 8)
    var penalty := backfire_count * 4
    # 本局目标：达成额外加分
    var goal_done: bool = goal_reached()
    var goal_bonus: int = 8 if goal_done else 0

    var score: int = clampi(base + san_score + pub_score + perfect_score + quiz_score + combo_score - penalty + goal_bonus, 0, 100)

    var grade := "D"
    var grade_title := "还需练习"
    if score >= 95:
        grade = "S"
        grade_title = "完美收官"
    elif score >= 82:
        grade = "A"
        grade_title = "说得漂亮"
    elif score >= 68:
        grade = "B"
        grade_title = "稳住了"
    elif score >= 52:
        grade = "C"
        grade_title = "还算体面"

    return {
        "score": score,
        "grade": grade,
        "grade_title": grade_title,
        "verdict": verdict,
        "goal_name": goal_info().get("name", ""),
        "goal_icon": goal_info().get("icon", ""),
        "goal_reached": goal_done,
        "goal_bonus": goal_bonus
    }

# 综述文本（BBCode）
func build_summary_text(ending: int, summary: Dictionary) -> String:
    var p: Dictionary = personality_info()
    var lines: Array = []
    lines.append("[color=#8fa0b8]性格[/color]   %s %s" % [p.get("icon", ""), p.get("name", "")])
    var goal_line: String = "%s %s" % [summary.get("goal_icon", ""), summary.get("goal_name", "")]
    if summary.get("goal_reached", false):
        goal_line += "  [color=#8fe0b0]达成 +%d 分[/color]" % int(summary.get("goal_bonus", 0))
    else:
        goal_line += "  [color=#8a90a0]未达成[/color]"
    lines.append("[color=#8fa0b8]本局目标[/color] %s" % goal_line)
    lines.append("[color=#8fa0b8]回合[/color]   %d / %d（交锋 %d 次）" % [current_round, MAX_ROUND, rounds_played])
    lines.append("[color=#8fa0b8]识破[/color]   %d 次（最高连击 %d）" % [perfect_count, best_combo])
    if good_count > 0 or weak_count > 0:
        lines.append("[color=#8fa0b8]判定[/color]   接住 %d 次 · 没接住 %d 次" % [good_count, weak_count])
    if backfire_count > 0:
        lines.append("[color=#8fa0b8]被带偏[/color] %d 次" % backfire_count)
    lines.append("[color=#8fa0b8]谬误题[/color] %d / %d 正确" % [quiz_correct_count(), quiz_correct.size()])
    lines.append("[color=#8fa0b8]论据[/color]   收集 %d · 用掉 %d" % [keyword_earned, keyword_used])
    lines.append("[color=#8fa0b8]最终[/color]   理智 %d · 信念 %d · 围观 %d" % [sanity, belief, public_opinion])
    return "\n".join(PackedStringArray(lines))

func summary_comment(summary: Dictionary) -> String:
    var grade: String = summary.get("grade", "D")
    var comments := {
        "S": "这一局没什么可挑的：你几乎读准了每一次语气。",
        "A": "大部分时候你都在节奏里，只是偶尔被他带偏。",
        "B": "该拿的分拿到了，但还有几次可以更狠。",
        "C": "你守住了底线，不过有几句话可以接得更准。",
        "D": "这一局你被对方牵着走的时候不少，下一局试试先听语气再开口。"
    }
    return comments.get(grade, "")

# ---------- 成就 ----------
func _unlock_achievement(id: String) -> void:
    if not achievements.get(id, false):
        achievements[id] = true
        save_achievements()
        achievement_unlocked.emit(id)

func _all_quizzes_correct() -> bool:
    if quiz_correct.size() < 3:
        return false
    for v in quiz_correct.values():
        if not v:
            return false
    return true

func check_behavior_achievements() -> void:
    if _all_quizzes_correct():
        _unlock_achievement("ach_critical")

func on_quiz_answered(round_num: int, correct: bool) -> void:
    quiz_correct[round_num] = correct
    if correct:
        _unlock_achievement("ach_fallacy_r2")
    check_behavior_achievements()

# ---------- 持久化 ----------
# 存档格式：{"achievements": {...}, "endings": {...}, "beaten": bool}
# 兼容旧格式：整个文件就是 achievements 字典
func save_achievements() -> void:
    var file := FileAccess.open(ACH_SAVE_PATH, FileAccess.WRITE)
    if file == null:
        push_warning("无法写入成就存档")
        return
    var data := JSON.stringify({
        "achievements": achievements,
        "endings": unlocked_endings,
        "beaten": beaten_once,
        "tutorial": seen_tutorial
    })
    file.store_string(data)
    file.close()

func load_achievements() -> void:
    var file := FileAccess.open(ACH_SAVE_PATH, FileAccess.READ)
    if file == null:
        achievements = {}
        unlocked_endings = {}
        beaten_once = false
        return
    var parser := JSON.new()
    var err := parser.parse(file.get_as_text())
    file.close()
    if err != OK or not (parser.data is Dictionary):
        achievements = {}
        unlocked_endings = {}
        beaten_once = false
        return
    var parsed: Dictionary = parser.data
    if parsed.has("achievements"):
        var a = parsed.get("achievements", {})
        var e = parsed.get("endings", {})
        achievements = a if a is Dictionary else {}
        unlocked_endings = e if e is Dictionary else {}
        beaten_once = bool(parsed.get("beaten", false))
        seen_tutorial = bool(parsed.get("tutorial", false))
    else:
        # 旧格式：整份就是成就字典
        achievements = parsed
        unlocked_endings = {}
        beaten_once = false

func is_ach_unlocked(id: String) -> bool:
    return achievements.get(id, false)

# ============================================================
# 中途存档（继续游戏）
# 每回合结束自动存盘；结局达成或主动重开时清除
# ============================================================
func save_run() -> void:
    var file := FileAccess.open(RUN_SAVE_PATH, FileAccess.WRITE)
    if file == null:
        return
    var data := JSON.stringify({
        "sanity": sanity,
        "belief": belief,
        "public_opinion": public_opinion,
        "current_round": current_round,
        "battle_stage": battle_stage,
        "is_empty_shell": is_empty_shell,
        "keywords": keywords,
        "keyword_earned": keyword_earned,
        "keyword_used": keyword_used,
        "combo": combo,
        "best_combo": best_combo,
        "perfect_count": perfect_count,
        "backfire_count": backfire_count,
        "good_count": good_count,
        "weak_count": weak_count,
        "rounds_played": rounds_played,
        "scene_setup": scene_setup,
        "boss_lines": boss_lines,
        "boss_stances": boss_stances,
        "boss_options": boss_options,
        "quiz_data": quiz_data,
        "boss_post_quiz": boss_post_quiz,
        "boss_overrides": boss_overrides,
        "run_events": run_events,
        "quiz_correct": quiz_correct,
        "personality": personality,
        "run_goal": run_goal,
        "hard_mode": hard_mode
    })
    file.store_string(data)
    file.close()

func load_run() -> bool:
    var file := FileAccess.open(RUN_SAVE_PATH, FileAccess.READ)
    if file == null:
        return false
    var parser := JSON.new()
    var err := parser.parse(file.get_as_text())
    file.close()
    if err != OK or not (parser.data is Dictionary):
        return false
    var d: Dictionary = parser.data
    sanity = int(d.get("sanity", INIT_SANITY))
    belief = int(d.get("belief", INIT_BELIEF))
    public_opinion = int(d.get("public_opinion", INIT_PUBLIC))
    current_round = int(d.get("current_round", 1))
    battle_stage = int(d.get("battle_stage", Stage.OPENING))
    is_empty_shell = bool(d.get("is_empty_shell", false))
    keywords = d.get("keywords", [])
    keyword_earned = int(d.get("keyword_earned", 0))
    keyword_used = int(d.get("keyword_used", 0))
    combo = int(d.get("combo", 0))
    best_combo = int(d.get("best_combo", 0))
    perfect_count = int(d.get("perfect_count", 0))
    backfire_count = int(d.get("backfire_count", 0))
    good_count = int(d.get("good_count", 0))
    weak_count = int(d.get("weak_count", 0))
    rounds_played = int(d.get("rounds_played", 0))
    scene_setup = String(d.get("scene_setup", ""))
    boss_lines = d.get("boss_lines", {})
    boss_stances = d.get("boss_stances", {})
    boss_options = d.get("boss_options", {})
    quiz_data = d.get("quiz_data", {})
    boss_post_quiz = d.get("boss_post_quiz", {})
    boss_overrides = d.get("boss_overrides", {})
    run_events = d.get("run_events", {})
    quiz_correct = d.get("quiz_correct", {})
    personality = String(d.get("personality", "hot"))
    run_goal = String(d.get("run_goal", ""))
    hard_mode = bool(d.get("hard_mode", false))
    return true

func has_run_save() -> bool:
    return FileAccess.file_exists(RUN_SAVE_PATH)

func clear_run_save() -> void:
    if FileAccess.file_exists(RUN_SAVE_PATH):
        DirAccess.remove_absolute(RUN_SAVE_PATH)

# ---------- 结局图鉴 ----------
func unlock_ending(key: String) -> void:
    if key.is_empty():
        return
    unlocked_endings[key] = true
    beaten_once = true
    save_achievements()

func is_ending_unlocked(key: String) -> bool:
    return unlocked_endings.get(key, false)

func unlocked_ending_count() -> int:
    var n := 0
    for v in unlocked_endings.values():
        if v:
            n += 1
    return n
