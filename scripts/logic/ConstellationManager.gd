extends Node

export(PackedScene) var SatelliteScene
export(int) var satellites_per_orbit = 5
export(int) var orbit_count = 3

func _ready():
	var id = 0
	for orbit in range(orbit_count):
		for i in range(satellites_per_orbit):
			var sat = SatelliteScene.instance()
			sat.satellite_id = id
			sat.orbit_id = orbit
			sat.theta = 2 * PI * i / satellites_per_orbit
			sat.angular_velocity = 2 * PI / satellites_per_orbit
			add_child(sat)
			id += 1
