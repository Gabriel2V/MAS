extends Node

export(int) var satellites_per_orbit = 24 # numero di satelliti per orbita
export(int) var orbit_count = 36 # numero di orbite
export(float) var orbit_radius = 70.00 # raggio orbite (scalato)
export(float) var orbit_inclination_deg = 53.0 # inclinazione in gradi dell'orbita
export(int) var walker_f = 12  # Phase factor (0 <= f < orbit_count)
export(float, 0.1, 100.0) var simulation_speed := 1.0 # 1.0 = tempo normale
export(int) var stats_refresh_cycles = 50 

# Parametri riposizionamento
export(float) var repositioning_speed_multiplier = 2.0 # Moltiplicatore velocità durante riposizionamento

const EARTH_MASS = 5.972e24  # kg
const G = 6.674e-11  # m3/kg·s2

onready var multi_mesh_instance := $MultiMeshInstance
onready var option_btn := $Control/SpeedButton
onready var status_label = $Label 

onready var total_satellites = satellites_per_orbit * orbit_count
var satellite_angles = []
onready var live_count = total_satellites
var fallen_count = 0
var cylces_count = 0
var simulation_time = 0.0 # Tempo simulato in secondi

var satellites = [] # ogni elemento: {id, orbit_id, theta, neighbors, last_heartbeat_times, repositioning, target_theta}
export(float) var fault_probability = 0.00001#0.001 # probabilità al secondo di fault

const LAT_STEP = 25
const LON_STEP = 25 
const EARTH_RADIUS = 63.710
const COVERAGE_RADIUS_KM = 10.0  
var earth_grid = []  # griglia di celle con copertura

var map_width := int(360 / LON_STEP)  # 36 per LON_STEP=10
var map_height := int(180 / LAT_STEP)  # 18 per LAT_STEP=10
var coverage_image : Image
var coverage_texture : ImageTexture

const BLINK_SPEED = 5.0  # Velocità del lampeggio
const FAILING_COLOR = Color(1.0, 0.0, 0.0)  # Rosso per falling
const REPOSITIONING_COLOR = Color(1.0, 1.0, 0.0)  # Giallo per repositioning
const NORMAL_COLOR = Color(0.0, 1.0, 0.0)  # Verde per normale
const INACTIVE_COLOR = Color(0.5, 0.5, 0.5)  # Grigio per inattivo

func _ready():
	option_btn = get_node_or_null("Control/SpeedButton")
	option_btn.clear()
	option_btn.add_item("Stop", 0)
	option_btn.add_item("1x", 1)
	option_btn.add_item("2x", 2)
	option_btn.add_item("10x", 3)
	option_btn.add_item("100x", 4)
	option_btn.select(1)
	
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
	var realistic_angular_velocity = calculate_scaled_angular_velocity()
	
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
				"angular_velocity": realistic_angular_velocity, #angular_velocity,
				"falling": false,
				"fall_timer": 0.0,
				"repositioning": false,
				"target_theta": 0.0,
				"original_angular_velocity": realistic_angular_velocity
			})
			
			id += 1
	initialize_earth_grid()
	init_coverage_map()
	

func calculate_scaled_angular_velocity() -> float:
	var orbit_radius_real_m = orbit_radius * 1000.0 * 100.0 # SCALE_FACTOR 
	# Calcola velocità orbitale reale 
	var velocity_real_ms = sqrt(G * EARTH_MASS / orbit_radius_real_m)  # m/s
	# Calcola velocità angolare reale
	var angular_vel_real = velocity_real_ms / orbit_radius_real_m  # rad/s
	return angular_vel_real


func orbital_position(radius: float, inclination_deg: float, RAAN: float, anomaly: float) -> Vector3:
	var inclination = deg2rad(inclination_deg)
	var x = radius * cos(anomaly)
	var z = radius * sin(anomaly)
	var y = 0.0
	var pos = Vector3(x, y, z)
	pos = pos.rotated(Vector3(1, 0, 0), inclination)
	pos = pos.rotated(Vector3(0, 1, 0), RAAN)
	return pos

