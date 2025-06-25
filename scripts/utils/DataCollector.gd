# Gestisce la raccolta e l'esportazione delle metriche di simulazione per satelliti autonomi
extends Node
class_name DataCollector

# Struttura dati per metriche allineata agli obiettivi di ricerca
var metrics_data = {
	"timestamp": [],
	"active_satellites": [],
	"repositioning_satellites": [],
	"degraded_satellites": [],
	"dead_satellites": [],
	"coverage_percentage": [],
	"spatial_distribution": [],
	"stabilization_metrics": [],
	"cascade_failure_events": [],
	"convergence_times": [],
	"network_connectivity": [],
	"orbital_gaps": [],
	"service_continuity": [],
	"geographical_coverage_quality": []
}

# Configurazione logging
export var enable_logging = true
export var log_interval = 1.0  # secondi
export var output_file = "autonomous_satellite_simulation.json"
export var data_folder = "data"  # Nome della cartella

var log_timer = 0.0
var simulation_start_time = 0.0
var last_fault_time = 0.0
var recent_faults = []
var stabilization_start_time = -1.0
var system_stable = true
var last_coverage_values = []

# Riferimenti ai componenti del sistema
var main_node: Main
var satellites: Array
var coverage_manager: CoverageManager
var comm_system: SatelliteCommSystem

# Parametri per analisi di stabilità
const STABILITY_THRESHOLD = 0.05  # Variazione percentuale per considerare il sistema stabile
const STABILITY_WINDOW = 10.0     # Secondi di stabilità richiesti
const CASCADE_WINDOW = 15.0       # Finestra temporale per rilevare guasti a cascata
const CASCADE_THRESHOLD = 3       # Numero minimo di guasti per considerare una cascata

func _ready():
	
	simulation_start_time = OS.get_ticks_msec() / 1000.0
	yield(get_tree(), "idle_frame")  # Aspetta un frame per l'inizializzazione
	# Ottieni riferimenti ai componenti del sistema
	main_node = get_node("/root/Main") if has_node("/root/Main") else get_parent()
	if main_node:
		satellites = main_node.satellites
		coverage_manager = main_node.coverage_manager
		if not coverage_manager:
			print("ERRORE: CoverageManager non trovato!")
		comm_system = main_node.comm_system
	
	print("DataCollector inizializzato per sistema di satelliti autonomi")

func _process(delta):
	if not enable_logging or not main_node:
		return
		
	log_timer += delta
	if log_timer >= log_interval:
		collect_autonomous_metrics()
		log_timer = 0.0

func collect_autonomous_metrics():
	"""Raccoglie metriche specifiche per il sistema autonomo"""
	var current_time = OS.get_ticks_msec() / 1000.0 - simulation_start_time
	
	# 1. Analisi della distribuzione spaziale
	var spatial_analysis = analyze_spatial_distribution()
	
	# 2. Dinamiche di stabilizzazione
	var stabilization_analysis = analyze_stabilization_dynamics(current_time)
	
	# 3. Valutazione della copertura terrestre
	var coverage_analysis = analyze_terrestrial_coverage()
	
	# 4. Resilienza a guasti cascata
	var cascade_analysis = analyze_cascade_resilience(current_time)
	
	# 5. Metriche di base
	var basic_stats = collect_basic_satellite_stats()
	
	# Memorizza tutti i dati
	metrics_data.timestamp.append(current_time)
	metrics_data.active_satellites.append(basic_stats.active)
	metrics_data.repositioning_satellites.append(basic_stats.repositioning)
	metrics_data.degraded_satellites.append(basic_stats.degraded)
	metrics_data.dead_satellites.append(basic_stats.dead)
	
	metrics_data.spatial_distribution.append(spatial_analysis)
	metrics_data.stabilization_metrics.append(stabilization_analysis)
	metrics_data.coverage_percentage.append(coverage_analysis.coverage_percentage)
	metrics_data.service_continuity.append(coverage_analysis.service_continuity)
	metrics_data.geographical_coverage_quality.append(coverage_analysis.geographical_quality)
	metrics_data.cascade_failure_events.append(cascade_analysis)
	
	# Connettività di rete e gap orbitali
	var connectivity = analyze_network_connectivity()
	var orbital_gaps = analyze_orbital_gaps()
	
	metrics_data.network_connectivity.append(connectivity)
	metrics_data.orbital_gaps.append(orbital_gaps)
	
	# Tempo di convergenza (se disponibile)
	var convergence_time = calculate_convergence_time()
	metrics_data.convergence_times.append(convergence_time)

