# Gestisce il calcolo e la visualizzazione della copertura terrestre
extends Node
class_name CoverageManager

const LAT_STEP = 25
const LON_STEP = 25
const EARTH_RADIUS = 63.710
const COVERAGE_RADIUS_KM = 10.0

var earth_grid = []
var map_width := int(360 / LON_STEP)
var map_height := int(180 / LAT_STEP)
var coverage_image: Image
var coverage_texture: ImageTexture
var exported_initial = false

func _ready():
	initialize_earth_grid()
	init_coverage_map()

func initialize_earth_grid():
	earth_grid.clear()
	for lat in range(-90, 90, LAT_STEP):
		for lon in range(-180, 180, LON_STEP):
			earth_grid.append({
				"lat": lat,
				"lon": lon,
				"covered": false,
				"covered_count": 0
			})

func init_coverage_map():
	coverage_image = Image.new()
	coverage_image.create(map_width, map_height, false, Image.FORMAT_RGB8)
	coverage_texture = ImageTexture.new()
	coverage_texture.create_from_image(coverage_image)

func setup_ui_texture(texture_rect: TextureRect):
	texture_rect.texture = coverage_texture

func is_cell_covered(cell_lat: float, cell_lon: float, sat_pos: Vector3) -> bool:
	var cell_lat_rad = deg2rad(cell_lat)
	var cell_lon_rad = deg2rad(cell_lon)
	var cell_x = EARTH_RADIUS * cos(cell_lat_rad) * cos(cell_lon_rad)
	var cell_y = EARTH_RADIUS * sin(cell_lat_rad)
	var cell_z = EARTH_RADIUS * cos(cell_lat_rad) * sin(cell_lon_rad)
	var cell_pos = Vector3(cell_x, cell_y, cell_z)
	
	var distance = sat_pos.distance_to(cell_pos)
	return distance <= COVERAGE_RADIUS_KM

func update_coverage(satellites: Array):
	if coverage_image == null:
		print("ERRORE: coverage_image è null!")
		return
		
	# Reset copertura
	for cell in earth_grid:
		cell.covered = false
	
	# Calcola copertura per ogni satellite attivo
	for satellite in satellites:
		# Verifica se il satellite può fornire copertura
		# Gestisce sia oggetti AutonomousSatellite che Dictionary
		var is_active = false
		var health = 0.0
		var sat_theta = 0.0
		var sat_orbit_id = 0
		var sat_orbit_radius = 0.0
		var sat_orbit_inclination = 0.0
		var sat_total_orbits = 1
		
		if satellite is Dictionary:
			# Satellite come Dictionary
			is_active = satellite.get("active", false)
			health = satellite.get("health_status", 0.0)
			sat_theta = satellite.get("theta", 0.0)
			sat_orbit_id = satellite.get("orbit_id", 0)
			sat_orbit_radius = satellite.get("orbit_radius", EARTH_RADIUS + 50.0)  # valore di default
			sat_orbit_inclination = satellite.get("orbit_inclination_deg", 0.0)
			sat_total_orbits = satellite.get("total_orbits", 1)
		else:
			# Satellite come oggetto AutonomousSatellite
			is_active = satellite.active
			health = satellite.health_status
			sat_theta = satellite.theta
			sat_orbit_id = satellite.orbit_id
			sat_orbit_radius = satellite.orbit_radius
			sat_orbit_inclination = satellite.orbit_inclination_deg
			sat_total_orbits = satellite.total_orbits
		
		# Verifica se il satellite può fornire copertura
		if not is_active or health <= 0.0 or health < 0.7:
			continue
			
		# Calcola posizione orbitale
		var pos = calculate_satellite_orbital_position(
			sat_theta, 
			sat_orbit_id, 
			sat_orbit_radius, 
			sat_orbit_inclination, 
			sat_total_orbits
		)
		
		# Verifica copertura per ogni cella della griglia terrestre
		for cell in earth_grid:
			if is_cell_covered(cell.lat, cell.lon, pos):
				cell.covered = true
	
	# Aggiorna conteggio per statistiche
	for cell in earth_grid:
		if cell.covered:
			cell.covered_count += 1
	
	# Aggiorna immagine
	update_coverage_image()
	
	if not exported_initial:
		initial_coverage_to_csv()
		exported_initial = true


func update_coverage_image():
	coverage_image.lock()
	
	for cell in earth_grid:
		var x = int((cell.lon + 180) / LON_STEP)
		var y = int((90 - cell.lat) / LAT_STEP)
		
		# Colore basato sulla copertura
		var color = Color(0.1, 0.1, 0.1)  # default: grigio scuro (non coperto)
		if cell.covered:
			color = Color(0.0, 1.0, 0.0)  # verde (coperto)
		
		# Assicurati che le coordinate siano valide
		x = clamp(x, 0, coverage_image.get_width() - 1)
		y = clamp(y, 0, coverage_image.get_height() - 1)
		coverage_image.set_pixel(x, y, color)
	
	coverage_image.unlock()
	coverage_texture.set_data(coverage_image)

