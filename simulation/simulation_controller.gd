extends Node
class_name SimulationController

signal simulation_started
signal simulation_ended

@onready var timer: Timer = $Timer
@onready var shelves_container: Control = $"../ShelvesContainer"
@onready var task_item_list: ItemList = $"../CanvasLayer/TaskUI/VBoxContainer/TaskList"
@onready var shipment_item_list: ItemList = $"../CanvasLayer/ShipmentUI/VBoxContainer/ShipmentList"
@onready var day_label: Label = $"../CanvasLayer/TopUI/DayLabel"
@onready var back_button: Button = $"../CanvasLayer/TopUI/BackButton"

var target_store_id: String = "0"

var sales_data: Dictionary = {} # date -> { product_id: number_sold }
var dates: Array = []
var current_date_index: int = 0

var active_shelves: Dictionary = {} # product_id -> Shelf instance

# 待到貨的進貨排程：Array of { "product_id": String, "amount": int, "arrival_index": int }
var pending_deliveries: Array = []

func _ready() -> void:
	target_store_id = GlobalData.selected_store_id
	timer.timeout.connect(_on_timer_timeout)
	back_button.pressed.connect(_on_back_pressed)
	_load_csv_data()
	
	if dates.size() > 0:
		_setup_shelves()
		timer.start(1.0)
		simulation_started.emit()
	else:
		var display_id = str(target_store_id.to_int() + 1) if target_store_id.is_valid_int() else target_store_id
		day_label.text = "No data found for Store " + display_id

func _load_csv_data() -> void:
	var file = FileAccess.open("res://sell data.csv", FileAccess.READ)
	if not file:
		print("Failed to open sell data.csv")
		return
		
	# Skip header
	var header = file.get_csv_line()
	
	while not file.eof_reached():
		var row = file.get_csv_line()
		if row.size() < 4:
			continue
			
		var date_str = row[0]
		var store = row[1]
		var product = row[2]
		var number_sold = row[3].to_int()
		
		# Filter for selected store
		if store == target_store_id:
			if not sales_data.has(date_str):
				sales_data[date_str] = {}
				dates.append(date_str)
			
			sales_data[date_str][product] = number_sold
	
	file.close()
	dates.sort()

func _setup_shelves() -> void:
	# 找出 store 1 的所有不重複商品 ID
	var unique_products: Array = []
	for date in dates:
		for prod in sales_data[date]:
			if not unique_products.has(prod):
				unique_products.append(prod)
	unique_products.sort()
	
	# 取得場景中已預放的 Shelf 節點並與商品 ID 配對
	var shelf_nodes = shelves_container.get_children()
	var initial_stock = 10000
	var safe_stock = 2000
	
	for i in range(mini(unique_products.size(), shelf_nodes.size())):
		var prod_id = unique_products[i]
		var shelf: Shelf = shelf_nodes[i] as Shelf
		shelf.initialize(prod_id, initial_stock, safe_stock)
		shelf.restock_requested.connect(_on_shelf_restock_requested)
		active_shelves[prod_id] = shelf
	
	# 隱藏多餘的貨架節點（如果有的話）
	for i in range(unique_products.size(), shelf_nodes.size()):
		shelf_nodes[i].hide()

func _on_timer_timeout() -> void:
	if current_date_index >= dates.size():
		timer.stop()
		simulation_ended.emit()
		print("Simulation Ended")
		return
	
	# 1. 先處理到貨的進貨
	_process_deliveries()
		
	# 2. 再處理當天的銷售扣庫存
	var current_date = dates[current_date_index]
	var display_id = str(target_store_id.to_int() + 1) if target_store_id.is_valid_int() else target_store_id
	day_label.text = "Store " + display_id + " | Date: " + current_date
	
	var day_sales = sales_data[current_date]
	for prod_id in day_sales.keys():
		var sold = day_sales[prod_id]
		if active_shelves.has(prod_id):
			active_shelves[prod_id].update_stock(sold)
			
	current_date_index += 1

func _process_deliveries() -> void:
	var delivered = []
	for i in range(pending_deliveries.size() - 1, -1, -1):
		var delivery = pending_deliveries[i]
		if delivery["arrival_index"] <= current_date_index:
			# 到貨！補貨到對應的貨架
			var prod_id = delivery["product_id"]
			if active_shelves.has(prod_id):
				active_shelves[prod_id].restock(delivery["amount"])
			delivered.append(i)
	
	# 移除已到貨的項目（從後往前移除避免索引錯位）
	for i in delivered:
		pending_deliveries.remove_at(i)
	
	# 更新進貨 UI
	_refresh_shipment_ui()

func _on_shelf_restock_requested(product_id: String) -> void:
	# 檢查是否已經有該商品的待進貨訂單
	for delivery in pending_deliveries:
		if delivery["product_id"] == product_id:
			return
			
	var restock_amount = 10000
	var arrival_index = current_date_index + 1
	
	pending_deliveries.append({
		"product_id": product_id,
		"amount": restock_amount,
		"arrival_index": arrival_index
	})
	
	# 在任務列表中顯示
	var shelf = active_shelves[product_id]
	var arrival_date = dates[mini(arrival_index, dates.size() - 1)]
	var task_text = "Ordered: Product " + product_id + " (Stock: " + str(shelf.stock) + ") → Arrives " + arrival_date
	var idx = task_item_list.get_item_count()
	task_item_list.add_item(task_text)
	task_item_list.set_item_metadata(idx, product_id)
	
	# 更新進貨 UI
	_refresh_shipment_ui()

func _refresh_shipment_ui() -> void:
	shipment_item_list.clear()
	for delivery in pending_deliveries:
		var prod_id = delivery["product_id"]
		var amount = delivery["amount"]
		var arrival_date = dates[mini(delivery["arrival_index"], dates.size() - 1)]
		var text = "📦 Product " + prod_id + " +" + str(amount) + " → " + arrival_date
		shipment_item_list.add_item(text)
	
	# 如果沒有待進貨項目也不用移除
	if pending_deliveries.size() == 0:
		# 同時清除任務列表中的已完成項目
		_clean_completed_tasks()

func _clean_completed_tasks() -> void:
	# 移除任務列表中已經不在待進貨佇列中的項目
	for i in range(task_item_list.get_item_count() - 1, -1, -1):
		var prod_id = task_item_list.get_item_metadata(i)
		var found = false
		for delivery in pending_deliveries:
			if delivery["product_id"] == prod_id:
				found = true
				break
		if not found:
			task_item_list.remove_item(i)

func _on_back_pressed() -> void:
	timer.stop()
	get_tree().change_scene_to_file("res://simulation/store_select.tscn")