func collect_basic_satellite_stats() -> Dictionary:
	"""Raccoglie statistiche di base sui satelliti"""
	var stats = {
		"active": 0,
		"repositioning": 0,
		"degraded": 0,
		"dead": 0,
		"total": satellites.size()
	}
	
	for satellite in satellites:
		if satellite.active:
			if satellite.repositioning_active and satellite.health_status > 0.3:
				stats.repositioning += 1
			if satellite.health_status > 0.8:
				stats.active += 1
			elif satellite.health_status > 0.3:
				stats.degraded += 1
			else:
				stats.dead += 1
		else:
			stats.dead += 1
	return stats

func analyze_spatial_distribution() -> Dictionary:
	"""Analizza la distribuzione spaziale dei satelliti"""
	var distribution = {
		"orbital_uniformity": 0.0,
		"average_neighbor_distance": 0.0,
		"max_gap_size": 0.0,
		"min_gap_size": 360.0,
		"coverage_holes": 0,
		"redistribution_efficiency": 0.0,
		"satellites_per_orbit": []
	}
	
	# Analizza distribuzione per orbita
	var orbit_counts = {}
	var total_gaps = []
	
	for orbit_id in range(main_node.orbit_count):
		var satellites_in_orbit = []
		orbit_counts[orbit_id] = 0
		
		for satellite in satellites:
			if satellite.orbit_id == orbit_id and satellite.active and satellite.health_status > 0.0:
				satellites_in_orbit.append(rad2deg(satellite.theta))
				orbit_counts[orbit_id] += 1
		
		distribution.satellites_per_orbit.append(orbit_counts[orbit_id])
		
		# Calcola gap tra satelliti in questa orbita
		if satellites_in_orbit.size() > 1:
			satellites_in_orbit.sort()
			for i in range(satellites_in_orbit.size()):
				var next_pos = satellites_in_orbit[(i + 1) % satellites_in_orbit.size()]
				var current_pos = satellites_in_orbit[i]
				var gap = next_pos - current_pos
				if gap < 0:
					gap += 360.0
				
				total_gaps.append(gap)
				distribution.max_gap_size = max(distribution.max_gap_size, gap)
				distribution.min_gap_size = min(distribution.min_gap_size, gap)
	
	# Calcola uniformità orbitale (coefficiente di variazione)
	var mean_per_orbit = 0.0
	for count in distribution.satellites_per_orbit:
		mean_per_orbit += count
	
	if distribution.satellites_per_orbit.size() > 0:
		mean_per_orbit /= distribution.satellites_per_orbit.size()
		
		var variance = 0.0
		for count in distribution.satellites_per_orbit:
			variance += pow(count - mean_per_orbit, 2)
		if distribution.satellites_per_orbit.size() > 1:
			variance /= (distribution.satellites_per_orbit.size() - 1)
		
		if mean_per_orbit > 0:
			distribution.orbital_uniformity = 1.0 - (sqrt(variance) / mean_per_orbit)
	
	# Calcola distanza media tra vicini
	if total_gaps.size() > 0:
		var sum_gaps = 0.0
		for gap in total_gaps:
			sum_gaps += gap
		distribution.average_neighbor_distance = sum_gaps / total_gaps.size()
	
	# Conta buchi di copertura significativi (gap > 50% della spaziatura ideale)
	var ideal_spacing = 360.0 / main_node.satellites_per_orbit
	for gap in total_gaps:
		if gap > ideal_spacing * 1.5:
			distribution.coverage_holes += 1
	
	# Efficienza di ridistribuzione (quanto bene i satelliti si ridistribuiscono)
	var repositioning_count = 0
	var total_repositioning_distance = 0.0
	
	for satellite in satellites:
		if satellite.repositioning_active:
			repositioning_count += 1
			var distance = satellite.angle_distance(satellite.theta, satellite.target_theta)
			total_repositioning_distance += distance
	
	if repositioning_count > 0:
		distribution.redistribution_efficiency = total_repositioning_distance / repositioning_count
	
	return distribution

