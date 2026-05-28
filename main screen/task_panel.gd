extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/TopHBox/TitleLabel
@onready var completed_checkbox: CheckBox = $MarginContainer/VBoxContainer/TopHBox/CompletedCheckBox
@onready var desc_label: Label = $MarginContainer/VBoxContainer/DescLabel
@onready var priority_label: Label = $MarginContainer/VBoxContainer/PriorityLabel
@onready var delete_button: Button = $"MarginContainer/VBoxContainer/delete button"

var _task: TaskData

func _ready() -> void:
	completed_checkbox.toggled.connect(_on_completed_toggled)
	delete_button.pressed.connect(_on_delete_pressed)

func set_task_data(task: TaskData) -> void:
	if not is_node_ready():
		await ready
	
	_task = task
	title_label.text = "Title: " + task.title
	
	if task.description.is_empty():
		desc_label.hide()
	else:
		desc_label.show()
		desc_label.text = "Description: " + task.description
		
	var priority_str = ["Low", "Normal", "High"][task.priority]
	priority_label.text = "Priority: " + priority_str
	
	# 更新 CheckBox 的狀態，但不觸發訊號以免觸發儲存邏輯
	completed_checkbox.set_pressed_no_signal(task.completed)
	
	_update_visuals()

func _on_completed_toggled(button_pressed: bool) -> void:
	if _task:
		_task.completed = button_pressed
		_update_visuals()
		
		# 將變更後的狀態儲存到資源檔案中
		var file_path = _task.resource_path
		if file_path and not file_path.is_empty():
			ResourceSaver.save(_task, file_path)

func _update_visuals() -> void:
	if _task and _task.completed:
		# 完成時將字體顏色變淡，可視為已完成的視覺回饋
		title_label.modulate = Color(0.5, 0.5, 0.5)
	else:
		# 未完成時恢復原本顏色
		title_label.modulate = Color(1, 1, 1)

func _on_delete_pressed() -> void:
	if not _task.completed:
		var dialog = AcceptDialog.new()
		dialog.title = "Warning"
		dialog.dialog_text = "Please mark the task as completed before deleting it."
		add_child(dialog)
		dialog.popup_centered()
		dialog.confirmed.connect(dialog.queue_free)
		return
		
	# 若已勾選完成，則刪除資源檔案
	var file_path = _task.resource_path
	if file_path and not file_path.is_empty():
		DirAccess.remove_absolute(file_path)
		
	# 從畫面中移除此節點
	queue_free()