func estimate_coverage() -> float:
	"""Stima la percentuale di copertura terrestre pesata per latitudine"""
	var covered_weight := 0.0
	var total_weight := 0.0
	
	for cell in earth_grid:
		var lat_rad = deg2rad(cell.lat)
		var weight = cos(lat_rad)
		if weight < 0.0:
			weight = 0.0
		total_weight += weight
		if cell.covered:
			covered_weight += weight
	
	if total_weight > 0.0:
		return (covered_weight / total_weight) * 100.0
	else:
		return 0.0

func get_coverage_statistics() -> Dictionary:
	"""Restituisce statistiche dettagliate sulla copertura"""
	var total_cells = earth_grid.size()
	var covered_cells = 0
	var coverage_by_latitude = {}
	
	# Inizializza conteggi per latitudine
	for lat in range(-90, 90, LAT_STEP):
		coverage_by_latitude[lat] = {"total": 0, "covered": 0}
	
	# Conta celle coperte
	for cell in earth_grid:
		if cell.covered:
			covered_cells += 1
		
		coverage_by_latitude[cell.lat].total += 1
		if cell.covered:
			coverage_by_latitude[cell.lat].covered += 1
	
	# Calcola percentuali per latitudine
	var coverage_percentages = {}
	for lat in coverage_by_latitude:
		var data = coverage_by_latitude[lat]
		if data.total > 0:
			coverage_percentages[lat] = (float(data.covered) / float(data.total)) * 100.0
		else:
			coverage_percentages[lat] = 0.0
	
	return {
		"total_cells": total_cells,
		"covered_cells": covered_cells,
		"coverage_percentage": (float(covered_cells) / float(total_cells)) * 100.0,
		"weighted_coverage": estimate_coverage(),
		"coverage_by_latitude": coverage_percentages
	}

func get_uncovered_regions() -> Array:
	"""Restituisce un array delle regioni non coperte"""
	var uncovered = []
	
	for cell in earth_grid:
		if not cell.covered:
			uncovered.append({
				"lat": cell.lat,
				"lon": cell.lon
			})
	
	return uncovered

func calculate_satellite_orbital_position(theta: float, orbit_id: int, radius: float, inclination_deg: float, total_orbits: int) -> Vector3:
	"""Calcola la posizione orbitale 3D del satellite"""
	var inclination = deg2rad(inclination_deg)
	var RAAN = deg2rad(orbit_id * 360.0 / total_orbits)
	
	var x = radius * cos(theta)
	var z = radius * sin(theta)
	var y = 0.0
	var pos = Vector3(x, y, z)
	pos = pos.rotated(Vector3(1, 0, 0), inclination)
	pos = pos.rotated(Vector3(0, 1, 0), RAAN)
	return pos

func cell_weight(lat_deg: float) -> float:
	"""Calcola il peso di una cella basato sulla latitudine (correzione per distorsione di Mercatore)"""
	var lat_rad = deg2rad(lat_deg)
	return cos(lat_rad)

func reset_coverage_statistics():
	"""Resetta le statistiche di copertura accumulate"""
	for cell in earth_grid:
		cell.covered_count = 0

func export_coverage_data() -> Dictionary:
	"""Esporta i dati di copertura per debug o analisi esterna"""
	var export_data = {
		"grid_resolution": {"lat_step": LAT_STEP, "lon_step": LON_STEP},
		"earth_radius": EARTH_RADIUS,
		"coverage_radius": COVERAGE_RADIUS_KM,
		"grid_data": []
	}
	
	for cell in earth_grid:
		export_data.grid_data.append({
			"lat": cell.lat,
			"lon": cell.lon,
			"covered": cell.covered,
			"coverage_count": cell.covered_count
		})
	
	return export_data
	
func initial_coverage_to_csv():
	var file = File.new()
	var error = file.open("res://data/coverage_matrix.csv", File.WRITE)
	if error != OK:
		print("Errore nell'apertura del file CSV")
		return
	
	for i in range(earth_grid.size()):
		var cell = earth_grid[i]
		# Supponendo che tu abbia memorizzato le coordinate di griglia
		# ad esempio cell.grid_x e cell.grid_y
		var status = "covered" if cell.covered else "not covered"
		file.store_line(str(i) + "(" + "lat=" + str(cell.lat) 
		+ "_lng=" + str(cell.lon) + ") : " + status)

	file.close()
	print("Coverage matrix salvata correttamente.")