func analyze_stabilization_dynamics(current_time: float) -> Dictionary:
	"""Analizza le dinamiche di stabilizzazione del sistema"""
	var stabilization = {
		"system_stable": true,
		"time_to_stabilize": 0.0,
		"stability_score": 0.0,
		"repositioning_satellites": 0,
		"convergence_velocity": 0.0,
		"oscillation_detected": false
	}
	
	# Conta satelliti in riposizionamento
	for satellite in satellites:
		if satellite.repositioning_active:
			stabilization.repositioning_satellites += 1
	
	# Determina se il sistema è stabile
	stabilization.system_stable = (stabilization.repositioning_satellites == 0)
	
	# Calcola tempo di stabilizzazione
	if not system_stable and stabilization.system_stable:
		# Sistema appena stabilizzato
		if stabilization_start_time > 0:
			stabilization.time_to_stabilize = current_time - stabilization_start_time
			stabilization_start_time = -1.0
		system_stable = true
	elif system_stable and not stabilization.system_stable:
		# Sistema appena destabilizzato
		stabilization_start_time = current_time
		system_stable = false
	
	# Calcola score di stabilità basato su variazioni recenti
	stabilization.stability_score = calculate_stability_score()
	
	# Rileva oscillazioni nel sistema
	stabilization.oscillation_detected = detect_system_oscillations()
	
	return stabilization

func analyze_terrestrial_coverage() -> Dictionary:
	"""Analizza la copertura terrestre e la qualità del servizio"""
	var coverage_analysis = {
		"coverage_percentage": 0.0,
		"service_continuity": 0.0,
		"geographical_quality": 0.0,
		"polar_coverage": 0.0,
		"equatorial_coverage": 0.0,
		"coverage_stability": 0.0,
		"uncovered_regions": 0
	}
	#print("Coverage Manager disponibile? ", coverage_manager != null)  # Debug
	if coverage_manager:
		# Ottieni statistiche dettagliate sulla copertura
		var coverage_stats = coverage_manager.get_coverage_statistics()
		#print("Dati di copertura: ", coverage_manager.get_coverage_statistics())  # Debug
		coverage_analysis.coverage_percentage = coverage_stats.weighted_coverage
		
		# Analizza copertura per regioni geografiche
		var coverage_by_lat = coverage_stats.coverage_by_latitude
		var polar_coverage_sum = 0.0
		var equatorial_coverage_sum = 0.0
		var polar_count = 0
		var equatorial_count = 0
		
		for lat in coverage_by_lat:
			var lat_coverage = coverage_by_lat[lat]
			if abs(lat) > 60:  # Regioni polari
				polar_coverage_sum += lat_coverage
				polar_count += 1
			elif abs(lat) < 30:  # Regioni equatoriali
				equatorial_coverage_sum += lat_coverage
				equatorial_count += 1
		
		if polar_count > 0:
			coverage_analysis.polar_coverage = polar_coverage_sum / polar_count
		if equatorial_count > 0:
			coverage_analysis.equatorial_coverage = equatorial_coverage_sum / equatorial_count
		
		# Calcola stabilità della copertura
		last_coverage_values.append(coverage_analysis.coverage_percentage)
		if last_coverage_values.size() > 10:
			last_coverage_values.pop_front()
		
		if last_coverage_values.size() > 1:
			var coverage_variance = 0.0
			var coverage_mean = 0.0
			for val in last_coverage_values:
				coverage_mean += val
			coverage_mean /= last_coverage_values.size()
			
			for val in last_coverage_values:
				coverage_variance += pow(val - coverage_mean, 2)
			coverage_variance /= last_coverage_values.size()
			
			# Stabilità è inversamente proporzionale alla varianza
			coverage_analysis.coverage_stability = 1.0 / (1.0 + coverage_variance)
		
		# Regioni non coperte
		var uncovered = coverage_manager.get_uncovered_regions()
		coverage_analysis.uncovered_regions = uncovered.size()
		
		# Continuità del servizio (basata sulla stabilità della copertura)
		coverage_analysis.service_continuity = coverage_analysis.coverage_stability
		
		# Qualità geografica (bilanciamento tra diverse regioni)
		var polar_eq_balance = 1.0 - abs(coverage_analysis.polar_coverage - coverage_analysis.equatorial_coverage) / 100.0
		coverage_analysis.geographical_quality = polar_eq_balance * coverage_analysis.coverage_percentage / 100.0
	
	return coverage_analysis

