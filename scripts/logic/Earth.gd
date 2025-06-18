extends Spatial

var rotation_speed = 360.0 / (60 * 60 * 24) # 1 rotazione al giorno

func _physics_process(delta):
	rotate_y(deg2rad(rotation_speed * delta))
