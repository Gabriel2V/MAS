extends Node

export(int) var satellites_per_orbit = 5
export(int) var orbit_count = 3
export(float) var orbit_radius = 20.0
export(float) var orbit_inclination_deg = 53.0
export(int) var walker_f = 1  # Phase factor (0 <= f < orbit_count)

onready var multi_mesh_instance := $MultiMeshInstance

var total_satellites = satellites_per_orbit * orbit_count
var satellite_angles = []
var angular_velocity = 2 * PI / satellites_per_orbit # rad/s


func _ready():
	multi_mesh_instance = get_node_or_null("MultiMeshInstance")
	if not multi_mesh_instance:
		printerr("ERRORE: Nodo MultiMeshInstance non trovato nella scena!")
		return
	print("MultiMeshInstance: ", multi_mesh_instance)

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
		for sat in range(satellites_per_orbit):
			# Phase shift per Walker delta pattern
			var phase_shift = 2 * PI * ((sat + orbit * walker_f) % satellites_per_orbit) / satellites_per_orbit
			var theta = phase_shift
			var pos = orbital_position(orbit_radius, orbit_inclination_deg, RAAN, theta)
			var transform = Transform().translated(pos)
			transform.basis = Basis().scaled(Vector3.ONE * 0.3)
			mm.set_instance_transform(id, transform)

			satellite_angles.append(theta)
			id += 1


func orbital_position(radius: float, inclination_deg: float, RAAN: float, anomaly: float) -> Vector3:
	var inclination = deg2rad(inclination_deg)
	var x = radius * cos(anomaly)
	var y = radius * sin(anomaly)
	var z = 0.0
	var pos = Vector3(x, y, z)

	pos = pos.rotated(Vector3(1, 0, 0), inclination)
	pos = pos.rotated(Vector3(0, 1, 0), RAAN)

	return pos


func _process(delta):
	var id = 0
	for orbit in range(orbit_count):
		var RAAN = deg2rad(orbit * 360.0 / orbit_count)
		for sat in range(satellites_per_orbit):
			satellite_angles[id] += angular_velocity * delta
			var theta = satellite_angles[id]
			var pos = orbital_position(orbit_radius, orbit_inclination_deg, RAAN, theta)

			var transform = Transform().translated(pos)
			transform.basis = Basis().scaled(Vector3.ONE * 0.3)
			multi_mesh_instance.multimesh.set_instance_transform(id, transform)

			id += 1
