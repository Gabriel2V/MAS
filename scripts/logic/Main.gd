# Script principale che coordina tutti i manager
extends Node

export(float, 0.1, 100.0) var simulation_speed := 1.0
export(int) var stats_refresh_cycles = 50

onready var satellite_manager: SatelliteManager = $SatelliteManager
onready var coverage_manager: CoverageManager = $CoverageManager
onready var heartbeat_manager: HeartbeatManager = $HeartbeatManager
onready var satellite_renderer: SatelliteRenderer = $SatelliteRenderer

onready var multi_mesh_instance := $MultiMeshInstance
onready var option_btn := $Control/SpeedButton
onready var status_label = $Label
onready var coverage_texture_rect = $Control/CoverageMapPanel/CoverageMapTexture

var simulation_time = 0.0
var cycles_count = 0

func _ready():
	setup_ui()
	setup_managers()
	initialize_simulation()

func setup_ui():
	# Configura il menu di velocità
	option_btn.clear()
	option_btn.add_item("Stop", 0)
	option_btn.add_item("1x", 1)
	option_btn.add_item("2x", 2)
	option_btn.add_item("10x", 3)
	option_btn.add_item("100x", 4)
	option_btn.select(1)
	
	# Collega il signal
	option_btn.connect("item_selected", self, "_on_SpeedButton_item_selected")

func setup_managers():
	# Configura SatelliteManager
	satellite_manager.connect("satellite_failed", self, "_on_satellite_failed")
	satellite_manager.connect("repositioning_started", self, "_on_repositioning_started")
	
	# Configura HeartbeatManager
	heartbeat_manager.connect("neighbor_fault_detected", self, "_on_neighbor_fault_detected")
	
	# Configura CoverageManager
	coverage_manager.setup_ui_texture(coverage_texture_rect)
	
	# Configura SatelliteRenderer
	var mesh = preload("res://scenes/Satellite.tres")
	satellite_renderer.setup_multimesh(multi_mesh_instance, satellite_manager.total_satellites, mesh)

func initialize_simulation():
	var satellites = satellite_manager.initialize_satellites()
	#print("Simulazione inizializzata con ", satellites.size(), " satelliti")

func _process(delta):
	simulation_time += delta * simulation_speed
	delta *= simulation_speed
	
	# Aggiorna satelliti (logica di fault, riposizionamento, caduta)
	var stats = satellite_manager.update_satellites(delta)
	
	# Aggiorna heartbeats
	heartbeat_manager.update_heartbeats(satellite_manager.satellites, delta, simulation_speed)
	
	# Aggiorna rendering (posizioni e colori)
	satellite_renderer.update_satellite_visuals(satellite_manager.satellites, satellite_manager, delta)
	
	# Aggiorna copertura periodicamente
	cycles_count += 1
	if cycles_count > stats_refresh_cycles:
		coverage_manager.update_coverage(satellite_manager.satellites, satellite_manager)
		var coverage_percent = coverage_manager.estimate_coverage()
		update_coverage_ui(coverage_percent)
		cycles_count = 0
	
	# Aggiorna UI
	update_status_ui(stats)
	
	# Controlla se tutti i satelliti sono morti
	check_simulation_end(stats)

func update_status_ui(stats: Dictionary):
	var time_string = format_simulation_time(simulation_time)
	var status_text = "Live satellites: %d\nRepositioning: %d\nFalling: %d\nBurned: %d\nSim Time: %s\n" % [
		stats.live, stats.repositioning, stats.falling, stats.removed, time_string
	]
	
	if stats.live == 0:
		status_text += "\n⚠ ALL SATELLITES DEAD ⚠"
	
	status_label.text = status_text

func update_coverage_ui(coverage_percent: float):
	if has_node("Control/HBoxContainer/ProgressBar"):
		var bar = get_node("Control/HBoxContainer/ProgressBar")
		bar.value = coverage_percent
	
	if has_node("Control/HBoxContainer/CoverageLabel"):
		var lbl = get_node("Control/HBoxContainer/CoverageLabel")
		lbl.text = "Copertura: %.2f%%" % coverage_percent

func check_simulation_end(stats: Dictionary):
	if stats.live == 0:
		simulation_speed = 0.0
		#print("Simulazione terminata: tutti i satelliti sono morti")

func format_simulation_time(total_seconds: float) -> String:
	var hours = int(total_seconds) / 3600
	var minutes = (int(total_seconds) % 3600) / 60
	var seconds = int(total_seconds) % 60
	return "%02d:%02d:%02d" % [hours, minutes, seconds]

# Signal handlers
func _on_SpeedButton_item_selected(index):
	match index:
		0: simulation_speed = 0
		1: simulation_speed = 1
		2: simulation_speed = 2
		3: simulation_speed = 10
		4: simulation_speed = 100

#func _on_satellite_failed(satellite_id: int):
#	print("Satellite ", satellite_id, " failed!")
#
#func _on_repositioning_started(orbit_id: int):
#	print("Riposizionamento iniziato per orbita ", orbit_id)

func _on_neighbor_fault_detected(satellite_id: int, neighbor_id: int):
	# Gestisci il fault del vicino tramite SatelliteManager
	satellite_manager.force_satellite_failure(neighbor_id)
