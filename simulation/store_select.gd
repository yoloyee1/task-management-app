extends Control

@onready var grid: GridContainer = $VBoxContainer/GridContainer
@onready var title_label: Label = $VBoxContainer/TitleLabel

func _ready() -> void:
	var stores = _find_unique_stores()
	for store_id in stores:
		var btn = Button.new()
		var display_id = str(store_id.to_int() + 1) if store_id.is_valid_int() else store_id
		btn.text = "Store " + display_id
		btn.custom_minimum_size = Vector2(200, 80)
		btn.pressed.connect(_on_store_pressed.bind(str(store_id)))
		grid.add_child(btn)

func _find_unique_stores() -> Array:
	var stores: Array = []
	var file = FileAccess.open("res://sell data.csv", FileAccess.READ)
	if not file:
		return stores
	
	# Skip header
	file.get_csv_line()
	
	while not file.eof_reached():
		var row = file.get_csv_line()
		if row.size() < 4:
			continue
		var store = row[1]
		if not stores.has(store) and store != "store":
			stores.append(store)
	
	file.close()
	stores.sort()
	return stores

func _on_store_pressed(store_id: String) -> void:
	get_tree().change_scene_to_file("res://simulation/simulation_scene.tscn")
