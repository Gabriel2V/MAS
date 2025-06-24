# Gestisce la raccolta e l'esportazione delle metriche di simulazione
extends Node
class_name DataCollector

# Struttura dati per metriche
var metrics_data = {
	"timestamp": [],
	"active_satellites": [],
	"repositioning_satellites": [],
	"falling_satellites": [],
	"removed_satellites": [],
	"coverage_percentage": [],
	"avg_convergence_time": [],
	"network_connectivity": [],
	"orbital_distribution": [],
	"fault_cascade_events": [],
	"heartbeat_timeouts": []
}

# Configurazione logging
export var enable_logging = true
export var log_interval = 1.0  # secondi
export var output_file = "simulation_data.json"
export var data_folder = "data"  # Nome della cartella

var log_timer = 0.0
var simulation_start_time = 0.0
var last_fault_time = 0.0
var recent_faults = []

# Riferimenti ai manager
onready var satellite_manager: SatelliteManager
onready var coverage_manager: CoverageManager
onready var heartbeat_manager: HeartbeatManager

func _ready():
	simulation_start_time = OS.get_ticks_msec() / 1000.0
	
	# Ottieni riferimenti ai manager dal nodo principale
	var main = get_node("/root/Main")
	if main:
		satellite_manager = main.get_node("SatelliteManager")
		coverage_manager = main.get_node("CoverageManager")
		heartbeat_manager = main.get_node("HeartbeatManager")
	
	# Connetti ai segnali per rilevare eventi
	if satellite_manager:
		satellite_manager.connect("satellite_failed", self, "_on_satellite_failed")
	if heartbeat_manager:
		heartbeat_manager.connect("neighbor_fault_detected", self, "_on_neighbor_fault_detected")

func _process(delta):
	if not enable_logging:
		return
		
	log_timer += delta
	if log_timer >= log_interval:
		collect_metrics()
		log_timer = 0.0

func collect_metrics():
	var current_time = OS.get_ticks_msec() / 1000.0 - simulation_start_time
	
	if not satellite_manager:
		return
	
	# Raccogli metriche base dai satelliti
	var stats = count_satellite_states()
	
	metrics_data.timestamp.append(current_time)
	metrics_data.active_satellites.append(stats.active)
	metrics_data.repositioning_satellites.append(stats.repositioning)
	metrics_data.falling_satellites.append(stats.falling)
	metrics_data.removed_satellites.append(stats.removed)
	
	# Calcola copertura se disponibile il coverage manager
	var coverage = 0.0
	if coverage_manager:
		coverage = coverage_manager.estimate_coverage()
	metrics_data.coverage_percentage.append(coverage)
	
	# Calcola connettività di rete
	var connectivity = calculate_network_connectivity()
	metrics_data.network_connectivity.append(connectivity)
	
	# Analizza distribuzione orbitale
	var distribution = analyze_orbital_distribution()
	metrics_data.orbital_distribution.append(distribution)
	
	# Rileva eventi di cascata
	var cascade_detected = detect_cascade_failure(current_time)
	metrics_data.fault_cascade_events.append(cascade_detected)
	
	# Conta timeout heartbeat
	var heartbeat_timeouts = count_heartbeat_timeouts()
	metrics_data.heartbeat_timeouts.append(heartbeat_timeouts)

func count_satellite_states() -> Dictionary:
	var stats = {
		"active": 0,
		"repositioning": 0,
		"falling": 0,
		"removed": 0
	}
	
	for sat in satellite_manager.satellites:
		if sat.removed:
			stats.removed += 1
		elif sat.falling:
			stats.falling += 1
		elif sat.repositioning:
			stats.repositioning += 1
		elif sat.active:
			stats.active += 1

	
	return stats

func calculate_network_connectivity() -> Dictionary:
	var connectivity_data = {
		"total_connections": 0,
		"avg_neighbors": 0.0,
		"isolated_satellites": 0,
		"max_component_size": 0,
		"connectivity_ratio": 0.0
	}
	
	var total_neighbors = 0
	var active_satellites = 0
	
	for sat in satellite_manager.satellites:
		if not sat.active or sat.removed or sat.falling:
			continue
			
		active_satellites += 1
		var neighbor_count = 0
		
		for neighbor_id in sat.neighbors:
			if neighbor_id < satellite_manager.satellites.size():
				var neighbor = satellite_manager.satellites[neighbor_id]
				if neighbor.active and not neighbor.removed and not neighbor.falling:
					neighbor_count += 1
		
		total_neighbors += neighbor_count
		
		if neighbor_count == 0:
			connectivity_data.isolated_satellites += 1
	
	if active_satellites > 0:
		connectivity_data.avg_neighbors = float(total_neighbors) / float(active_satellites)
		connectivity_data.connectivity_ratio = float(active_satellites - connectivity_data.isolated_satellites) / float(active_satellites)
	
	connectivity_data.total_connections = total_neighbors / 2  # Ogni connessione conta doppia
	
	return connectivity_data

