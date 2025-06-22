extends Node

# Struttura dati per metriche
var metrics_data = {
	"timestamp": [],
	"active_satellites": [],
	"failed_satellites": [],
	"coverage_percentage": [],
	"avg_convergence_time": [],
	"network_connectivity": [],
	"orbital_distribution": [],
	"fault_cascade_events": []
}

# Configurazione logging
export var enable_logging = true
export var log_interval = 1.0  # secondi
export var output_file = "simulation_data.json"

var log_timer = 0.0
var simulation_start_time = 0.0

func _ready():
	simulation_start_time = OS.get_ticks_msec() / 1000.0

func _process(delta):
	if not enable_logging:
		return
		
	log_timer += delta
	if log_timer >= log_interval:
		collect_metrics()
		log_timer = 0.0

func collect_metrics():
	var current_time = OS.get_ticks_msec() / 1000.0 - simulation_start_time
	
	# Ottieni riferimento al main script
	var main = get_node("/root/Main")
	if not main:
		return
	
	# Raccogli metriche base
	metrics_data.timestamp.append(current_time)
	metrics_data.active_satellites.append(main.live_count)
	metrics_data.failed_satellites.append(main.fallen_count)
	
	# Calcola copertura
	var coverage = calculate_coverage_percentage(main)
	metrics_data.coverage_percentage.append(coverage)
	
	# Calcola connettività di rete
	var connectivity = calculate_network_connectivity(main)
	metrics_data.network_connectivity.append(connectivity)
	
	# Analizza distribuzione orbitale
	var distribution = analyze_orbital_distribution(main)
	metrics_data.orbital_distribution.append(distribution)

func calculate_coverage_percentage(main) -> float:
	var covered_cells = 0
	for cell in main.earth_grid:
		if cell.covered:
			covered_cells += 1
	return float(covered_cells) / float(main.earth_grid.size()) * 100.0

func calculate_network_connectivity(main) -> Dictionary:
	var connectivity_data = {
		"total_connections": 0,
		"avg_neighbors": 0.0,
		"isolated_satellites": 0,
		"max_component_size": 0
	}
	
	var total_neighbors = 0
	var active_satellites = 0
	
	for sat in main.satellites:
		if not sat.active:
			continue
			
		active_satellites += 1
		var neighbor_count = 0
		
		for neighbor_id in sat.neighbors:
			if main.satellites[neighbor_id].active:
				neighbor_count += 1
				
		total_neighbors += neighbor_count
		
		if neighbor_count == 0:
			connectivity_data.isolated_satellites += 1
	
	if active_satellites > 0:
		connectivity_data.avg_neighbors = float(total_neighbors) / float(active_satellites)
	
	connectivity_data.total_connections = total_neighbors / 2  # Ogni connessione conta doppia
	
	return connectivity_data

func analyze_orbital_distribution(main) -> Dictionary:
	var distribution = {
		"per_orbit": [],
		"uniformity_index": 0.0,
		"max_gap": 0.0,
		"min_gap": 360.0
	}
	
	# Conta satelliti per orbita
	for orbit in range(main.orbit_count):
		var active_in_orbit = 0
		var positions = []
		
		for sat in main.satellites:
			if sat.orbit_id == orbit and sat.active:
				active_in_orbit += 1
				positions.append(rad2deg(sat.theta))
		
		distribution.per_orbit.append(active_in_orbit)
		
		# Calcola gap tra satelliti in questa orbita
		if positions.size() > 1:
			positions.sort()
			for i in range(positions.size()):
				var gap = positions[(i + 1) % positions.size()] - positions[i]
				if gap < 0:
					gap += 360
				distribution.max_gap = max(distribution.max_gap, gap)
				distribution.min_gap = min(distribution.min_gap, gap)
	
	# Calcola indice di uniformità (coefficiente di variazione)
	var mean_per_orbit = 0.0
	for count in distribution.per_orbit:
		mean_per_orbit += count
	mean_per_orbit /= distribution.per_orbit.size()
	
	var variance = 0.0
	for count in distribution.per_orbit:
		variance += pow(count - mean_per_orbit, 2)
	variance /= distribution.per_orbit.size()
	
	if mean_per_orbit > 0:
		distribution.uniformity_index = sqrt(variance) / mean_per_orbit
	
	return distribution

func export_data():
	var file = File.new()
	if file.open("user://simulation_data.json", File.WRITE) != OK:
		print("Errore nell'aprire il file per la scrittura")
		return
	
	# Aggiungi metadati
	var export_data = {
		"metadata": {
			"simulation_duration": OS.get_ticks_msec() / 1000.0 - simulation_start_time,
			"total_satellites": get_node("/root/Main").total_satellites,
			"orbit_count": get_node("/root/Main").orbit_count,
			"satellites_per_orbit": get_node("/root/Main").satellites_per_orbit,
			"fault_probability": get_node("/root/Main").fault_probability,
			"export_timestamp": OS.get_datetime()
		},
		"metrics": metrics_data
	}
	
	file.store_line(JSON.print(export_data))
	file.close()
	print("Dati esportati in: ", OS.get_user_data_dir(), "/simulation_data.json")

func _exit_tree():
	if enable_logging:
		export_data()

# Funzioni per analisi in tempo reale
func get_current_fault_rate() -> float:
	var main = get_node("/root/Main")
	if main.total_satellites == 0:
		return 0.0
	return float(main.fallen_count) / float(main.total_satellites)

func get_convergence_time_after_fault() -> float:
	# Implementare logica per misurare tempo di convergenza
	# dopo un evento di fault
	return 0.0

func detect_cascade_failure() -> bool:
	# Implementare detection di guasti a cascata
	# (es. più di 3 guasti in 10 secondi)
	return false
