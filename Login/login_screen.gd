extends Control

@onready var login_panel: PanelContainer = $CenterContainer/LoginPanel
@onready var register_panel: PanelContainer = $CenterContainer/RegisterPanel

# Login inputs
@onready var account_line_edit: LineEdit = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/InputVBox/AccountVBox/AccountLineEdit
@onready var password_line_edit: LineEdit = $CenterContainer/LoginPanel/MarginContainer/VBoxContainer/InputVBox/PasswordVBox/PasswordLineEdit

# Register inputs
@onready var reg_account_line_edit: LineEdit = $CenterContainer/RegisterPanel/MarginContainer/VBoxContainer/InputVBox/AccountVBox/RegAccountLineEdit
@onready var reg_password_line_edit: LineEdit = $CenterContainer/RegisterPanel/MarginContainer/VBoxContainer/InputVBox/PasswordVBox/RegPasswordLineEdit
@onready var confirm_password_line_edit: LineEdit = $CenterContainer/RegisterPanel/MarginContainer/VBoxContainer/InputVBox/ConfirmPasswordVBox/ConfirmPasswordLineEdit

@export var main_screen: PackedScene

const CONFIG_PATH = "user://accounts.cfg"

func _ready() -> void:
	login_panel.show()
	register_panel.hide()

func _show_message(title: String, text: String) -> void:
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = text
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(dialog.queue_free)

func _on_login_button_pressed() -> void:
	var account = account_line_edit.text
	var password = password_line_edit.text
	
	if account.is_empty() or password.is_empty():
		_show_message("Login Failed", "Account or password cannot be empty")
		return
		
	var config = ConfigFile.new()
	var err = config.load(CONFIG_PATH)
	
	if err == OK:
		if config.has_section_key("accounts", account):
			var saved_password = config.get_value("accounts", account)
			if saved_password == password:
				# Password correct, login successful
				if main_screen:
					get_tree().change_scene_to_packed(main_screen)
				else:
					_show_message("Login Successful", "Login successful, but main_screen is not set in Inspector.")
				return
				
	# Account not found or incorrect password
	_show_message("Login Failed", "Invalid account or password")

func _on_register_button_pressed() -> void:
	var account = reg_account_line_edit.text
	var password = reg_password_line_edit.text
	var confirm_password = confirm_password_line_edit.text
	
	if account.is_empty() or password.is_empty():
		_show_message("Registration Failed", "Account or password cannot be empty")
		return
		
	if password != confirm_password:
		_show_message("Registration Failed", "Passwords do not match")
		return
		
	var config = ConfigFile.new()
	config.load(CONFIG_PATH)
	
	if config.has_section_key("accounts", account):
		_show_message("Registration Failed", "Account already exists")
		return
		
	config.set_value("accounts", account, password)
	config.save(CONFIG_PATH)
	
	_show_message("Registration Successful", "Account registered successfully! Please return to login")
	
	reg_account_line_edit.text = ""
	reg_password_line_edit.text = ""
	confirm_password_line_edit.text = ""
	
	_on_go_to_login_button_pressed()

func _on_go_to_register_button_pressed() -> void:
	login_panel.hide()
	register_panel.show()

func _on_go_to_login_button_pressed() -> void:
	register_panel.hide()
	login_panel.show()
