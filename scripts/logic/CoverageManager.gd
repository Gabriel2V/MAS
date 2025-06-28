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

func update_coverage(satellites: Array, satellite_manager: SatelliteManager):
	if coverage_image == null:
		print("ERRORE: coverage_image è null!")
		return
		
	# Reset copertura
	for cell in earth_grid:
		cell.covered = false
	
	# Calcola copertura per ogni satellite attivo
	for s in satellites:
		if not s.active or s.falling or s.removed:
			continue
		
		var RAAN = deg2rad(s.orbit_id * 360.0 / satellite_manager.orbit_count)
		var pos = satellite_manager.orbital_position(
			satellite_manager.orbit_radius, 
			satellite_manager.orbit_inclination_deg, 
			RAAN, 
			s.theta
		)
		
		for cell in earth_grid:
			if is_cell_covered(cell.lat, cell.lon, pos):
				cell.covered = true
	
	# Aggiorna conteggio per statistiche
	for cell in earth_grid:
		if cell.covered:
			cell.covered_count += 1
			
	if not exported_initial:
		initial_coverage_to_csv()
		exported_initial = true

	
	# Aggiorna immagine
	update_coverage_image()

func update_coverage_image():
	coverage_image.lock()
	for cell in earth_grid:
		var x = int((cell.lon + 180) / LON_STEP)
		var y = int((90 - cell.lat) / LAT_STEP)
		var color = Color(0.1, 0.1, 0.1)  # default: dark gray
		if cell.covered:
			color = Color(0.0, 1.0, 0.0)  # green
		
		x = clamp(x, 0, coverage_image.get_width() - 1)
		y = clamp(y, 0, coverage_image.get_height() - 1)
		coverage_image.set_pixel(x, y, color)
	coverage_image.unlock()
	coverage_texture.set_data(coverage_image)

func estimate_coverage() -> float:
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
	
	return (covered_weight / total_weight) * 100.0

func cell_weight(lat_deg: float) -> float:
	var lat_rad = deg2rad(lat_deg)
	return cos(lat_rad)

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