func calculate_optimal_positions(orbit_id: int) -> Array:
	"""Calcola le posizioni ottimali per i satelliti attivi nell'orbita"""
	var active_satellites = []
	for sat in satellites:
		if sat.orbit_id == orbit_id and sat.active and not sat.falling:
			active_satellites.append(sat)
	
	if active_satellites.size() == 0:
		return []
	
	var optimal_positions = []
	var angular_spacing = 2 * PI / active_satellites.size()
	
	# Trova il satellite con l'angolo più piccolo come riferimento
	var min_angle = active_satellites[0].theta
	for sat in active_satellites:
		if sat.theta < min_angle:
			min_angle = sat.theta
	
	# Calcola posizioni ottimali a partire dal riferimento
	for i in range(active_satellites.size()):
		var optimal_theta = min_angle + i * angular_spacing
		# Normalizza l'angolo tra 0 e 2π
		while optimal_theta >= 2 * PI:
			optimal_theta -= 2 * PI
		while optimal_theta < 0:
			optimal_theta += 2 * PI
		optimal_positions.append(optimal_theta)
	
	return optimal_positions

func start_repositioning(orbit_id: int):
	"""Avvia il riposizionamento dei satelliti in un'orbita"""
	var active_satellites = []
	for sat in satellites:
		if sat.orbit_id == orbit_id and sat.active and not sat.falling:
			active_satellites.append(sat)
	
	if active_satellites.size() <= 1:
		return  # Non serve riposizionare se c'è solo un satellite o nessuno
	
	var optimal_positions = calculate_optimal_positions(orbit_id)
	
	# Assegna ogni satellite alla posizione ottimale più vicina
	var assigned_positions = []
	for sat in active_satellites:
		var best_target = -1
		var min_distance = INF
		
		for i in range(optimal_positions.size()):
			if i in assigned_positions:
				continue
			
			var target_theta = optimal_positions[i]
			var distance = angle_distance(sat.theta, target_theta)
			
			if distance < min_distance:
				min_distance = distance
				best_target = i
		
		if best_target != -1:
			assigned_positions.append(best_target)
			sat.target_theta = optimal_positions[best_target]
			sat.repositioning = true
			#print("Satellite ", sat.id, " inizia riposizionamento verso posizione ", rad2deg(sat.target_theta))

func angle_distance(angle1: float, angle2: float) -> float:
	"""Calcola la distanza angolare più breve tra due angoli"""
	var diff = abs(angle2 - angle1)
	if diff > PI:
		diff = 2 * PI - diff
	return diff

func update_repositioning(satellite: Dictionary, delta: float):
	"""Aggiorna il riposizionamento di un satellite"""
	if not satellite.repositioning :
		return
	
	var target_theta = satellite.target_theta
	var current_theta = satellite.theta
	
	# Calcola la direzione più breve per raggiungere il target
	var diff = target_theta - current_theta
	if diff > PI:
		diff -= 2 * PI
	elif diff < -PI:
		diff += 2 * PI
	
	# Se siamo vicini al target, ferma il riposizionamento
	if abs(diff) < 0.01:  # Tolleranza di ~0.6 gradi
		satellite.repositioning = false
		satellite.angular_velocity = satellite.original_angular_velocity
		#print("Satellite ", satellite.id, " ha completato il riposizionamento")
		return
	
	
	# Applica velocità aumentata nella direzione corretta
	var direction = sign(diff)
	var base_velocity = satellite.original_angular_velocity
	satellite.angular_velocity = base_velocity * repositioning_speed_multiplier * direction

