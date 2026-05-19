extends Control

const TASK_PANEL_SCENE = preload("res://main screen/task_panel.tscn")

# UI 參照
@onready var add_new_task_btn: Button = $VBoxContainer/HBoxContainer/Button
@onready var task_form_container: VBoxContainer = $"VBoxContainer/HBoxContainer/adding new task"
@onready var existing_task_placeholder: Control = $"VBoxContainer/existing task"

# 靜態 UI 參照（這些現在從場景中取得）
@onready var toggle_form_btn: Button = $"VBoxContainer/HBoxContainer/adding new task/ToggleFormButton"
@onready var form_vbox: VBoxContainer = $"VBoxContainer/HBoxContainer/adding new task/FormVBox"
@onready var title_input: LineEdit = $"VBoxContainer/HBoxContainer/adding new task/FormVBox/TitleLineEdit"
@onready var desc_input: LineEdit = $"VBoxContainer/HBoxContainer/adding new task/FormVBox/DescLineEdit"
@onready var priority_input: OptionButton = $"VBoxContainer/HBoxContainer/adding new task/FormVBox/PriorityOptionButton"

# 任務列表
var task_list_container: VBoxContainer
var created_tasks: Array[TaskData] = []

func _ready() -> void:
	# 連接切換表單顯示的按鈕
	toggle_form_btn.pressed.connect(_on_toggle_form_pressed)
	
	# 連接 Add New Task 按鈕
	add_new_task_btn.pressed.connect(_on_add_new_task_pressed)
	
	# 建立捲動容器來顯示任務
	_setup_task_list()

func _setup_task_list() -> void:
	# 建立一個捲動容器來放置現有的任務
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	existing_task_placeholder.add_child(scroll)
	
	task_list_container = VBoxContainer.new()
	task_list_container.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(task_list_container)
	
	# 載入現有的任務資源
	_load_existing_tasks()

func _load_existing_tasks() -> void:
	var dir = DirAccess.open("user://")
	if dir and dir.dir_exists("tasks"):
		var tasks_dir = DirAccess.open("user://tasks")
		if tasks_dir:
			tasks_dir.list_dir_begin()
			var file_name = tasks_dir.get_next()
			while file_name != "":
				if not tasks_dir.current_is_dir() and file_name.ends_with(".tres"):
					var task_res = ResourceLoader.load("user://tasks/" + file_name) as TaskData
					if task_res:
						created_tasks.append(task_res)
						_add_task_to_ui(task_res)
				file_name = tasks_dir.get_next()
		
		# 載入完畢後排序
		_sort_task_list()

func _sort_task_list() -> void:
	var children = task_list_container.get_children()
	# 使用自訂排序，優先級數值越大的排在越上面
	children.sort_custom(func(a, b):
		return a._task.priority > b._task.priority
	)
	
	# 根據排序結果重新排列節點
	for i in range(children.size()):
		task_list_container.move_child(children[i], i)

func _on_toggle_form_pressed() -> void:
	# 切換表單顯示狀態
	form_vbox.visible = !form_vbox.visible

func _on_add_new_task_pressed() -> void:
	# 如果表單尚未展開，點擊時先展開表單
	if not form_vbox.visible:
		form_vbox.show()
		return
		
	# 檢查標題是否為空
	if title_input.text.is_empty():
		return
		
	# 根據自訂變數建立 Task 資源
	var new_task = TaskData.new()
	new_task.title = title_input.text
	new_task.description = desc_input.text
	new_task.priority = priority_input.selected
	
	# 將任務資源儲存為檔案
	var dir = DirAccess.open("user://")
	if not dir.dir_exists("tasks"):
		dir.make_dir("tasks")
		
	var timestamp = Time.get_unix_time_from_system()
	var file_path = "user://tasks/task_" + str(timestamp) + ".tres"
	
	# 先指派資源路徑，這樣 task_panel 在存檔時才知道存去哪裡
	new_task.take_over_path(file_path)
	var err = ResourceSaver.save(new_task, file_path)
	if err != OK:
		print("Failed to save task resource")
	
	# 加入列表（現在是在存檔且有了 resource_path 之後呼叫）
	created_tasks.append(new_task)
	_add_task_to_ui(new_task)
	_sort_task_list()
	
	# 清空輸入
	title_input.text = ""
	desc_input.text = ""
	priority_input.select(1)
	
	# 新增後隱藏表單
	form_vbox.hide()

func _add_task_to_ui(task: TaskData) -> void:
	var panel = TASK_PANEL_SCENE.instantiate()
	task_list_container.add_child(panel)
	panel.set_task_data(task)
