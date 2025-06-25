# Gestisce il rendering e la visualizzazione dei satelliti
extends Node
class_name SatelliteRenderer

const BLINK_SPEED = 5.0
const FAILING_COLOR = Color(1.0, 0.0, 0.0)      # Rosso
const REPOSITIONING_COLOR = Color(1.0, 1.0, 0.0) # Giallo
const NORMAL_COLOR = Color(0.0, 1.0, 0.0)        # Verde
const INACTIVE_COLOR = Color(0.5, 0.5, 0.5)      # Grigio
const REMOVAL_TIME = 5.0  # Tempo in secondi prima della rimozione


var multi_mesh_instance: MultiMeshInstance
var simulation_time: float = 0.0
var satellite_timers: Dictionary = {}  # Traccia quanto tempo ogni satellite è inattivo
var removed_satellites: Array = []     # Lista degli indici dei satelliti rimossi


func _ready():
	pass

func setup_multimesh(multimesh_node: MultiMeshInstance, satellite_count: int, mesh_resource: Mesh):
	multi_mesh_instance = multimesh_node
	
	if not multi_mesh_instance:
		printerr("ERRORE: MultiMeshInstance non valido!")
		return false
	
	var mm = MultiMesh.new()
	mm.mesh = mesh_resource
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.color_format = MultiMesh.COLOR_NONE
	mm.custom_data_format = MultiMesh.CUSTOM_DATA_8BIT
	mm.instance_count = satellite_count
	multi_mesh_instance.multimesh = mm
		# Inizializza i timer per ogni satellite
	for i in range(satellite_count):
		satellite_timers[i] = 0.0
	
	return true
func update_autonomous_satellite_visuals(satellite_data: Array, delta: float):
	if not multi_mesh_instance or not multi_mesh_instance.multimesh:
		return
	simulation_time += delta
	var blink_factor = abs(sin(simulation_time * BLINK_SPEED))
	
	for i in range(satellite_data.size()):
		var sat = satellite_data[i]
		
		# Aggiorna timer per satelliti inattivi
		if not sat.active or sat.health <= 0.0:
			satellite_timers[i] += delta
			
			# Se il satellite è stato inattivo troppo a lungo, rimuovilo
			if satellite_timers[i] >= REMOVAL_TIME and not i in removed_satellites:
				remove_satellite_visual(i)
				continue
		else:
			# Reset timer se il satellite è tornato attivo
			satellite_timers[i] = 0.0
		
		# Salta i satelliti già rimossi
		if i in removed_satellites:
			continue
		
		var transform = Transform().translated(sat.position)
		transform.basis = Basis().scaled(Vector3.ONE * 0.3)
		multi_mesh_instance.multimesh.set_instance_transform(i, transform)
		
		# Aggiorna colore basato sullo stato
		var color
		if not sat.active:
			# Grigio inattivi
			color = INACTIVE_COLOR
		elif sat.repositioning:
			# Giallo lampeggiante per satelliti in riposizionamento
			color = REPOSITIONING_COLOR.linear_interpolate(Color(0.5, 0.5, 0), blink_factor)
		elif sat.health < 0.3:
			# Rosso lampeggiante per satelliti in caduta
			color = FAILING_COLOR.linear_interpolate(Color(0.5, 0, 0), blink_factor)
		else:
			# Verde per satelliti normali
			color = NORMAL_COLOR
		multi_mesh_instance.multimesh.set_instance_custom_data(i, color)
		
func remove_satellite_visual(satellite_index: int):
	"""Rimuove visivamente un satellite dalla scena"""
	if satellite_index in removed_satellites:
		return  # Già rimosso
	
	#print("Removing satellite visual for index: ", satellite_index)
	removed_satellites.append(satellite_index)
	
	# Nascondi il satellite spostandolo molto lontano e rendendolo trasparente
	var hidden_transform = Transform().translated(Vector3(0, -1000, 0))
	hidden_transform.basis = Basis().scaled(Vector3.ZERO)
	multi_mesh_instance.multimesh.set_instance_transform(satellite_index, hidden_transform)
	
	# Rendilo completamente trasparente
	var transparent_color = Color(0, 0, 0, 0)
	multi_mesh_instance.multimesh.set_instance_custom_data(satellite_index, transparent_color)