func _process(delta):
	simulation_time += delta * simulation_speed 
	delta *= simulation_speed
	var id = 0
	var orbits_affected = []  # Traccia le orbite che hanno perso satelliti
	
	# Calcola il fattore di lampeggio basato sul tempo
	var blink_factor = abs(sin(simulation_time * BLINK_SPEED))
	
	for orbit in range(orbit_count):
		var RAAN = deg2rad(orbit * 360.0 / orbit_count)
		for sat in range(satellites_per_orbit):
			if satellites[id].active and randf() < fault_probability * delta: 
				#satellites[id].active = false
				satellites[id].falling = true
				satellites[id].fall_timer = 0.0
				#print("Satellite ", id, " FAILED")
				fallen_count += 1
				live_count -= 1
				if not (satellites[id].orbit_id in orbits_affected):
					orbits_affected.append(satellites[id].orbit_id)
			# Aggiorna riposizionamento
			if satellites[id].repositioning:
				update_repositioning(satellites[id], delta)
			# Update angolo solo se attivo
			if satellites[id].active or satellites[id].falling:
				satellite_angles[id] += satellites[id].angular_velocity * delta
			var theta = satellite_angles[id]
			var pos = orbital_position(orbit_radius, orbit_inclination_deg, RAAN, theta)
			
			# Se sta cadendo, scende verso la Terra
			if satellites[id].falling:
				satellites[id].fall_timer += delta
				
				# Calcola la direzione verso il centro della Terra
				var direction_to_center = -pos.normalized()
				
				# Aggiungi un po' di casualità per un effetto più realistico
				var randomness = Vector3(
					rand_range(-0.1, 0.1),
					rand_range(-0.1, 0.1),
					rand_range(-0.1, 0.1))
				
				# Muovi il satellite verso il centro con accelerazione
				var fall_speed = satellites[id].fall_timer * 2.0  # Aumenta la velocità col tempo
				pos += direction_to_center * fall_speed * delta + randomness * delta
			# Aggiorna posizione
			var transform = Transform().translated(pos)
			transform.basis = Basis().scaled(Vector3.ONE * 0.3)
			multi_mesh_instance.multimesh.set_instance_transform(id, transform)
			
			# Colore in base allo stato con effetto lampeggiante
			var color = NORMAL_COLOR  # verde - normale
			
			if satellites[id].falling:
				# Rosso lampeggiante per satelliti in caduta
				color = FAILING_COLOR.linear_interpolate(Color(0.5, 0, 0), blink_factor)
			elif satellites[id].repositioning:
				# Giallo lampeggiante per satelliti in riposizionamento
				color = REPOSITIONING_COLOR.linear_interpolate(Color(0.5, 0.5, 0), blink_factor)
			elif not satellites[id].active:
				color = INACTIVE_COLOR  # grigio - inattivo
			
			multi_mesh_instance.multimesh.set_instance_custom_data(id, color)
			
			# Aggiorna angolo
			satellites[id].theta = theta
			id += 1
#			# Dopo 5s, disattiva del tutto e nascondi
#			if satellites[id].fall_timer >= 5.0:
#				var transform = multi_mesh_instance.multimesh.get_instance_transform(id)
#				transform.basis = Basis().scaled(Vector3(0, 0, 0))
#				multi_mesh_instance.multimesh.set_instance_transform(id, transform)
#				satellites[id].active = false
#				satellites[id].falling = false
#				id += 1
#				continue
#
#			# Dopo 5s, disattiva del tutto e nascondi
#			if satellites[id].fall_timer >= 5.0:
#				var transform = multi_mesh_instance.multimesh.get_instance_transform(id)
#				transform.basis = Basis().scaled(Vector3(0, 0, 0))
#				multi_mesh_instance.multimesh.set_instance_transform(id, transform)
#				satellites[id].active = false
#				satellites[id].falling = false
#				id += 1
#				continue
#			# Aggiorna posizione
#			var transform = Transform().translated(pos)
#			transform.basis = Basis().scaled(Vector3.ONE * 0.3)
#			multi_mesh_instance.multimesh.set_instance_transform(id, transform)
#
#			# Colore in base allo stato
#			var color = Color(0, 1, 0)  # verde - normale
#			if satellites[id].repositioning:
#				color = Color(0, 0, 1)  # blu - riposizionamento
#			elif satellites[id].falling:
#				color = Color(1.0, 0.5, 0.0)  # arancione - caduta
#			elif not satellites[id].active:
#				color = Color(1.0, 0.0, 0.0)  # rosso - inattivo
#			multi_mesh_instance.multimesh.set_instance_custom_data(id, color)
#			# Aggiorna angolo
#			satellites[id].theta = theta
#			id += 1
			
	# Avvia riposizionamento per le orbite affette
	for orbit_id in orbits_affected:
		start_repositioning(orbit_id)
	cylces_count += 1
	
	update_heartbeats(delta)
	if cylces_count == stats_refresh_cycles:
		#print("refreshing coverage",simulation_time)
		update_coverage()
		estimate_coverage()
		cylces_count = 0
	
	# Aggiorna statistiche
	var repositioning_count = 0

	for sat in satellites:
		if sat.active:
			if sat.repositioning:
				repositioning_count += 1
		
	var time_string = format_simulation_time(simulation_time)
	status_label.text = "Live satellites: %d\nDead satellites: %d\nRepositioning: %d\nSim Time: %s\n" % [live_count, fallen_count, repositioning_count, time_string]


