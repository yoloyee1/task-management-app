extends Node
class_name SimulationManager

## 所有商店的模擬同時在背景運行。
## UI 層可以查詢任意商店的即時狀態來顯示。

signal tick_completed  # 每次時間推進後發出
signal delivery_queued(store_id: String, product_id: String)  # 當新進貨訂單產生時發出

@onready var timer: Timer = $Timer

# 全域日期管理
var all_dates: Array = []
var current_date_index: int = 0

# CSV 原始資料：{ store_id: { date: { product_id: number_sold } } }
var all_sales_data: Dictionary = {}

# 所有商店 ID（排序後）
var store_ids: Array = []

# 每家商店的模擬狀態
# { store_id: { "products": {}, "deliveries": [], "tasks": [] } }
var store_states: Dictionary = {}

const INITIAL_STOCK = 10000
const SAFE_STOCK = 2000
const RESTOCK_AMOUNT = 10000

func _ready() -> void:
	timer.timeout.connect(_on_timer_timeout)
	_load_csv_data()
	_init_all_stores()
	if all_dates.size() > 0:
		timer.start(3.0)

func get_current_date() -> String:
	if current_date_index < all_dates.size():
		return all_dates[current_date_index]
	return "Simulation Ended"

func get_store_state(store_id: String) -> Dictionary:
	if store_states.has(store_id):
		return store_states[store_id]
	return {}

func get_store_products_sorted(store_id: String) -> Array:
	if not store_states.has(store_id):
		return []
	var keys = store_states[store_id]["products"].keys()
	keys.sort()
	return keys

func _load_csv_data() -> void:
	var file = FileAccess.open("res://sell data.csv", FileAccess.READ)
	if not file:
		print("Failed to open sell data.csv")
		return
	
	var header = file.get_csv_line()
	var date_set: Dictionary = {}
	
	while not file.eof_reached():
		var row = file.get_csv_line()
		if row.size() < 4:
			continue
		
		var date_str = row[0]
		var store = row[1]
		var product = row[2]
		var number_sold = row[3].to_int()
		
		# 收集所有商店
		if not all_sales_data.has(store):
			all_sales_data[store] = {}
			store_ids.append(store)
		
		if not all_sales_data[store].has(date_str):
			all_sales_data[store][date_str] = {}
		
		all_sales_data[store][date_str][product] = number_sold
		
		if not date_set.has(date_str):
			date_set[date_str] = true
	
	file.close()
	
	all_dates = date_set.keys()
	all_dates.sort()
	store_ids.sort()

func _init_all_stores() -> void:
	for store_id in store_ids:
		# 找出該商店所有不重複的商品 ID
		var products: Dictionary = {}
		for date in all_dates:
			if all_sales_data[store_id].has(date):
				for prod_id in all_sales_data[store_id][date]:
					if not products.has(prod_id):
						products[prod_id] = {
							"stock": INITIAL_STOCK,
							"safe_stock": SAFE_STOCK,
							"state": "NORMAL",
							"last_change": 0
						}
		
		store_states[store_id] = {
			"products": products,
			"deliveries": [],
			"tasks": []
		}

func _on_timer_timeout() -> void:
	if current_date_index >= all_dates.size():
		timer.stop()
		return
	
	# 同時推進所有商店的模擬
	for store_id in store_ids:
		_process_store_tick(store_id)
	
	current_date_index += 1
	tick_completed.emit()

func _process_store_tick(store_id: String) -> void:
	var state = store_states[store_id]
	
	# 1. 處理到貨的進貨
	_process_deliveries(store_id, state)
	
	# 2. 處理當天的銷售扣庫存
	var current_date = all_dates[current_date_index]
	if all_sales_data[store_id].has(current_date):
		var day_sales = all_sales_data[store_id][current_date]
		for prod_id in day_sales:
			if state["products"].has(prod_id):
				var sold = day_sales[prod_id]
				var prod = state["products"][prod_id]
				prod["stock"] -= sold
				if prod["stock"] < 0:
					prod["stock"] = 0
				prod["last_change"] = -sold
	
	# 3. 評估所有商品狀態並觸發自動補貨
	for prod_id in state["products"]:
		var prod = state["products"][prod_id]
		_evaluate_product_state(store_id, prod_id, prod, state)

func _process_deliveries(store_id: String, state: Dictionary) -> void:
	var delivered: Array = []
	for i in range(state["deliveries"].size() - 1, -1, -1):
		var delivery = state["deliveries"][i]
		if delivery["arrival_index"] <= current_date_index:
			var prod_id = delivery["product_id"]
			if state["products"].has(prod_id):
				var prod = state["products"][prod_id]
				prod["stock"] += delivery["amount"]
				prod["last_change"] = delivery["amount"]
			delivered.append(i)
	
	# 移除已到貨的（從後往前）
	for i in delivered:
		state["deliveries"].remove_at(i)
	
	# 清除已完成的任務
	if delivered.size() > 0:
		_clean_tasks(state)

func _evaluate_product_state(store_id: String, prod_id: String, prod: Dictionary, state: Dictionary) -> void:
	# 更新狀態
	if prod["stock"] <= 0:
		prod["state"] = "EMPTY"
	elif prod["stock"] <= prod["safe_stock"]:
		prod["state"] = "WARNING"
	else:
		prod["state"] = "NORMAL"
	
	# WARNING 或 EMPTY 時自動觸發補貨（如果沒有待進貨訂單）
	match prod["state"]:
		"WARNING", "EMPTY":
			if not _has_pending_delivery(state, prod_id):
				_queue_delivery(store_id, prod_id, state)
		"NORMAL":
			pass

func _has_pending_delivery(state: Dictionary, prod_id: String) -> bool:
	for delivery in state["deliveries"]:
		if delivery["product_id"] == prod_id:
			return true
	return false

func _queue_delivery(store_id: String, prod_id: String, state: Dictionary) -> void:
	var arrival_index = current_date_index + 1
	state["deliveries"].append({
		"product_id": prod_id,
		"amount": RESTOCK_AMOUNT,
		"arrival_index": arrival_index
	})
	
	var arrival_date = all_dates[mini(arrival_index, all_dates.size() - 1)]
	var prod = state["products"][prod_id]
	state["tasks"].append({
		"product_id": prod_id,
		"text": "Ordered: Product " + prod_id + " (Stock: " + str(prod["stock"]) + ") → Arrives " + arrival_date
	})
	delivery_queued.emit(store_id, prod_id)

func _clean_tasks(state: Dictionary) -> void:
	var new_tasks: Array = []
	for task in state["tasks"]:
		var still_pending = false
		for delivery in state["deliveries"]:
			if delivery["product_id"] == task["product_id"]:
				still_pending = true
				break
		if still_pending:
			new_tasks.append(task)
	state["tasks"] = new_tasks
