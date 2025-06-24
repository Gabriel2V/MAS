# Gestisce il sistema di heartbeat tra satelliti
extends Node
class_name HeartbeatManager

signal neighbor_fault_detected(satellite_id, neighbor_id)

const HEARTBEAT_INTERVAL = 1.0  # secondi
const FAULT_TIMEOUT = 3.0  # secondi

func update_heartbeats(satellites: Array, delta: float, simulation_speed: float):
	for sat in satellites:
		# FIXED: Skip satellites that are not fully operational
		if not sat.active or sat.removed or sat.falling:
			continue
		
		# Aggiorna timer heartbeat
		if simulation_speed != 0:
			sat.heartbeat_timer += delta / simulation_speed
		
		# Aggiorna timeout per ogni vicino
		for neighbor_id in sat.neighbors:
			if simulation_speed != 0:
				sat.last_heartbeat[neighbor_id] += delta / simulation_speed
		
		# Invia heartbeat ogni HEARTBEAT_INTERVAL secondi
		if sat.heartbeat_timer >= HEARTBEAT_INTERVAL:
			send_heartbeat(sat, satellites)
			sat.heartbeat_timer = 0.0
		
		# Controlla timeout dei vicini
		check_neighbor_timeouts(sat, satellites)

func send_heartbeat(satellite: Dictionary, satellites: Array):
	for neighbor_id in satellite.neighbors:
		if neighbor_id < satellites.size():
			var neighbor = satellites[neighbor_id]
			# FIXED: Only send heartbeat to fully operational neighbors
			if neighbor.active and not neighbor.removed and not neighbor.falling:
				neighbor.last_heartbeat[satellite.id] = 0.0

func check_neighbor_timeouts(satellite: Dictionary, satellites: Array):
	for neighbor_id in satellite.neighbors:
		if neighbor_id >= satellites.size():
			continue
			
		var neighbor = satellites[neighbor_id]
		
		# FIXED: More robust fault detection conditions
		if satellite.last_heartbeat[neighbor_id] > FAULT_TIMEOUT:
			# Only detect fault if neighbor appears to be active but isn't responding
			if neighbor.active and not neighbor.falling and not neighbor.removed:
				print("⚠ Satellite ", satellite.id, " detects fault in neighbor ", neighbor_id)
				emit_signal("neighbor_fault_detected", satellite.id, neighbor_id)
				
				# Reset del timer per evitare detection multiple
				satellite.last_heartbeat[neighbor_id] = 0.0