func format_simulation_time(total_seconds: float) -> String:
	"""Formatta il tempo simulato in ore:minuti:secondi"""
	var hours = int(total_seconds) / 3600
	var minutes = (int(total_seconds) % 3600) / 60
	var seconds = int(total_seconds) % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

func update_heartbeats(delta):
	for sat in satellites:
		if simulation_speed != 0:
			sat.heartbeat_timer += delta / simulation_speed
		else:
			sat.heartbeat_timer += 0
		for neighbor_id in sat.neighbors:
			if simulation_speed != 0:
				sat.last_heartbeat[neighbor_id] += delta / simulation_speed
			else:
				sat.last_heartbeat[neighbor_id] += 0
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
						#update_angular_velocities()

func update_angular_velocities():
	var realistic_angular_velocity = calculate_scaled_angular_velocity()
	for orbit in range(orbit_count):
		var sats_in_orbit = []
		for s in satellites:
			if s.orbit_id == orbit and s.active:
				sats_in_orbit.append(s)
		var count = sats_in_orbit.size()
		if count == 0:
			continue
		var new_velocity = ( realistic_angular_velocity * count) / satellites_per_orbit #2 * PI / count
		for s in sats_in_orbit:
			s.angular_velocity = new_velocity
			

func _on_SpeedButton_item_selected(index):
	match index:
		0:
			simulation_speed = 0
		1:
			simulation_speed = 1
		2:
			simulation_speed = 2
		3:
			simulation_speed = 10
		4: 
			simulation_speed = 100

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
	# Verifica che coverage_image sia inizializzata
	if coverage_image == null:
		print("ERRORE: coverage_image è null!")
		return
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
	# Update image
	coverage_image.lock()
	for cell in earth_grid:
		var x = int((cell.lon + 180) / LON_STEP)
		var y = int((90 - cell.lat) / LAT_STEP)
		var color = Color(0.1, 0.1, 0.1) # default: dark gray
		if cell.covered:
			color = Color(0.0, 1.0, 0.0) # green
		x = clamp(x, 0, coverage_image.get_width() - 1)
		y = clamp(y, 0, coverage_image.get_height() - 1)
		coverage_image.set_pixel(x, y, color)
	coverage_image.unlock()
	coverage_texture.set_data(coverage_image)


func estimate_coverage():
	#var covered_cells = 0
	var covered_weight := 0.0
	var total_weight := 0.0
	for cell in earth_grid:
		var lat_rad = deg2rad(cell.lat)
		var weight = cos(lat_rad)
		if weight < 0.0:
			weight = 0.0  # per sicurezza
		total_weight += weight
		if cell.covered:
			covered_weight += weight
			#covered_cells += 1
	var percent := (covered_weight / total_weight) * 100.0
	#var percent := float(covered_cells) / float(earth_grid.size()) * 100.0
	# AGGIORNA UI
	if has_node("Control/HBoxContainer/ProgressBar"):
		var bar = get_node("Control/HBoxContainer/ProgressBar")
		bar.value = percent
	if has_node("Control/HBoxContainer/CoverageLabel"):
		var lbl = get_node("Control/HBoxContainer/CoverageLabel")
		lbl.text = "Copertura: "#%.2f%%" % percent		

func init_coverage_map():
	coverage_image = Image.new()
	coverage_image.create(map_width, map_height, false, Image.FORMAT_RGB8)
	coverage_texture = ImageTexture.new()
	coverage_texture.create_from_image(coverage_image)

	$Control/CoverageMapPanel/CoverageMapTexture.texture = coverage_texture

func cell_weight(lat_deg: float) -> float:
	var lat_rad = deg2rad(lat_deg)
	return cos(lat_rad)  # Celle vicine ai poli valgono meno
