extends Node

# 全局字体：Noto Sans SC 取代 Godot 默认系统字体
# 必须是第一个 autoload（在 GlobalData 和 Audio 之前）
# 用 node_added 信号持续应用 theme，覆盖所有场景切换

var _theme: Theme = null

func _ready() -> void:
	var path: String = "res://assets/fonts/NotoSansSC-VF.ttf"
	if not FileAccess.file_exists(path):
		return
	var font: FontFile = load(path)
	if font == null:
		return

	_theme = Theme.new()
	_theme.default_font = font
	var cs: Array = ["Label", "Button", "LineEdit", "TextEdit", "RichTextLabel",
	                 "OptionButton", "CheckBox", "RadioButton", "TabContainer",
	                 "ProgressBar", "HSlider", "VSlider", "Popup", "Panel"]
	for c in cs:
		_theme.set_font("font", c, font)

	# 持续应用：任何节点加入树时，如果是 Control 就挂上 theme
	var tree: SceneTree = get_tree()
	if tree != null:
		tree.node_added.connect(_on_node_added)
		# 立刻对当前树里所有 Control 应用一次
		_recursive_apply(tree.root)

func _on_node_added(node: Node) -> void:
	if _theme == null:
		return
	if node is Control:
		node.theme = _theme

func _recursive_apply(node: Node) -> void:
	if _theme == null:
		return
	for child in node.get_children():
		if child is Control:
			child.theme = _theme
		_recursive_apply(child)
