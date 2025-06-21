extends Node

export(int) var satellites_per_orbit = 50
export(int) var orbit_count = 25
export(float) var orbit_radius = 7000
export(float) var orbit_inclination_deg = 53.0
export(int) var walker_f = 1  # Phase factor (0 <= f < orbit_count)
export(float, 0.1, 10.0) var simulation_speed := 1.0 # 1.0 = tempo normale


onready var multi_mesh_instance := $MultiMeshInstance
onready var option_btn := $Control/SpeedButton
onready var status_label = $Label 

var total_satellites = satellites_per_orbit * orbit_count
var satellite_angles = []
var angular_velocity = 2 * PI / satellites_per_orbit # rad/s
var live_count = total_satellites
var fallen_count = 0

var satellites = [] # ogni elemento: {id, orbit_id, theta, neighbors, last_heartbeat_times}
export(float) var fault_probability = 0.001 # probabilità al secondo di fault

const LAT_STEP = 10
const LON_STEP = 10
const EARTH_RADIUS = 6371.0
const COVERAGE_RADIUS_KM = 1000.0
var earth_grid = []  # griglia di celle con copertura



func _ready():
	option_btn = get_node_or_null("Control/SpeedButton")
	option_btn.clear()
	option_btn.add_item("Stop", 0)
	option_btn.add_item("0.5x", 1)
	option_btn.add_item("1x", 2)
	option_btn.add_item("2x", 3)
	option_btn.select(2)
	
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
	mm.custom_data_format = MultiMesh.CUSTOM_DATA_8BIT
	mm.instance_count = total_satellites
	multi_mesh_instance.multimesh = mm
	
	satellites.clear()
	satellite_angles.clear()
	
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
			
			
		# Neighbors: previous and next in orbit (circular)
			var prev = (sat - 1 + satellites_per_orbit) % satellites_per_orbit + orbit * satellites_per_orbit
			var next = (sat + 1) % satellites_per_orbit + orbit * satellites_per_orbit

			satellites.append({
				"id": id,
				"orbit_id": orbit,
				"theta": theta,
				"neighbors": [prev, next],
				"last_heartbeat": {prev: 0.0, next: 0.0},
				"heartbeat_timer": 0.0,
				"active": true,
				"angular_velocity": angular_velocity,
				"falling": false,
				"fall_timer": 0.0
			})
			
			id += 1
	initialize_earth_grid()


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
	
	delta *= simulation_speed
	var id = 0
	for orbit in range(orbit_count):
		var RAAN = deg2rad(orbit * 360.0 / orbit_count)
		for sat in range(satellites_per_orbit):
			#satellite_angles[id] += angular_velocity * delta			
			if satellites[id].active and randf() < fault_probability * delta: 
				#satellites[id].active = false
				satellites[id].falling = true
				satellites[id].fall_timer = 0.0
				print("Satellite ", id, " FAILED")
				fallen_count += 1
				live_count -= 1
			
			# Update angolo solo se attivo
			if satellites[id].active or satellites[id].falling:
				satellite_angles[id] += satellites[id].angular_velocity * delta
			
			var theta = satellite_angles[id]
			var pos = orbital_position(orbit_radius, orbit_inclination_deg, RAAN, theta)
			
			# Se sta cadendo, scende
			if satellites[id].falling:
				satellites[id].fall_timer += delta
				var descent = satellites[id].fall_timer * 2.0
				pos.y -= descent

			# Dopo 5s, disattiva del tutto e nascondi
			if satellites[id].fall_timer >= 5.0:
				var transform = multi_mesh_instance.multimesh.get_instance_transform(id)
				transform.basis = Basis().scaled(Vector3(0, 0, 0))
				multi_mesh_instance.multimesh.set_instance_transform(id, transform)
				satellites[id].active = false
				satellites[id].falling = false
				id += 1
				continue

			# Aggiorna posizione
			var transform = Transform().translated(pos)
			transform.basis = Basis().scaled(Vector3.ONE * 0.3)
			multi_mesh_instance.multimesh.set_instance_transform(id, transform)

			# Colore in base allo stato
			var color = Color(0, 1, 0)  # verde
			if satellites[id].falling:
				color = Color(1.0, 0.5, 0.0)  # arancione
			elif not satellites[id].active:
				color = Color(1.0, 0.0, 0.0)  # rosso

			multi_mesh_instance.multimesh.set_instance_custom_data(id, color)

			# Aggiorna angolo
			satellites[id].theta = theta
			id += 1

	update_heartbeats(delta)
	update_coverage()
	estimate_coverage()

	status_label.text = "Live satellites: %d \n Dead satellites: %d" % [live_count, fallen_count]
	