func get_removal_statistics() -> Dictionary:
	"""Restituisce statistiche sui satelliti rimossi"""
	var pending_removal = 0
	
	for satellite_id in satellite_timers:
		if satellite_timers[satellite_id] > REMOVAL_TIME * 0.5 and not satellite_id in removed_satellites:
			pending_removal += 1
	
	return {
		"removed_count": removed_satellites.size(),
		"pending_removal": pending_removal,
		"removal_time_threshold": REMOVAL_TIME
	}

func reset_removal_system():
	"""Resetta il sistema di rimozione (utile per restart della simulazione)"""
	satellite_timers.clear()
	removed_satellites.clear()
	
	if multi_mesh_instance and multi_mesh_instance.multimesh:
		var instance_count = multi_mesh_instance.multimesh.instance_count
		for i in range(instance_count):
			satellite_timers[i] = 0.0

func is_satellite_removed(satellite_index: int) -> bool:
	"""Verifica se un satellite è stato rimosso visivamente"""
	return satellite_index in removed_satellites

func get_inactive_time(satellite_index: int) -> float:
	"""Restituisce per quanto tempo un satellite è stato inattivo"""
	if satellite_index in satellite_timers:
		return satellite_timers[satellite_index]
	return 0.0
#func update_satellite_visuals(satellites: Array, satellite_manager: SatelliteManager, delta: float):
#	if not multi_mesh_instance or not multi_mesh_instance.multimesh:
#		return
#
#	simulation_time += delta
#	var blink_factor = abs(sin(simulation_time * BLINK_SPEED))
#
#	for i in range(satellites.size()):
#		var sat = satellites[i]
#
#		# Salta satelliti completamente rimossi
#		if sat.removed:
#			# Nascondi il satellite
#			var transform = Transform()
#			transform.basis = Basis().scaled(Vector3.ZERO)
#			multi_mesh_instance.multimesh.set_instance_transform(i, transform)
#			continue
#
#		# IMPORTANTE: Aggiorna l'angolo del satellite
#		if sat.active or sat.falling:
#			satellite_manager.satellite_angles[i] += sat.angular_velocity * delta
#			sat.theta = satellite_manager.satellite_angles[i]
#
#		# Calcola posizione
#		var RAAN = deg2rad(sat.orbit_id * 360.0 / satellite_manager.orbit_count)
#		var pos = satellite_manager.orbital_position(
#			satellite_manager.orbit_radius,
#			satellite_manager.orbit_inclination_deg,
#			RAAN,
#			sat.theta
#		)
#
#		# Modifica posizione per satelliti in caduta
#		if sat.falling:
#			var direction_to_center = -pos.normalized()
#			var randomness = Vector3(
#				rand_range(-0.1, 0.1),
#				rand_range(-0.1, 0.1),
#				rand_range(-0.1, 0.1)
#			)
#			var fall_speed = sat.fall_timer * 2.0
#			pos += direction_to_center * fall_speed * delta + randomness * delta
#
#		# Aggiorna transform
#		var transform = Transform().translated(pos)
#		transform.basis = Basis().scaled(Vector3.ONE * 0.3)
#		multi_mesh_instance.multimesh.set_instance_transform(i, transform)
#
#		# Aggiorna colore
#		update_satellite_color(i, sat, blink_factor)

#func update_satellite_color(satellite_index: int, satellite: Dictionary, blink_factor: float):
#	if not multi_mesh_instance or not multi_mesh_instance.multimesh:
#		return
#
#	var color = NORMAL_COLOR
#
#	if satellite.removed:
#		# Non impostare colore per satelliti rimossi
#		return
#	elif satellite.falling:
#		# Rosso lampeggiante per satelliti in caduta
#		color = FAILING_COLOR.linear_interpolate(Color(0.5, 0, 0), blink_factor)
#	elif satellite.repositioning:
#		# Giallo lampeggiante per satelliti in riposizionamento
#		color = REPOSITIONING_COLOR.linear_interpolate(Color(0.5, 0.5, 0), blink_factor)
#	elif satellite.active:
#		# Verde per satelliti normali
#		color = NORMAL_COLOR
#	else:
#		# Grigio per satelliti inattivi
#		color = INACTIVE_COLOR
#
#	multi_mesh_instance.multimesh.set_instance_custom_data(satellite_index, color)