func analyze_cascade_resilience(current_time: float) -> Dictionary:
	"""Analizza la resilienza del sistema ai guasti a cascata"""
	var cascade_analysis = {
		"cascade_detected": false,
		"cascade_severity": 0.0,
		"affected_orbits": 0,
		"recovery_time": 0.0,
		"system_resilience": 1.0,
		"failure_propagation_rate": 0.0
	}
	
	# Aggiorna lista dei guasti recenti
	update_recent_failures(current_time)
	
	# Rileva guasti a cascata
	if recent_faults.size() >= CASCADE_THRESHOLD:
		cascade_analysis.cascade_detected = true
		cascade_analysis.cascade_severity = float(recent_faults.size()) / CASCADE_THRESHOLD
		
		# Analizza diffusione del guasto tra orbite
		var affected_orbits = {}
		var total_failures = 0
		
		for satellite in satellites:
			if not satellite.active or satellite.health_status <= 0.0:
				affected_orbits[satellite.orbit_id] = true
				total_failures += 1
		
		cascade_analysis.affected_orbits = affected_orbits.size()
		
		# Calcola tasso di propagazione del guasto
		if current_time > 0:
			cascade_analysis.failure_propagation_rate = float(total_failures) / current_time
		
		# Resilienza del sistema (capacità di mantenere servizio durante cascata)
		var active_satellites = 0
		for satellite in satellites:
			if satellite.active and satellite.health_status > 0.0:
				active_satellites += 1
		
		cascade_analysis.system_resilience = float(active_satellites) / float(satellites.size())
	
	return cascade_analysis

func analyze_network_connectivity() -> Dictionary:
	"""Analizza la connettività della rete di satelliti"""
	var connectivity = {
		"average_neighbors": 0.0,
		"isolated_satellites": 0,
		"network_diameter": 0,
		"clustering_coefficient": 0.0,
		"connectivity_ratio": 0.0
	}
	
	var total_neighbors = 0
	var active_satellites = 0
	var isolated_count = 0
	
	for satellite in satellites:
		if not satellite.active or satellite.health_status <= 0.0:
			continue
		
		active_satellites += 1
		var active_neighbor_count = 0
		
		# Conta vicini attivi
		for neighbor_id in [satellite.left_neighbor_id, satellite.right_neighbor_id]:
			if satellite.is_neighbor_active(neighbor_id):
				active_neighbor_count += 1
		
		total_neighbors += active_neighbor_count
		
		if active_neighbor_count == 0:
			isolated_count += 1
	
	if active_satellites > 0:
		connectivity.average_neighbors = float(total_neighbors) / float(active_satellites)
		connectivity.connectivity_ratio = float(active_satellites - isolated_count) / float(active_satellites)
	
	connectivity.isolated_satellites = isolated_count
	
	return connectivity

func analyze_orbital_gaps() -> Dictionary:
	"""Analizza i gap nella copertura orbitale"""
	var gaps_analysis = {
		"max_gap_degrees": 0.0,
		"average_gap": 0.0,
		"critical_gaps": 0,  # Gap > 1.5x spaziatura ideale
		"gap_distribution": []
	}
	
	var all_gaps = []
	var ideal_spacing = 360.0 / main_node.satellites_per_orbit
	
	for orbit_id in range(main_node.orbit_count):
		var positions = []
		
		for satellite in satellites:
			if satellite.orbit_id == orbit_id and satellite.active and satellite.health_status > 0.0:
				positions.append(rad2deg(satellite.theta))
		
		if positions.size() > 1:
			positions.sort()
			for i in range(positions.size()):
				var next_pos = positions[(i + 1) % positions.size()]
				var current_pos = positions[i]
				var gap = next_pos - current_pos
				if gap < 0:
					gap += 360.0
				
				all_gaps.append(gap)
				gaps_analysis.max_gap_degrees = max(gaps_analysis.max_gap_degrees, gap)
				
				if gap > ideal_spacing * 1.5:
					gaps_analysis.critical_gaps += 1
	
	if all_gaps.size() > 0:
		var sum_gaps = 0.0
		for gap in all_gaps:
			sum_gaps += gap
		gaps_analysis.average_gap = sum_gaps / all_gaps.size()
	
	gaps_analysis.gap_distribution = all_gaps
	
	return gaps_analysis

