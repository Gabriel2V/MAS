# Gestisce la logica dei satelliti, orbite e riposizionamento
extends Node
class_name SatelliteManager

signal satellite_failed(satellite_id)
signal repositioning_started(orbit_id)
signal repositioning_completed(satellite_id)

export(int) var satellites_per_orbit = 24
export(int) var orbit_count = 36
export(float) var orbit_radius = 70.00
export(float) var orbit_inclination_deg = 53.0
export(int) var walker_f = 12
export(float) var repositioning_speed_multiplier = 2.0
export(float) var fault_probability = 0.0001

const EARTH_MASS = 5.972e24
const G = 6.674e-11

var satellites = []
var satellite_angles = []
var total_satellites
var live_count = 0
var fallen_count = 0
var removed_count = 0

func _ready():
	total_satellites = satellites_per_orbit * orbit_count

func initialize_satellites() -> Array:
	satellites.clear()
	satellite_angles.clear()
	
	var realistic_angular_velocity = calculate_scaled_angular_velocity()
	var id = 0
	
	for orbit in range(orbit_count):
		var RAAN = deg2rad(orbit * 360.0 / orbit_count)
		for sat in range(satellites_per_orbit):
			var phase_shift = 2 * PI * ((sat + orbit * walker_f) % satellites_per_orbit) / satellites_per_orbit
			var theta = phase_shift
			
			satellite_angles.append(theta)
			
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
				"angular_velocity": realistic_angular_velocity,
				"falling": false,
				"fall_timer": 0.0,
				"repositioning": false,
				"target_theta": 0.0,
				"original_angular_velocity": realistic_angular_velocity,
				"removed": false
			})
			
			id += 1
	
	live_count = total_satellites
	return satellites

func calculate_scaled_angular_velocity() -> float:
	var orbit_radius_real_m = orbit_radius * 1000.0 * 100.0
	var velocity_real_ms = sqrt(G * EARTH_MASS / orbit_radius_real_m)
	var angular_vel_real = velocity_real_ms / orbit_radius_real_m
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

func trigger_satellite_failure(satellite: Dictionary):
	"""Forza il fallimento di un satellite"""
	# FIXED: Check if satellite is already failing to prevent double-processing
	if not satellite.active or satellite.falling:
		return
		
	satellite.active = false
	satellite.falling = true
	satellite.fall_timer = 0.0
	fallen_count += 1
	live_count -= 1
	emit_signal("satellite_failed", satellite.id)

func force_satellite_failure(satellite_id: int):
	"""Funzione pubblica per forzare il fallimento di un satellite specifico"""
	if satellite_id < 0 or satellite_id >= satellites.size():
		return
		
	var sat = satellites[satellite_id]
	# FIXED: More robust state checking
	if sat.active and not sat.falling and not sat.removed:
		trigger_satellite_failure(sat)
		# Avvia riposizionamento per l'orbita affetta
		start_repositioning(sat.orbit_id)

func update_satellites(delta: float) -> Dictionary:
	var orbits_affected = []
	var stats = {"live": 0, "repositioning": 0, "falling": 0, "removed": 0}
	
	for i in range(satellites.size()):
		var sat = satellites[i]
		
		if sat.removed:
			stats.removed += 1
			continue
		
		# Logica di fault casuale - FIXED: More precise conditions
		if sat.active and not sat.falling and not sat.repositioning and randf() < fault_probability * delta:
			trigger_satellite_failure(sat)
			if not (sat.orbit_id in orbits_affected):
				orbits_affected.append(sat.orbit_id)
		
		# Aggiorna riposizionamento
		if sat.repositioning and sat.active and not sat.falling:
			update_repositioning(sat, delta)
		
		# Gestione caduta
		if sat.falling:
			sat.fall_timer += delta
			if sat.fall_timer >= 5.0:
				sat.falling = false
				sat.active = false
				sat.removed = true
				# FIXED: Update counters properly
				if fallen_count > 0:
					fallen_count -= 1
				removed_count += 1
				stats.removed += 1
				continue
		
		# FIXED: More accurate statistics counting
		if sat.active and not sat.falling and not sat.removed:
			stats.live += 1
			if sat.repositioning:
				stats.repositioning += 1
		elif sat.falling and not sat.removed:
			stats.falling += 1
	
	# FIXED: Update global counters
	live_count = stats.live
	
	# Avvia riposizionamento per orbite affette
	for orbit_id in orbits_affected:
		start_repositioning(orbit_id)
	
	return stats

func calculate_optimal_positions(orbit_id: int) -> Array:
	var active_satellites = []
	for sat in satellites:
		if sat.orbit_id == orbit_id and sat.active and not sat.falling and not sat.removed:
			active_satellites.append(sat)
	
	if active_satellites.size() == 0:
		return []
	
	var optimal_positions = []
	var angular_spacing = 2 * PI / active_satellites.size()
	
	var min_angle = active_satellites[0].theta
	for sat in active_satellites:
		if sat.theta < min_angle:
			min_angle = sat.theta
	
	for i in range(active_satellites.size()):
		var optimal_theta = min_angle + i * angular_spacing
		while optimal_theta >= 2 * PI:
			optimal_theta -= 2 * PI
		while optimal_theta < 0:
			optimal_theta += 2 * PI
		optimal_positions.append(optimal_theta)
	
	return optimal_positions

func start_repositioning(orbit_id: int):
	var active_satellites = []
	for sat in satellites:
		if sat.orbit_id == orbit_id and sat.active and not sat.falling and not sat.removed:
			active_satellites.append(sat)
	
	if active_satellites.size() <= 1:
		return
	
	var optimal_positions = calculate_optimal_positions(orbit_id)
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
	
	emit_signal("repositioning_started", orbit_id)

func angle_distance(angle1: float, angle2: float) -> float:
	var diff = abs(angle2 - angle1)
	if diff > PI:
		diff = 2 * PI - diff
	return diff

func update_repositioning(satellite: Dictionary, delta: float):
	if not satellite.repositioning:
		return
	
	var target_theta = satellite.target_theta
	var current_theta = satellite.theta
	
	var diff = target_theta - current_theta
	if diff > PI:
		diff -= 2 * PI
	elif diff < -PI:
		diff += 2 * PI
	
	if abs(diff) < 0.01:
		satellite.repositioning = false
		satellite.angular_velocity = satellite.original_angular_velocity
		emit_signal("repositioning_completed", satellite.id)
		return
	
	var direction = sign(diff)
	var base_velocity = satellite.original_angular_velocity
	satellite.angular_velocity = base_velocity * repositioning_speed_multiplier * direction