func analyze_orbital_distribution() -> Dictionary:
	var distribution = {
		"per_orbit": [],
		"uniformity_index": 0.0,
		"max_gap": 0.0,
		"min_gap": 360.0,
		"total_active_orbits": 0
	}
	
	# Conta satelliti per orbita
	for orbit in range(satellite_manager.orbit_count):
		var active_in_orbit = 0
		var positions = []
		
		for sat in satellite_manager.satellites:
			if sat.orbit_id == orbit and sat.active and not sat.removed and not sat.falling:
				active_in_orbit += 1
				positions.append(rad2deg(sat.theta))
		
		distribution.per_orbit.append(active_in_orbit)
		
		if active_in_orbit > 0:
			distribution.total_active_orbits += 1
		
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
	
	if distribution.per_orbit.size() > 0:
		mean_per_orbit /= distribution.per_orbit.size()
		
		var variance = 0.0
		for count in distribution.per_orbit:
			variance += pow(count - mean_per_orbit, 2)
		variance /= distribution.per_orbit.size()
		
		if mean_per_orbit > 0:
			distribution.uniformity_index = sqrt(variance) / mean_per_orbit
	
	return distribution

func count_heartbeat_timeouts() -> int:
	var timeout_count = 0
	
	if not heartbeat_manager:
		return 0
	
	for sat in satellite_manager.satellites:
		if not sat.active or sat.removed or sat.falling:
			continue
		
		for neighbor_id in sat.neighbors:
			if sat.last_heartbeat.has(neighbor_id):
				if sat.last_heartbeat[neighbor_id] > heartbeat_manager.FAULT_TIMEOUT:
					timeout_count += 1
	
	return timeout_count

func detect_cascade_failure(current_time: float) -> bool:
	# Rileva guasti a cascata: più di 3 guasti in 10 secondi
	var cascade_window = 10.0
	var cascade_threshold = 3
	
	# Rimuovi guasti vecchi dalla lista
	var i = recent_faults.size() - 1
	while i >= 0:
		if current_time - recent_faults[i] > cascade_window:
			recent_faults.remove(i)
		i -= 1
	
	return recent_faults.size() >= cascade_threshold

func export_data():
	# Crea il percorso completo
	var project_path = ProjectSettings.globalize_path("res://")
	var data_path = project_path + data_folder + "/"
	var full_path = data_path + output_file
	
	# Verifica che la cartella esista
	var dir = Directory.new()
	if not dir.dir_exists(data_path):
		print("ATTENZIONE: Cartella data non trovata: ", data_path)
		return
		
	# Apri il file per la scrittura
	var file = File.new()
	if file.open(full_path, File.WRITE) != OK:
		print("Errore nell'aprire il file per la scrittura: ", full_path)
		return
	
	# Aggiungi metadati
	var export_data = {
		"metadata": {
			"simulation_duration": OS.get_ticks_msec() / 1000.0 - simulation_start_time,
			"total_satellites": satellite_manager.total_satellites,
			"orbit_count": satellite_manager.orbit_count,
			"satellites_per_orbit": satellite_manager.satellites_per_orbit,
			"fault_probability": satellite_manager.fault_probability,
			"heartbeat_interval": heartbeat_manager.HEARTBEAT_INTERVAL if heartbeat_manager else 0,
			"fault_timeout": heartbeat_manager.FAULT_TIMEOUT if heartbeat_manager else 0,
			"export_timestamp": OS.get_datetime(),
			"project_path": project_path
		},
		"metrics": metrics_data
	}
	
	file.store_line(JSON.print(export_data))
	file.close()
	print("Dati esportati in: ", full_path)

func export_data_with_timestamp():
	var datetime = OS.get_datetime()
	var timestamp = "%04d%02d%02d_%02d%02d%02d" % [
		datetime.year, datetime.month, datetime.day,
		datetime.hour, datetime.minute, datetime.second
	]
	
	var original_filename = output_file
	output_file = "simulation_data_%s.json" % timestamp
	export_data()
	output_file = original_filename

func export_checkpoint(checkpoint_name: String = "checkpoint"):
	var original_filename = output_file
	output_file = "%s_%s.json" % [checkpoint_name, OS.get_ticks_msec()]
	export_data()
	output_file = original_filename

func _exit_tree():
	if enable_logging:
		export_data()

# Signal handlers
func _on_satellite_failed(satellite_id: int):
	var current_time = OS.get_ticks_msec() / 1000.0 - simulation_start_time
	recent_faults.append(current_time)
	last_fault_time = current_time

func _on_neighbor_fault_detected(satellite_id: int, neighbor_id: int):
	# Registra il rilevamento di fault tramite heartbeat
	var current_time = OS.get_ticks_msec() / 1000.0 - simulation_start_time
	print("DataCollector: Fault rilevato via heartbeat - Sat %d ha rilevato fault in Sat %d" % [satellite_id, neighbor_id])

# Funzioni per analisi in tempo reale
func get_current_fault_rate() -> float:
	if satellite_manager.total_satellites == 0:
		return 0.0
	return float(satellite_manager.fallen_count + satellite_manager.removed_count) / float(satellite_manager.total_satellites)

func get_convergence_time_after_fault() -> float:
	# Tempo medio per stabilizzare la rete dopo un fault
	# Implementazione semplificata - può essere estesa
	if recent_faults.size() == 0:
		return 0.0
	
	var current_time = OS.get_ticks_msec() / 1000.0 - simulation_start_time
	var time_since_last_fault = current_time - last_fault_time
	
	# Se sono passati più di 30 secondi dall'ultimo fault, considera la rete stabile
	if time_since_last_fault > 30.0:
		return time_since_last_fault
	else:
		return 0.0

func get_current_stats() -> Dictionary:
	"""Restituisce statistiche correnti per debug"""
	return {
		"satellite_states": count_satellite_states(),
		"network_connectivity": calculate_network_connectivity(),
		"orbital_distribution": analyze_orbital_distribution(),
		"fault_rate": get_current_fault_rate(),
		"recent_faults": recent_faults.size(),
		"heartbeat_timeouts": count_heartbeat_timeouts()
	}