func calculate_stability_score() -> float:
	"""Calcola uno score di stabilità del sistema"""
	var stability = 1.0
	
	# Penalizza per satelliti in riposizionamento
	var repositioning_count = 0
	for satellite in satellites:
		if satellite.repositioning_active:
			repositioning_count += 1
	
	if satellites.size() > 0:
		var repositioning_ratio = float(repositioning_count) / float(satellites.size())
		stability -= repositioning_ratio * 0.5
	
	# Penalizza per variazioni nella copertura
	if last_coverage_values.size() > 2:
		var recent_variance = 0.0
		var recent_mean = 0.0
		var recent_count = min(5, last_coverage_values.size())
		
		for i in range(recent_count):
			recent_mean += last_coverage_values[last_coverage_values.size() - 1 - i]
		recent_mean /= recent_count
		
		for i in range(recent_count):
			var val = last_coverage_values[last_coverage_values.size() - 1 - i]
			recent_variance += pow(val - recent_mean, 2)
		recent_variance /= recent_count
		
		stability -= min(0.3, recent_variance / 100.0)
	
	return max(0.0, stability)

func detect_system_oscillations() -> bool:
	"""Rileva oscillazioni nel sistema"""
	if last_coverage_values.size() < 6:
		return false
	
	# Cerca pattern di oscillazione negli ultimi valori
	var oscillation_threshold = 5.0  # Variazione percentuale
	var oscillations = 0
	
	for i in range(1, min(6, last_coverage_values.size())):
		var current = last_coverage_values[last_coverage_values.size() - i]
		var previous = last_coverage_values[last_coverage_values.size() - i - 1]
		
		if abs(current - previous) > oscillation_threshold:
			oscillations += 1
	
	return oscillations >= 3

func calculate_convergence_time() -> float:
	"""Calcola il tempo di convergenza dopo l'ultimo evento di instabilità"""
	if system_stable and stabilization_start_time > 0:
		var current_time = OS.get_ticks_msec() / 1000.0 - simulation_start_time
		return current_time - stabilization_start_time
	return 0.0

func update_recent_failures(current_time: float):
	"""Aggiorna la lista dei guasti recenti"""
	# Rimuovi guasti vecchi
	var i = recent_faults.size() - 1
	while i >= 0:
		if current_time - recent_faults[i] > CASCADE_WINDOW:
			recent_faults.remove(i)
		i -= 1
	
	# Aggiungi nuovi guasti
	for satellite in satellites:
		if satellite.health_status <= 0.0 and satellite.active:
			# Satellite appena morto
			recent_faults.append(current_time)
			break  # Un guasto per ciclo

func export_comprehensive_data():
	"""Esporta dati completi con metadati estesi"""
	var project_path = ProjectSettings.globalize_path("res://")
	var data_path = project_path + data_folder + "/"
	var full_path = data_path + output_file
	
	# Verifica che la cartella esista
	var dir = Directory.new()
	if not dir.dir_exists(data_path):
		print("ATTENZIONE: Cartella data non trovata: ", data_path)
		return
	
	var file = File.new()
	if file.open(full_path, File.WRITE) != OK:
		print("Errore nell'aprire il file per la scrittura: ", full_path)
		return
	
	# Metadati completi per l'analisi scientifica
	var export_data = {
		"metadata": {
			"simulation_duration": OS.get_ticks_msec() / 1000.0 - simulation_start_time,
			"total_satellites": satellites.size(),
			"orbit_count": main_node.orbit_count,
			"satellites_per_orbit": main_node.satellites_per_orbit,
			"orbit_radius": main_node.orbit_radius,
			"orbit_inclination": main_node.orbit_inclination_deg,
			"walker_constellation_f": main_node.walker_f,
			"export_timestamp": OS.get_datetime(),
			"godot_version": Engine.get_version_info(),
			"simulation_parameters": {
				"log_interval": log_interval,
				"stability_threshold": STABILITY_THRESHOLD,
				"cascade_window": CASCADE_WINDOW,
				"cascade_threshold": CASCADE_THRESHOLD
			}
		},
		"research_objectives": {
			"spatial_distribution_analysis": "Analisi della distribuzione spaziale dei satelliti",
			"stabilization_dynamics": "Dinamiche di stabilizzazione del sistema",
			"terrestrial_coverage": "Valutazione della copertura terrestre",
			"cascade_resilience": "Resilienza a guasti cascata"
		},
		"metrics": metrics_data,
		"final_statistics": get_final_statistics()
	}
	
	file.store_line(JSON.print(export_data))
	file.close()
	print("Dati completi esportati in: ", full_path)

