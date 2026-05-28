extends Control

## 管理兩個視圖（商店列表 / 商品詳情）之間的切換，
## 並在查看某商店時即時更新該商店的視覺資料。

@onready var sim_manager: SimulationManager = $SimulationManager
@onready var store_select_view: Control = $StoreSelectView
@onready var store_detail_view: Control = $StoreDetailView

# 商店列表
@onready var store_grid: GridContainer = $StoreSelectView/VBoxContainer/ScrollContainer/GridContainer
@onready var global_task_list: ItemList = $StoreSelectView/GlobalTaskUI/VBoxContainer/GlobalTaskList

# 商品詳情
@onready var back_button: Button = $StoreDetailView/TopBar/BackButton
@onready var day_label: Label = $StoreDetailView/TopBar/DayLabel
@onready var shelves_container: Control = $StoreDetailView/ShelvesContainer
@onready var task_item_list: ItemList = $StoreDetailView/TaskUI/VBoxContainer/TaskList
@onready var shipment_item_list: ItemList = $StoreDetailView/ShipmentUI/VBoxContainer/ShipmentList

var current_view_store: String = ""  # 當前正在查看的商店 ID（空 = 商店列表）

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	sim_manager.tick_completed.connect(_on_tick_completed)
	
	# 等 SimulationManager 載入完 CSV 後再建立按鈕
	_build_store_buttons()
	
	# 預設顯示商店列表
	store_select_view.show()
	store_detail_view.hide()

func _build_store_buttons() -> void:
	var btn_nodes = store_grid.get_children()
	for i in range(btn_nodes.size()):
		var btn = btn_nodes[i] as Button
		if i < sim_manager.store_ids.size():
			var store_id = sim_manager.store_ids[i]
			var display_id = str(store_id.to_int() + 1) if store_id.is_valid_int() else store_id
			btn.text = "Store " + display_id
			if not btn.pressed.is_connected(_on_store_pressed):
				btn.pressed.connect(_on_store_pressed.bind(store_id))
			btn.show()
		else:
			btn.hide()

func _on_store_pressed(store_id: String) -> void:
	current_view_store = store_id
	store_select_view.hide()
	store_detail_view.show()
	_refresh_detail_view()

func _on_back_pressed() -> void:
	current_view_store = ""
	store_detail_view.hide()
	store_select_view.show()

func _on_tick_completed() -> void:
	# 更新全局任務列表
	if is_instance_valid(global_task_list):
		global_task_list.clear()
		for store_id in sim_manager.store_ids:
			var state = sim_manager.get_store_state(store_id)
			if state.has("tasks") and state["tasks"].size() > 0:
				var display_id = str(store_id.to_int() + 1) if store_id.is_valid_int() else store_id
				for task in state["tasks"]:
					global_task_list.add_item("Store " + display_id + " - " + task["text"])

	# 如果正在查看某商店，即時更新畫面
	if current_view_store != "":
		_refresh_detail_view()

func _refresh_detail_view() -> void:
	var store_id = current_view_store
	var state = sim_manager.get_store_state(store_id)
	if state.is_empty():
		return
	
	# 更新日期標籤
	var display_id = str(store_id.to_int() + 1) if store_id.is_valid_int() else store_id
	day_label.text = "Store " + display_id + " | Date: " + sim_manager.get_current_date()
	
	# 更新貨架顯示
	var product_ids = sim_manager.get_store_products_sorted(store_id)
	var shelf_nodes = shelves_container.get_children()
	
	for i in range(shelf_nodes.size()):
		if i < product_ids.size():
			var prod_id = product_ids[i]
			var prod = state["products"][prod_id]
			shelf_nodes[i].show()
			shelf_nodes[i].display(prod_id, prod["stock"], prod["state"], prod["last_change"])
		else:
			shelf_nodes[i].hide()
	
	# 更新任務列表
	task_item_list.clear()
	for task in state["tasks"]:
		task_item_list.add_item(task["text"])
	
	# 更新進貨列表
	shipment_item_list.clear()
	for delivery in state["deliveries"]:
		var arrival_date = sim_manager.all_dates[mini(delivery["arrival_index"], sim_manager.all_dates.size() - 1)]
		var text = "📦 Product " + delivery["product_id"] + " +" + str(delivery["amount"]) + " → " + arrival_date
		shipment_item_list.add_item(text)
