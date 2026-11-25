extends Node

# ============================================================
# audio.gd — 全局音频（程序化合成，零外部素材、无版权风险）
# 所有音效与 BGM 在运行时用正弦/三角/噪声合成，首次生成后缓存到 user://
# 参数：RATE 采样率、POOL_SIZE 音效播放器数量（同时发声上限）
# ============================================================

const RATE := 22050
const POOL_SIZE := 6
const CFG_PATH := "user://audio.cfg"
const BGM_CACHE := "user://bgm_cache.wav"

var sfx_volume: float = 0.85
var bgm_volume: float = 0.45
var muted: bool = false

var _streams: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_idx: int = 0
var _bgm: AudioStreamPlayer = null
var _bgm_tried: bool = false

func _ready() -> void:
	# 无头模式跳过合成，避免拖慢回归测试
	var headless: bool = DisplayServer.get_name() == "headless"
	if not headless:
		_build_all_sfx()
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_bgm = AudioStreamPlayer.new()
	_bgm.bus = "Master"
	add_child(_bgm)
	_load_cfg()
	if not headless:
		call_deferred("_ensure_bgm")

func play_sfx(id: String, pitch_var: float = 0.0, pitch_scale: float = 1.0, volume_mul: float = 1.0) -> void:
	if muted or sfx_volume <= 0.01:
		return
	if not _streams.has(id) or _pool.is_empty():
		return
	var p: AudioStreamPlayer = _pool[_pool_idx]
	_pool_idx = (_pool_idx + 1) % _pool.size()
	p.stream = _streams[id]
	p.volume_db = linear_to_db(clampf(sfx_volume * clampf(volume_mul, 0.0, 1.0), 0.0, 1.0))
	p.pitch_scale = clampf(pitch_scale, 0.5, 2.0) * (1.0 + randf_range(-pitch_var, pitch_var))
	p.play()

func start_bgm() -> void:
	_ensure_bgm()

func is_bgm_playing() -> bool:
	return _bgm != null and _bgm.playing

func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	_save_cfg()

func set_bgm_volume(v: float) -> void:
	bgm_volume = clampf(v, 0.0, 1.0)
	_apply_bgm_volume()
	_save_cfg()

func set_muted(v: bool) -> void:
	muted = v
	_apply_bgm_volume()
	_save_cfg()

func _apply_bgm_volume() -> void:
	if _bgm == null:
		return
	if muted:
		_bgm.volume_db = -80.0
	else:
		_bgm.volume_db = linear_to_db(maxf(bgm_volume, 0.0001))

func _ensure_bgm() -> void:
	if _bgm_tried:
		return
	_bgm_tried = true
	if DisplayServer.get_name() == "headless":
		return
	var st: AudioStreamWAV = null
	if FileAccess.file_exists(BGM_CACHE):
		var f := FileAccess.open(BGM_CACHE, FileAccess.READ)
		if f != null:
			var buf := f.get_buffer(f.get_length())
			if buf.size() > 0:
				st = AudioStreamWAV.new()
				st.format = AudioStreamWAV.FORMAT_16_BITS
				st.mix_rate = RATE
				st.stereo = false
				st.data = buf
				st.loop_mode = AudioStreamWAV.LOOP_FORWARD
				st.loop_begin = 0
				st.loop_end = int(buf.size() / 2)
	if st == null:
		st = _build_bgm()
		st.save_to_wav(BGM_CACHE)
	_bgm.stream = st
	_apply_bgm_volume()
	_bgm.play()

# ------------------------------------------------------------
# BGM：8 秒 Am-F-C-G 循环 + 低频垫底 + 呼吸感
# 每个和弦首尾振幅为 0，循环接缝天然无缝，不会爆音
# ------------------------------------------------------------
func _build_bgm() -> AudioStreamWAV:
	var dur := 8.0
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var chords: Array = [
		[220.0, 261.63, 329.63],
		[174.61, 220.0, 261.63],
		[261.63, 329.63, 392.0],
		[196.0, 246.94, 293.66]
	]
	var chord_len: float = dur / 4.0
	for i in range(n):
		var t := float(i) / RATE
		var ci: int = int(t / chord_len) % chords.size()
		var local: float = fmod(t, chord_len)
		var env: float = clampf(local / 0.35, 0.0, 1.0) * clampf((chord_len - local) / 0.5, 0.0, 1.0)
		var s := 0.0
		var chord: Array = chords[ci]
		for k in range(chord.size()):
			var f: float = chord[k]
			s += sin(TAU * f * t) * 0.09
			s += sin(TAU * f * 2.0 * t) * 0.02
		s += sin(TAU * 55.0 * t) * 0.05
		s += sin(TAU * 110.0 * t) * 0.025
		var lfo: float = 0.85 + 0.15 * sin(TAU * 0.125 * t)
		buf[i] = s * env * lfo
	var st := _wav(buf)
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_begin = 0
	st.loop_end = n
	return st