func get_final_statistics() -> Dictionary:
	"""Calcola statistiche finali per il report"""
	var final_stats = {}
	
	if metrics_data.timestamp.size() > 0:
		# Statistiche sui satelliti
		final_stats.max_active_satellites = 0
		final_stats.min_active_satellites = satellites.size()
		final_stats.total_repositioning_events = 0
		
		for i in range(metrics_data.active_satellites.size()):
			final_stats.max_active_satellites = max(final_stats.max_active_satellites, metrics_data.active_satellites[i])
			final_stats.min_active_satellites = min(final_stats.min_active_satellites, metrics_data.active_satellites[i])
			final_stats.total_repositioning_events += metrics_data.repositioning_satellites[i]
		
		# Statistiche sulla copertura
		if metrics_data.coverage_percentage.size() > 0:
			final_stats.max_coverage = 0.0
			final_stats.min_coverage = 100.0
			final_stats.average_coverage = 0.0
			
			for coverage in metrics_data.coverage_percentage:
				final_stats.max_coverage = max(final_stats.max_coverage, coverage)
				final_stats.min_coverage = min(final_stats.min_coverage, coverage)
				final_stats.average_coverage += coverage
			
			final_stats.average_coverage /= metrics_data.coverage_percentage.size()
		
		# Eventi di cascata
		final_stats.total_cascade_events = 0
		for cascade_event in metrics_data.cascade_failure_events:
			if cascade_event.cascade_detected:
				final_stats.total_cascade_events += 1
	
	return final_stats

func export_data():
	"""Wrapper per compatibilità"""
	export_comprehensive_data()

func _exit_tree():
	if enable_logging:
		export_comprehensive_data()

# Funzioni per analisi in tempo reale
func get_current_system_health() -> Dictionary:
	"""Restituisce lo stato di salute corrente del sistema"""
	var health = {
		"active_percentage": 0.0,
		"average_health": 0.0,
		"system_stability": calculate_stability_score(),
		"coverage_percentage": 0.0,
		"network_connectivity": 0.0
	}
	
	if satellites.size() > 0:
		var active_count = 0
		var total_health = 0.0
		
		for satellite in satellites:
			total_health += satellite.health_status
			if satellite.active and satellite.health_status > 0.0:
				active_count += 1
		
		health.active_percentage = float(active_count) / float(satellites.size()) * 100.0
		health.average_health = total_health / float(satellites.size())
	
	if coverage_manager:
		health.coverage_percentage = coverage_manager.estimate_coverage()
	
	var connectivity = analyze_network_connectivity()
	health.network_connectivity = connectivity.connectivity_ratio * 100.0
	
	return health

func debug_print_current_stats():
	"""Stampa statistiche correnti per debug"""
	var health = get_current_system_health()
	print("=== STATO SISTEMA SATELLITI AUTONOMI ===")
	print("Satelliti attivi: %.1f%%" % health.active_percentage)
	print("Salute media: %.2f" % health.average_health)
	print("Stabilità sistema: %.2f" % health.system_stability)
	print("Copertura terrestre: %.1f%%" % health.coverage_percentage)
	print("Connettività rete: %.1f%%" % health.network_connectivity)
	print("Guasti recenti: %d" % recent_faults.size())
	print("==========================================")