func update_heartbeats(delta):
	for sat in satellites:
		sat.heartbeat_timer += delta
		for neighbor_id in sat.neighbors:
			sat.last_heartbeat[neighbor_id] += delta

		# Invia heartbeat ogni 1 secondo
		if sat.heartbeat_timer >= 1.0:
			for neighbor_id in sat.neighbors:
				# Simula ricezione dal satellite verso il vicino
				var neighbor = satellites[neighbor_id]
				neighbor.last_heartbeat[sat.id] = 0.0
				#print("Satellite ", sat.id, " sends heartbeat to ", neighbor_id)
			sat.heartbeat_timer = 0.0

		# Controlla se un vicino è considerato morto
		for neighbor_id in sat.neighbors:
			if sat.last_heartbeat[neighbor_id] > 3.0: # fault timeout
					if satellites[neighbor_id].active:
						print("⚠ Satellite ", sat.id, " detects fault in neighbor ", neighbor_id)
						satellites[neighbor_id].active = false
						update_angular_velocities()


func update_angular_velocities():
	for orbit in range(orbit_count):
		var sats_in_orbit = []
		for s in satellites:
			if s.orbit_id == orbit and s.active:
				sats_in_orbit.append(s)
		var count = sats_in_orbit.size()
		if count == 0:
			continue
		var new_velocity = 2 * PI / count
		for s in sats_in_orbit:
			s.angular_velocity = new_velocity
			

func _on_SpeedButton_item_selected(index):
	match index:
		0:
			simulation_speed = 0
		1:
			simulation_speed = 0.5
		2:
			simulation_speed = 1
		3:
			simulation_speed = 2

func initialize_earth_grid():
	earth_grid.clear()
	for lat in range(-90, 90, LAT_STEP):
		for lon in range(-180, 180, LON_STEP):
			earth_grid.append({
				"lat": lat,
				"lon": lon,
				"covered": false,
				"covered_count": 0  # utile per media nel tempo
			})

func is_cell_covered(cell_lat: float, cell_lon: float, sat_pos: Vector3) -> bool:
	# Converti cella in coordinate 3D (approssimazione sferica)
	var cell_lat_rad = deg2rad(cell_lat)
	var cell_lon_rad = deg2rad(cell_lon)
	var cell_x = EARTH_RADIUS * cos(cell_lat_rad) * cos(cell_lon_rad)
	var cell_y = EARTH_RADIUS * sin(cell_lat_rad)
	var cell_z = EARTH_RADIUS * cos(cell_lat_rad) * sin(cell_lon_rad)
	var cell_pos = Vector3(cell_x, cell_y, cell_z)

	var distance = sat_pos.distance_to(cell_pos)
	return distance <= COVERAGE_RADIUS_KM

func update_coverage():
	for cell in earth_grid:
		cell.covered = false

	for s in satellites:
		if not s.active:
			continue
		var RAAN = deg2rad(s.orbit_id * 360.0 / orbit_count)
		var pos = orbital_position(orbit_radius, orbit_inclination_deg, RAAN, s.theta)

		for cell in earth_grid:
			if is_cell_covered(cell.lat, cell.lon, pos):
				cell.covered = true
	
	# Aggiorna conteggio per media
	for cell in earth_grid:
		if cell.covered:
			cell.covered_count += 1

func estimate_coverage():
	var covered_cells = 0
	for cell in earth_grid:
		if cell.covered:
			covered_cells += 1
	var percent = float(covered_cells) / float(earth_grid.size()) * 100.0
	print("🗺️ Copertura terrestre: ", percent, "%")