# ------------------------------------------------------------
# 音效库
# ------------------------------------------------------------
func _build_all_sfx() -> void:
	_streams["click"] = _blip(880.0, 0.07, 0.35, 22.0)
	_streams["select"] = _seq([660.0, 990.0], 0.06, 0.30)
	_streams["open"] = _seq([440.0, 660.0], 0.07, 0.30)
	_streams["good"] = _seq([523.25, 659.25], 0.09, 0.38)
	_streams["perfect"] = _seq([659.25, 830.61, 1046.5], 0.085, 0.42, true)
	_streams["backfire"] = _fall(300.0, 120.0, 0.28, 0.50)
	_streams["wrong"] = _fall(360.0, 180.0, 0.22, 0.45)
	_streams["hit"] = _impact()
	_streams["win"] = _seq([523.25, 659.25, 783.99, 1046.5], 0.13, 0.40, true)
	_streams["lose"] = _seq([392.0, 329.63, 261.63], 0.20, 0.40)

func _blip(freq: float, dur: float, amp: float, decay: float = 6.0, tri: bool = false) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in range(n):
		var t := float(i) / RATE
		var env: float = exp(-decay * t) * clampf(t / 0.004, 0.0, 1.0)
		var v := 0.0
		if tri:
			v = asin(sin(TAU * freq * t)) * (2.0 / PI)
		else:
			v = sin(TAU * freq * t)
		buf[i] = v * env * amp
	return _wav(buf)

func _seq(freqs: Array, note_dur: float, amp: float, tri: bool = false) -> AudioStreamWAV:
	var total := int(RATE * note_dur * (freqs.size() + 0.6))
	var buf := PackedFloat32Array()
	buf.resize(total)
	for k in range(freqs.size()):
		var f: float = freqs[k]
		var start := int(RATE * note_dur * k)
		var n := int(RATE * note_dur * 1.4)
		for i in range(n):
			var idx := start + i
			if idx >= total:
				break
			var t := float(i) / RATE
			var env: float = exp(-5.0 * t) * clampf(t / 0.004, 0.0, 1.0)
			var v := 0.0
			if tri:
				v = asin(sin(TAU * f * t)) * (2.0 / PI)
			else:
				v = sin(TAU * f * t)
			buf[idx] += v * env * amp
	return _wav(buf)

func _fall(f0: float, f1: float, dur: float, amp: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var p: float = t / dur
		var f: float = lerpf(f0, f1, p)
		phase += TAU * f / RATE
		var env: float = exp(-3.0 * t) * clampf(t / 0.004, 0.0, 1.0)
		buf[i] = sin(phase) * env * amp
	return _wav(buf)

func _impact() -> AudioStreamWAV:
	var n := int(RATE * 0.22)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261022
	for i in range(n):
		var t := float(i) / RATE
		var env: float = exp(-16.0 * t)
		var noise: float = rng.randf_range(-1.0, 1.0)
		var body: float = sin(TAU * lerpf(120.0, 45.0, t / 0.22) * t)
		buf[i] = (noise * 0.35 + body * 0.8) * env * 0.75
	return _wav(buf)

func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var v: int = int(clampf(samples[i], -1.0, 1.0) * 32000.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s

# ------------------------------------------------------------
# 配置持久化
# ------------------------------------------------------------
func _load_cfg() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG_PATH) != OK:
		return
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	bgm_volume = clampf(float(cfg.get_value("audio", "bgm", bgm_volume)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", muted))
	_apply_bgm_volume()

func _save_cfg() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "bgm", bgm_volume)
	cfg.set_value("audio", "muted", muted)
	cfg.save(CFG_PATH)
