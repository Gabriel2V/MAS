extends Spatial

var rotation_speed = 0.005
var is_rotating = false
var last_mouse_pos = Vector2()
var zoom_speed = 2.0

func _ready():
	pass
	

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_LEFT:
			is_rotating = event.pressed
			last_mouse_pos = event.position
	elif event is InputEventMouseMotion and is_rotating:
		var delta = event.relative
		# Ruota attorno all'asse Y (orizzontale) e all'asse X (verticale)
		rotate_y(-delta.x * rotation_speed)
		rotate_x(-delta.y * rotation_speed)
		#$Camera.rotate_x(-delta.y * rotation_speed)
		# Clamp l'inclinazione verticale per evitare ribaltamenti
		#var camera_rot = $Camera.rotation_degrees
		#camera_rot.x = clamp(camera_rot.x, -89, 89)
		#$Camera.rotation_degrees = camera_rot
		# Zoom con la rotellina del mouse
	if event is InputEventMouseButton:
		if event.button_index == BUTTON_WHEEL_UP:
			zoom_camera(-zoom_speed)
		elif event.button_index == BUTTON_WHEEL_DOWN:
			zoom_camera(zoom_speed)

func zoom_camera(amount):
	$Camera.size += amount


func _on_HSlider_value_changed(value):
	$Camera.size = 100-value
	

func _on_VScrollBar_value_changed(value):
	print("rotation: ",$Camera.translation)
	$Camera.translate(Vector3(0,value-50*0.9,0))
	rotate_x(value-50*-0.9)
