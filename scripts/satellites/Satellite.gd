extends Spatial

var satellite_id = -1
var orbit_id = -1
var theta = 0.0 # angolo sull'orbita (in radianti)
var angular_velocity = 0.01 # modificabile per reorganizzazione
var heartbeat_timer = 0.0
var neighbors = [] # [id precedente, id successivo]

func _ready():
	print("Satellite ", satellite_id, " initialized.")

func _physics_process(delta):
	theta += angular_velocity * delta
	rotate_orbit()
	send_heartbeat(delta)

func rotate_orbit():
	var radius = 10.0 + orbit_id * 5
	var x = radius * cos(theta)
	var z = radius * sin(theta)
	var y = 0.0
	translation = Vector3(x, y, z)

func send_heartbeat(delta):
	heartbeat_timer += delta
	if heartbeat_timer >= 1.0:
		# simulazione: stampa su log
		print("Satellite ", satellite_id, " heartbeat to ", neighbors)
		heartbeat_timer = 0.0
