extends Control

## 管理兩個視圖（商店列表 / 商品詳情）之間的切換，
## 在商店總覽時顯示供應商方框、商店卡片（含狀態指示燈）、
## 以及進貨動畫（📦 從供應商飛向目標商店）。

@onready var sim_manager: SimulationManager = $SimulationManager
@onready var store_select_view: Control = $StoreSelectView
@onready var store_detail_view: Control = $StoreDetailView

# 商店總覽
@onready var overview_date_label: Label = $StoreSelectView/ContentVBox/DateLabel
@onready var time_scale_label: Label = $StoreSelectView/ContentVBox/TimeScaleBox/TimeScaleLabel
@onready var time_scale_slider: HSlider = $StoreSelectView/ContentVBox/TimeScaleBox/TimeScaleSlider
@onready var supplier_box: PanelContainer = $StoreSelectView/ContentVBox/SupplierBox
@onready var store_grid: GridContainer = $StoreSelectView/ContentVBox/StoreGridScroll/StoreGrid
@onready var global_task_list: ItemList = $StoreSelectView/ContentVBox/GlobalTaskUI/VBoxContainer/GlobalTaskList
@onready var animation_layer: Control = $StoreSelectView/AnimationLayer

# 商品詳情
@onready var back_button: Button = $StoreDetailView/TopBar/BackButton
@onready var day_label: Label = $StoreDetailView/TopBar/DayLabel
@onready var shelves_container: Control = $StoreDetailView/ShelvesContainer
@onready var task_item_list: ItemList = $StoreDetailView/TaskUI/VBoxContainer/TaskList
@onready var shipment_item_list: ItemList = $StoreDetailView/ShipmentUI/VBoxContainer/ShipmentList

# 手動任務派發UI
@onready var restock_grid: GridContainer = $StoreDetailView/ManualTaskUI/VBox/RestockSection/RestockGrid
@onready var command_input: LineEdit = $StoreDetailView/ManualTaskUI/VBox/CommandSection/CommandInput
@onready var command_submit: Button = $StoreDetailView/ManualTaskUI/VBox/CommandSection/CommandSubmit

var current_view_store: String = "" # 當前正在查看的商店 ID（空 = 商店列表）

# store_id -> StoreCard node 的對照表
var store_card_map: Dictionary = {}

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	sim_manager.tick_completed.connect(_on_tick_completed)
	sim_manager.delivery_queued.connect(_on_delivery_queued)
	time_scale_slider.value_changed.connect(_on_time_scale_changed)
	command_submit.pressed.connect(_on_command_submit_pressed)
	command_input.text_submitted.connect(func(_t): _on_command_submit_pressed())
	
	_setup_store_cards()
	
	# 預設顯示商店列表
	store_select_view.show()
	store_detail_view.hide()

func _setup_store_cards() -> void:
	var card_nodes = store_grid.get_children()
	for i in range(card_nodes.size()):
		var card = card_nodes[i] as PanelContainer
		if i < sim_manager.store_ids.size():
			var store_id = sim_manager.store_ids[i]
			var display_id = str(store_id.to_int() + 1) if store_id.is_valid_int() else store_id
			
			# 更新卡片名稱
			var name_label = card.get_node("VBox/NameLabel") as Label
			name_label.text = "🏪 Store " + display_id
			
			# 記錄對照
			store_card_map[store_id] = card
			
			# 綁定點擊（使用 gui_input 因為 PanelContainer 沒有 pressed 信號）
			card.gui_input.connect(_on_card_gui_input.bind(store_id))
			card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			card.show()
			
			# 在 ProductGrid 的每個進度條前面插入阿拉伯數字標籤
			var grid = card.get_node_or_null("VBox/ProductGrid")
			if grid:
				var progs = grid.get_children()  # 取得目前的 Prog_0 ~ Prog_9
				for p in range(progs.size()):
					var lbl = Label.new()
					lbl.text = str(p + 1)
					lbl.add_theme_font_size_override("font_size", 10)
					lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					lbl.custom_minimum_size = Vector2(14, 0)
					grid.add_child(lbl)
					# 把標籤移到對應進度條前面: 目標索引 = p * 2
					grid.move_child(lbl, p * 2)
		else:
			card.hide()

