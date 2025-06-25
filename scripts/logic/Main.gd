# Controller principale per sistema di satelliti completamente autonomo
extends Node
class_name Main
export(float, 0.1, 100.0) var simulation_speed := 1.0
export(int) var satellites_per_orbit = 24
export(int) var orbit_count = 36
export(float) var orbit_radius = 70.0
export(float) var orbit_inclination_deg = 53.0
export(int) var walker_f = 12

onready var comm_system: SatelliteCommSystem = $SatelliteCommSystem
onready var satellite_renderer: SatelliteRenderer = $SatelliteRenderer
onready var coverage_manager: CoverageManager = $CoverageManager

onready var multi_mesh_instance := $MultiMeshInstance
onready var option_btn := $Control/SpeedButton
onready var status_label = $Label
onready var coverage_texture_rect = $Control/CoverageMapPanel/CoverageMapTexture

var satellites: Array = []
var simulation_time = 0.0
var stats_refresh_cycles = 0
var stats_refresh_interval = 50

const EARTH_MASS = 5.972e24
const G = 6.674e-11

func _ready():
	setup_ui()
	initialize_autonomous_constellation()

func setup_ui():
	option_btn.clear()
	option_btn.add_item("Stop", 0)
	option_btn.add_item("1x", 1)
	option_btn.add_item("2x", 2)
	option_btn.add_item("10x", 3)
	option_btn.add_item("100x", 4)
	option_btn.select(1)
	option_btn.connect("item_selected", self, "_on_SpeedButton_item_selected")

func initialize_autonomous_constellation():
	"""Inizializa la costellazione di satelliti autonomi"""
	satellites.clear()
	
	var realistic_angular_velocity = calculate_orbital_velocity()
	var satellite_id = 0
	
	for orbit in range(orbit_count):
		for sat_pos in range(satellites_per_orbit):
			var phase_shift = 2 * PI * ((sat_pos + orbit * walker_f) % satellites_per_orbit) / satellites_per_orbit
			
			# Crea satellite autonomo
			var satellite = AutonomousSatellite.new()
			satellite.init(
				satellite_id, 
				orbit,
				sat_pos, 
				phase_shift,
				orbit_radius, 
				orbit_inclination_deg,
				orbit_count)
				
			satellite.angular_velocity = realistic_angular_velocity
			
			
			# Aggiungi alla scena e registra nel sistema di comunicazione
			add_child(satellite)
			comm_system.register_satellite(satellite)
			satellites.append(satellite)
			
			satellite_id += 1
	
	# Setup renderer
	var mesh = preload("res://scenes/Satellite.tres")
	satellite_renderer.setup_multimesh(multi_mesh_instance, satellites.size(), mesh)
	
	# Setup coverage manager
	coverage_manager.setup_ui_texture(coverage_texture_rect)
	
	print("Autonomous constellation initialized with ", satellites.size(), " satellites")

func calculate_orbital_velocity() -> float:
	"""Calcola velocità orbitale realistica"""
	var orbit_radius_real_m = orbit_radius * 1000.0 * 100.0
	var velocity_real_ms = sqrt(G * EARTH_MASS / orbit_radius_real_m)
	var angular_vel_real = velocity_real_ms / orbit_radius_real_m
	return angular_vel_real

func _process(delta):
	simulation_time += delta * simulation_speed   
	# Aggiorna rendering e statistiche
	update_satellite_rendering(delta)
	if stats_refresh_cycles > stats_refresh_interval:
		update_coverage_and_stats()
		stats_refresh_cycles = 0
	else:
		stats_refresh_cycles += 1
		
func update_satellite_rendering(delta: float):
	var satellite_data = []
	for satellite in satellites:
		satellite_data.append({
			"position": satellite.calculate_orbital_position(orbit_radius, orbit_inclination_deg),
			"active": satellite.active,
			"health": satellite.health_status,
			"repositioning": satellite.repositioning_active,
			 "falling": satellite.health_status <= 0.0
			})
	satellite_renderer.update_autonomous_satellite_visuals(satellite_data, delta)
	
func orbital_position(radius: float, inclination_deg: float, RAAN: float, anomaly: float) -> Vector3:
	"""Calcola posizione orbitale 3D"""
	var inclination = deg2rad(inclination_deg)
	var x = radius * cos(anomaly)
	var z = radius * sin(anomaly)
	var y = 0.0
	var pos = Vector3(x, y, z)
	pos = pos.rotated(Vector3(1, 0, 0), inclination)
	pos = pos.rotated(Vector3(0, 1, 0), RAAN)
	return pos

func update_coverage_and_stats():
	"""Aggiorna copertura e statistiche"""
	var stats = calculate_constellation_stats()
	
	# Aggiorna coverage manager con i satelliti attivi
	var active_satellites = []
	for satellite in satellites:
		if satellite.active and satellite.health_status > 0.0:
			active_satellites.append({
				"theta": satellite.theta,
				"orbit_id": satellite.orbit_id,
				"orbit_radius": orbit_radius,
				"orbit_inclination_deg": orbit_inclination_deg,
				"total_orbits": orbit_count,
				"active": true,
				"health_status": satellite.health_status })
#	var  ogg = FuncRef.new()
#	ogg.set_instance(self)
#	ogg.set_function("orbital_position") 

	coverage_manager.update_coverage(active_satellites)
	var coverage_percent = coverage_manager.estimate_coverage()
	
	update_ui(stats, coverage_percent)

func calculate_constellation_stats() -> Dictionary:
	"""Calcola statistiche della costellazione"""
	var stats = {
		"live": 0,
		"repositioning": 0,
		"degraded": 0,
		"dead": 0
	}
	
	for satellite in satellites:
		if satellite.active:
			if satellite.health_status > 0.8:
				stats.live += 1
			elif satellite.health_status > 0.3:
				stats.degraded += 1
			else:
				stats.dead += 1
				
			if satellite.repositioning_active:
				stats.repositioning += 1
		else:
			stats.dead += 1
	
	return stats

func update_ui(stats: Dictionary, coverage_percent: float):
	"""Aggiorna interfaccia utente"""
	var time_string = format_simulation_time(simulation_time)
	var status_text = "Live: %d\nDegraded: %d\nRepositioning: %d\nDead: %d\nSim Time: %s" % [
		stats.live, stats.degraded, stats.repositioning, stats.dead, time_string]
	
	if stats.live == 0:
		status_text += "\n⚠ CONSTELLATION FAILED ⚠"
		simulation_speed = 0.0
	
	status_label.text = status_text
	
	# Aggiorna barra di copertura se esiste
	if has_node("Control/HBoxContainer/ProgressBar"):
		var bar = get_node("Control/HBoxContainer/ProgressBar")
		bar.value = coverage_percent

func format_simulation_time(total_seconds: float) -> String:
	var hours = int(total_seconds) / 3600
	var minutes = (int(total_seconds) % 3600) / 60
	var seconds = int(total_seconds) % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

func _on_SpeedButton_item_selected(index):
	match index:
		0: Engine.time_scale = 0
		1: Engine.time_scale = 1
		2: Engine.time_scale = 2
		3: Engine.time_scale = 10
		4: Engine.time_scale = 100

# Funzioni helper per compatibilità con coverage manager
func get_satellites_per_orbit():
	return satellites_per_orbit

func get_orbit_count():
	return orbit_count
