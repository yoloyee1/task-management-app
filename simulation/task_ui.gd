extends Control

@onready var toggle_btn: Button = $VBoxContainer/ToggleBtn
@onready var task_list: ItemList = $VBoxContainer/TaskList
@onready var panel: Panel = $Panel

func _ready() -> void:
	toggle_btn.pressed.connect(_on_toggle_pressed)
	# 預設收起任務列表
	task_list.hide()
	panel.hide()
	toggle_btn.text = "Expand Tasks"

func _on_toggle_pressed() -> void:
	if task_list.visible:
		task_list.hide()
		panel.hide()
		toggle_btn.text = "Expand Tasks"
	else:
		task_list.show()
		panel.show()
		toggle_btn.text = "Collapse Tasks"
