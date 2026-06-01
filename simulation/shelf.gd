extends Control
class_name Shelf

@onready var color_rect: ColorRect = $ColorRect
@onready var product_label: Label = $VBoxContainer/ProductIDLabel
@onready var stock_label: Label = $VBoxContainer/StockLabel

## 純顯示元件：根據外部傳入的資料更新視覺
func display(p_id: String, stock: int, state: String, last_change: int = 0) -> void:
	if not is_node_ready():
		await ready
	
	product_label.text = "Product: " + str(p_id)
	
	if last_change < 0:
		stock_label.text = "Stock: " + str(stock) + "\n (" + str(last_change) + ")"
	elif last_change > 0:
		stock_label.text = "Stock: " + str(stock) + "\n (+" + str(last_change) + ")"
	else:
		stock_label.text = "Stock: " + str(stock)
	
	_apply_visuals(state)

func _apply_visuals(current_stock_state: String) -> void:
	match current_stock_state:
		"NORMAL":
			# 庫存充足，顯示原本顏色（白色）
			color_rect.color = Color.WHITE
		"WARNING":
			# 低於安全水位，顯示黃色
			color_rect.color = Color.YELLOW
		"EMPTY":
			# 缺貨，顯示紅色
			color_rect.color = Color.RED
