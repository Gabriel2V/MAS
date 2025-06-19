extends Node

export(int) var satellites_per_orbit = 5
export(int) var orbit_count = 3
export(float) var orbit_radius = 20_000.0
export(float) var orbit_inclination_deg = 53.0

onready var multi_mesh_instance := $MultiMeshInstance
var total_satellites = satellites_per_orbit * orbit_count

func _ready():
	var mesh = preload("res://scenes/Satellite.tres")
	
	var mm = MultiMesh.new()
	mm.mesh = mesh
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_NONE
	mm.custom_data_format = MultiMesh.CUSTOM_DATA_NONE
	mm.instance_count = total_satellites
	multi_mesh_instance.multimesh = mm
	
	var id = 0
	for orbit in range(orbit_count):
		var RAAN = deg2rad(orbit * 360.0 / orbit_count)
		for i in range(satellites_per_orbit):
			var theta = 2 * PI * i / satellites_per_orbit
			var pos = orbital_position(orbit_radius, orbit_inclination_deg, RAAN, theta)
			var transform = Transform().translated(pos)
			mm.set_instance_transform(id, transform)
			id += 1

func orbital_position(radius: float, inclination_deg: float, RAAN: float, anomaly: float) -> Vector3:
	var inclination = deg2rad(inclination_deg)
	var x = radius * cos(anomaly)
	var y = radius * sin(anomaly)
	var z = 0.0
	var pos = Vector3(x, y, z)
	
	# Rotazione per inclinazione sull'asse X
	pos = pos.rotated(Vector3(1, 0, 0), inclination)
	
	# Rotazione per RAAN sull'asse Y
	pos = pos.rotated(Vector3(0, 1, 0), RAAN)
	
	return pos