func _on_card_gui_input(event: InputEvent, store_id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_store_pressed(store_id)

func _on_store_pressed(store_id: String) -> void:
	current_view_store = store_id
	store_select_view.hide()
	store_detail_view.show()
	_build_restock_buttons(store_id)
	_refresh_detail_view()

func _on_back_pressed() -> void:
	current_view_store = ""
	store_detail_view.hide()
	store_select_view.show()

func _on_time_scale_changed(value: float) -> void:
	time_scale_label.text = "Timer Speed: %.1fx" % value
	var base_time = 3.0 # 對應 1.0x 的基準時間
	var new_wait_time = base_time / value
	sim_manager.timer.wait_time = new_wait_time
	# 如果當前剩餘時間大於新的目標時間，直接重啟計時器讓它立刻加速
	if sim_manager.timer.time_left > new_wait_time:
		sim_manager.timer.start(new_wait_time)

func _on_tick_completed() -> void:
	# 更新總覽頁面的日期
	overview_date_label.text = "📅 Date: " + sim_manager.get_current_date()
	
	# 更新每個商店卡片的狀態指示燈
	_update_store_indicators()
	
	# 更新全局任務列表
	_update_global_task_list()

	# 如果正在查看某商店，即時更新畫面
	if current_view_store != "":
		_refresh_detail_view()

func _update_store_indicators() -> void:
	var tick_duration = sim_manager.timer.wait_time
	
	for store_id in store_card_map:
		var card = store_card_map[store_id] as PanelContainer
		var indicator = card.get_node("VBox/StatusIndicator") as ColorRect
		var worst = _get_store_worst_state(store_id)
		
		# 漸變指示燈顏色
		var target_color: Color
		match worst:
			"NORMAL":
				target_color = Color(0.2, 0.8, 0.2, 1)
			"WARNING":
				target_color = Color(0.9, 0.8, 0.1, 1)
			"EMPTY":
				target_color = Color(0.9, 0.2, 0.2, 1)
			_:
				target_color = Color(0.2, 0.8, 0.2, 1)
		
		if indicator.color != target_color:
			var color_tween = create_tween()
			color_tween.tween_property(indicator, "color", target_color, tick_duration * 0.25)

		# 更新進度條（漸變）
		var state = sim_manager.get_store_state(store_id)
		if state.is_empty() or not state.has("products"):
			continue
		
		var product_ids = sim_manager.get_store_products_sorted(store_id)
		var grid = card.get_node_or_null("VBox/ProductGrid")
		if grid:
			# 只取 ProgressBar 節點（跳過數字標籤）
			var progs: Array = []
			for child in grid.get_children():
				if child is ProgressBar:
					progs.append(child)
			
			for i in range(progs.size()):
				var prog = progs[i] as ProgressBar
				# 數字標籤在前一個 sibling
				var lbl_idx = prog.get_index() - 1
				var lbl = grid.get_child(lbl_idx) if lbl_idx >= 0 else null
				
				if i < product_ids.size():
					var prod_id = product_ids[i]
					var prod_data = state["products"][prod_id]
					var target_value = float(prod_data["stock"])
					
					# 漸變進度條數值
					if abs(prog.value - target_value) > 0.5:
						var val_tween = create_tween()
						val_tween.set_ease(Tween.EASE_OUT)
						val_tween.set_trans(Tween.TRANS_CUBIC)
						val_tween.tween_property(prog, "value", target_value, tick_duration * 0.5)
					
					# 漸變進度條顏色
					var prod_state = prod_data["state"]
					var target_mod: Color
					if prod_state == "EMPTY":
						target_mod = Color(0.9, 0.2, 0.2, 1)
					elif prod_state == "WARNING":
						target_mod = Color(0.9, 0.8, 0.1, 1)
					else:
						target_mod = Color(0.2, 0.8, 0.2, 1)
					
					if prog.modulate != target_mod:
						var mod_tween = create_tween()
						mod_tween.tween_property(prog, "modulate", target_mod, tick_duration * 0.25)
						
					prog.show()
					if lbl:
						lbl.show()
				else:
					prog.hide()
					if lbl:
						lbl.hide()

func _get_store_worst_state(store_id: String) -> String:
	var state = sim_manager.get_store_state(store_id)
	if state.is_empty() or not state.has("products"):
		return "NORMAL"
	
	var worst = "NORMAL"
	for prod_id in state["products"]:
		var prod_state = state["products"][prod_id]["state"]
		if prod_state == "EMPTY":
			return "EMPTY" # 最差，直接回傳
		elif prod_state == "WARNING":
			worst = "WARNING"
	return worst

func _update_global_task_list() -> void:
	global_task_list.clear()
	for store_id in sim_manager.store_ids:
		var state = sim_manager.get_store_state(store_id)
		if state.has("tasks") and state["tasks"].size() > 0:
			var display_id = str(store_id.to_int() + 1) if store_id.is_valid_int() else store_id
			for task in state["tasks"]:
				global_task_list.add_item("Store " + display_id + " - " + task["text"])

func _on_delivery_queued(store_id: String, product_id: String) -> void:
	# 只在商店總覽頁面顯示動畫
	if not store_select_view.visible:
		return
	
	if not store_card_map.has(store_id):
		return
	
	# 等一幀讓佈局完成
	await get_tree().process_frame
	
	var target_card = store_card_map[store_id] as PanelContainer
	
	# 計算起點（供應商方框的中心，轉到 AnimationLayer 的座標）
	var supplier_center = supplier_box.global_position + supplier_box.size * 0.5
	var start_pos = supplier_center - animation_layer.global_position
	
	# 計算終點（目標商店卡片的中心）
	var card_center = target_card.global_position + target_card.size * 0.5
	var end_pos = card_center - animation_layer.global_position
	
	# 建立飛行的 📦 圖示
	var icon = Label.new()
	icon.text = "📦"
	icon.add_theme_font_size_override("font_size", 28)
	icon.position = start_pos - Vector2(14, 14) # 偏移讓圖示居中
	animation_layer.add_child(icon)
	
	var tick_time = sim_manager.timer.wait_time
	var fade_time = minf(tick_time * 0.15, 0.3)
	var fly_time = tick_time - fade_time
	
	# 用 Tween 做動畫（飛行時間恰好等於一個 tick，貨物抵達時庫存才增加）
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(icon, "position", end_pos - Vector2(14, 14), fly_time)
	
	# 到達後立即淡出消失
	tween.tween_property(icon, "modulate:a", 0.0, fade_time)
	tween.tween_callback(icon.queue_free)

# ===== 商店詳情頁 =====

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

# ===== 手動任務派發 =====

func _build_restock_buttons(store_id: String) -> void:
	# 清空舊按鈕
	for child in restock_grid.get_children():
		child.queue_free()
	
	var product_ids = sim_manager.get_store_products_sorted(store_id)
	for prod_id in product_ids:
		var btn = Button.new()
		btn.text = "⚡ " + prod_id
		btn.tooltip_text = "Request early restock for Product " + prod_id
		btn.pressed.connect(_on_restock_pressed.bind(store_id, prod_id, btn))
		restock_grid.add_child(btn)

func _on_restock_pressed(store_id: String, prod_id: String, btn: Button) -> void:
	var success = sim_manager.request_early_restock(store_id, prod_id)
	if success:
		btn.text = "✅ " + prod_id
		btn.disabled = true
		# 刷新任務與進貨清單
		_refresh_detail_view()
	else:
		# 已有待進貨訂單 — 閃爍提示
		btn.text = "⚠️ " + prod_id
		await get_tree().create_timer(1.0).timeout
		btn.text = "⚡ " + prod_id

func _on_command_submit_pressed() -> void:
	var text = command_input.text.strip_edges()
	if text.is_empty() or current_view_store.is_empty():
		return
	sim_manager.add_custom_task(current_view_store, text)
	command_input.clear()
	# 即時刷新任務列表
	_refresh_detail_view()
