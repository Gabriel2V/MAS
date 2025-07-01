extends Node
class_name AutonomousSatellite

# Stato interno del satellite
var satellite_id: int
var orbit_id: int
var position_in_orbit: int
var theta: float
var angular_velocity: float
var original_angular_velocity: float
var active: bool = true
var health_status: float = 1.0  # 0.0 = morto, 1.0 = perfetto
var comm_system: SatelliteCommSystem


onready var simulation_speed = get_node("/root/Main").simulation_speed

# Conoscenza locale limitata
var left_neighbor_id: int = -1
var right_neighbor_id: int = -1
var neighbor_states = {}

# Parametri decisionali autonomi migliorati
var heartbeat_interval: float = 1.0
var heartbeat_timer: float = 0.0
var fault_tolerance_threshold: float = 3.0
var repositioning_threshold: float = 0.25
var desired_spacing: float

# Timer per decisioni autonome
var decision_timer: float = 0.0
var decision_interval: float = 1.5  # Più reattivo

# Stato del riposizionamento
var repositioning_active: bool = false
var target_theta: float = 0.0
var repositioning_speed_multiplier: float = 3.0  # Più veloce

# Anti-glitch control
var last_direction: int = 0
var direction_change_counter: int = 0
const MAX_DIRECTION_CHANGES = 4
const DIRECTION_RESET_TIME = 3.0
var direction_timer: float = 0.0

# Parametri di degrado 
var base_degradation_rate: float = 0.001
var stress_multiplier: float = 1.0  # Aumenta sotto stress
var repair_rate: float = 0.00005    # Auto-riparazione lenta

# Parametri per evitare collisioni
const MIN_SAFE_DISTANCE: float = 0.15  # Distanza minima sicura tra satelliti
const MAX_REPOSITIONING_DISTANCE: float = 0.5  # Massimo movimento consentito

var repositioning_cooldown: float = 10.0
var cooldown_timer: float = 0.0


# Sistema di comunicazione
func get_comm_system() -> SatelliteCommSystem:
	if comm_system:
		return comm_system
	var main = get_tree().root.get_child(0)  # Ottiene Main
	if main.has_node("SatelliteCommSystem"):
		comm_system = main.get_node("SatelliteCommSystem")
		return comm_system
	elif main.has_node("SatelliteCommsystem"):
		comm_system = main.get_node("SatelliteCommsystem")
		return comm_system
	else:
		print("ERRORE: SatelliteCommSystem non trovato!")
		return null


func send_message_to_neighbor(neighbor_id: int, message: Dictionary):
	var comm = get_comm_system()
	if comm:
		comm.send_message(satellite_id, neighbor_id, message)
	else:
		print("ERRORE: Impossibile inviare messaggio da satellite ", satellite_id, " a ", neighbor_id)

# Metriche autonome per decision making
var isolation_level: float = 0.0    # Quanto è isolato dai vicini
var workload_level: float = 0.0     # Carico di lavoro
var stability_score: float = 1.0    # Stabilità dell'orbita locale
var orbit_radius: float
var orbit_inclination_deg: float
var total_orbits: int

func init(id: int, orbit: int, pos_in_orbit: int, initial_theta: float, radius: float, inclination: float, orbits_count: int):
	satellite_id = id
	orbit_id = orbit
	position_in_orbit = pos_in_orbit
	theta = initial_theta
	orbit_radius = radius
	orbit_inclination_deg = inclination
	total_orbits = orbits_count
	
	# Calcola vicini
	var satellites_per_orbit = 24
	left_neighbor_id = orbit * satellites_per_orbit + ((pos_in_orbit - 1 + satellites_per_orbit) % satellites_per_orbit)
	right_neighbor_id = orbit * satellites_per_orbit + ((pos_in_orbit + 1) % satellites_per_orbit)
	
	desired_spacing = 2 * PI / satellites_per_orbit
	
	# Inizializza stato dei vicini
	neighbor_states[left_neighbor_id] = {"active": true, "last_heartbeat": 0.0, "position": initial_theta - desired_spacing, "health": 1.0}
	neighbor_states[right_neighbor_id] = {"active": true, "last_heartbeat": 0.0, "position": initial_theta + desired_spacing, "health": 1.0}
	cooldown_timer = 0.0  # Inizializza il timer di cooldown


func _process(delta: float):
	simulation_speed = get_node("/root/Main").simulation_speed
	
	if health_status <= 0.0:
		if active:
			autonomous_shutdown()
		return
		
	if original_angular_velocity == 0: # never init	Add commentMore actions
		original_angular_velocity = angular_velocity
	
	# 1. Aggiorna metriche interne
	update_internal_metrics(delta * simulation_speed)
	
	# 2. Gestione salute autonoma
	autonomous_health_management(delta * simulation_speed)
	
	# 3. Heartbeat e comunicazione
	autonomous_heartbeat(delta, simulation_speed)
	
	# 4. Decisioni strategiche
	autonomous_decision_making(delta * simulation_speed)
	
	# 5. Movimento orbitale
	autonomous_movement(delta * simulation_speed)

func update_internal_metrics(delta: float):
	"""Aggiorna metriche interne per decision making"""
	# Calcola livello di isolamento
	var active_neighbors = 0
	for neighbor_id in [left_neighbor_id, right_neighbor_id]:
		if is_neighbor_active(neighbor_id):
			active_neighbors += 1
	
	isolation_level = 1.0 - (float(active_neighbors) / 2.0)
	
	# Calcola carico di lavoro (basato su gap da coprire)
	workload_level = isolation_level * 1.5  # Più vicini morti = più lavoro
	
	# Calcola stabilità orbitale locale
	stability_score = calculate_orbital_stability()
	
	# Aggiorna stress multiplier
	stress_multiplier = 1.0 + (isolation_level * 2.0) + (workload_level * 1.5)

func calculate_orbital_stability() -> float:
	"""Calcola quanto è stabile l'orbita locale"""
	var stability = 1.0
	
	# Penalizza se i vicini sono troppo vicini o lontani
	for neighbor_id in [left_neighbor_id, right_neighbor_id]:
		if is_neighbor_active(neighbor_id):
			var neighbor_pos = get_neighbor_position(neighbor_id)
			var distance = angle_distance(theta, neighbor_pos)
			var ideal_distance = desired_spacing
			
			var distance_ratio = distance / ideal_distance
			if distance_ratio < 0.5 or distance_ratio > 1.5:
				stability -= 0.3
	
	return max(0.0, stability)

func autonomous_health_management(delta: float):
	"""Gestione avanzata della salute"""
	# Degrado basato su stress
	var degradation = base_degradation_rate * stress_multiplier * delta
	
	# Degrado casuale
	if randf() < degradation:
		health_status -= rand_range(0.05, 0.15)
		#print("Satellite ", satellite_id, " health degraded to ", health_status)
	
	# Auto-riparazione lenta quando non sotto stress
	if stress_multiplier < 1.2 and health_status < 1.0:
		health_status += repair_rate * delta
		health_status = min(1.0, health_status)
	
	# Fallimento critico
	if health_status <= 0.0:
		autonomous_shutdown()

func autonomous_shutdown():
	"""Procedura di spegnimento autonomo"""
	if not active:
		return
		
	active = false
	#print("Satellite ", satellite_id, " autonomously shutting down (health: ", health_status, ")")
	
	# Informa i vicini prima di morire
	send_failure_notification()

func autonomous_heartbeat(delta: float, simulation_speed: float):
	"""Sistema di heartbeat migliorato"""
	if simulation_speed != 0:
		heartbeat_timer += delta * simulation_speed
	else:
		heartbeat_timer += 0
		
	if heartbeat_timer >= heartbeat_interval:
		send_enhanced_heartbeat()
		heartbeat_timer = 0.0
	
	check_neighbor_timeouts(delta, simulation_speed)

func send_enhanced_heartbeat():
	"""Invia heartbeat con più informazioni"""
	var heartbeat_msg = {
		"type": "heartbeat",
		"sender_id": satellite_id,
		"timestamp": OS.get_ticks_msec(),
		"position": theta,
		"health": health_status,
		"workload": workload_level,
		"stability": stability_score,
		"isolation": isolation_level,
		"repositioning": repositioning_active
	}
	var comm = get_comm_system()
	if comm:
		send_message_to_neighbor(left_neighbor_id, heartbeat_msg)
		send_message_to_neighbor(right_neighbor_id, heartbeat_msg)
	else:
		print("DEBUG: Satellite ", satellite_id, " non può inviare heartbeat - comm system non disponibile")
	#send_message_to_neighbor(left_neighbor_id, heartbeat_msg)
	#send_message_to_neighbor(right_neighbor_id, heartbeat_msg)

func autonomous_decision_making(delta: float):
	"""Sistema decisionale avanzato"""
	decision_timer += delta
	
	if cooldown_timer > 0:
		#print("sim cooldown", cooldown_timer)
		cooldown_timer -= delta * simulation_speed
	
	
	if decision_timer >= decision_interval:
		# Analisi situazione completa
		if cooldown_timer > 0:
			decision_timer = 0.0
			return
		var situation = analyze_comprehensive_situation()
		
		# Prendi decisioni basate sulla situazione
		make_strategic_decisions(situation)
		
		decision_timer = 0.0

func analyze_comprehensive_situation() -> Dictionary:
	"""Analisi completa della situazione locale"""
	var situation = {
		"neighbor_count": 0,
		"average_neighbor_health": 0.0,
		"coverage_gaps": [],
		"overcrowded_areas": [],
		"critical_neighbors": []
	}
	
	var total_health = 0.0
	var active_count = 0
	
	for neighbor_id in [left_neighbor_id, right_neighbor_id]:
		if is_neighbor_active(neighbor_id):
			active_count += 1
			var neighbor_health = get_neighbor_health(neighbor_id)
			total_health += neighbor_health
			
			# Identifica vicini critici
			if neighbor_health < 0.3:
				situation.critical_neighbors.append(neighbor_id)
		else:
			# Gap di copertura
			situation.coverage_gaps.append(neighbor_id)
	
	situation.neighbor_count = active_count
	if active_count > 0:
		situation.average_neighbor_health = total_health / active_count
	
	return situation

func make_strategic_decisions(situation: Dictionary):
	"""Decisioni più intelligenti con controllo anti-collisione"""
	
	# Priorità 1: Coprire gap critici
	if situation.coverage_gaps.size() > 0 and not repositioning_active:
		var optimal_position = calculate_safe_gap_coverage_position(situation.coverage_gaps)
		if optimal_position != -1:  # -1 significa nessuna posizione sicura trovata
			var distance_to_target = angle_distance(theta, optimal_position)
			
			if distance_to_target > desired_spacing * 0.1 and distance_to_target < MAX_REPOSITIONING_DISTANCE:
				start_autonomous_repositioning(optimal_position, "gap_coverage")
			return
	
	# Priorità 2: Supportare vicini critici (solo piccoli aggiustamenti)
	if situation.critical_neighbors.size() > 0 and health_status > 0.7:
		var support_position = calculate_safe_support_position(situation.critical_neighbors)
		if support_position != -1:
			var distance_to_target = angle_distance(theta, support_position)
			
			# Movimenti molto limitati per supporto
			if distance_to_target > desired_spacing * 0.05 and distance_to_target < desired_spacing * 0.3:
				start_autonomous_repositioning(support_position, "neighbor_support")
			return
	
	# Priorità 3: Ottimizzazione distribuzione (solo piccoli aggiustamenti)
	if stability_score < 0.5 and not repositioning_active:
		var balanced_position = calculate_safe_balanced_position()
		if balanced_position != -1:
			var distance_to_target = angle_distance(theta, balanced_position)
			
			if distance_to_target > desired_spacing * 0.05 and distance_to_target < desired_spacing * 0.2:
				start_autonomous_repositioning(balanced_position, "optimization")

func get_all_active_satellite_positions() -> Array:
	"""Ottieni tutte le posizioni dei satelliti attivi conosciuti"""
	var positions = []
	
	# Aggiungi la propria posizione
	positions.append(theta)
	
	# Aggiungi posizioni dei vicini attivi
	for neighbor_id in [left_neighbor_id, right_neighbor_id]:
		if is_neighbor_active(neighbor_id):
			positions.append(get_neighbor_position(neighbor_id))
	
	return positions

func is_position_safe(target_pos: float) -> bool:
	"""Verifica se una posizione è sicura (non troppo vicina ad altri satelliti)"""
	var active_positions = get_all_active_satellite_positions()
	
	for pos in active_positions:
		if pos == theta:  # Salta la propria posizione
			continue
			
		var distance = angle_distance(target_pos, pos)
		if distance < MIN_SAFE_DISTANCE:
			return false
	
	return true

func find_safe_position_in_range(start_pos: float, end_pos: float, steps: int = 10) -> float:
	"""Trova una posizione sicura in un range specificato"""
	var start_normalized = normalize_angle(start_pos)
	var end_normalized = normalize_angle(end_pos)
	
	# Gestisci il caso in cui il range attraversa 0/2π
	var range_size = end_normalized - start_normalized
	if range_size < 0:
		range_size += 2 * PI
	
	var step_size = range_size / steps
	
	for i in range(steps + 1):
		var test_pos = normalize_angle(start_normalized + i * step_size)
		if is_position_safe(test_pos):
			return test_pos
	
	return -1.0  # Nessuna posizione sicura trovata

func calculate_safe_gap_coverage_position(gaps: Array) -> float:
	"""Calcola posizione sicura per coprire gap"""
	if gaps.size() == 0:
		return -1.0
	
	var active_neighbors = []
	for neighbor_id in [left_neighbor_id, right_neighbor_id]:
		if is_neighbor_active(neighbor_id):
			active_neighbors.append({
				"id": neighbor_id,
				"position": get_neighbor_position(neighbor_id)
			})
	
	if active_neighbors.size() == 0:
		# Nessun vicino attivo, cerca una posizione sicura nelle vicinanze
		var search_start = theta - desired_spacing * 0.5
		var search_end = theta + desired_spacing * 0.5
		return find_safe_position_in_range(search_start, search_end)
		
	elif active_neighbors.size() == 1:
		# Un vicino attivo, posizionati nel lato opposto
		var neighbor_pos = active_neighbors[0].position
		var opposite_side = normalize_angle(neighbor_pos + PI)
		
		# Cerca posizione sicura vicino al lato opposto
		var search_start = opposite_side - desired_spacing * 0.5
		var search_end = opposite_side + desired_spacing * 0.5
		return find_safe_position_in_range(search_start, search_end)
		
	else:
		# Due vicini attivi, trova il centro del gap più grande
		var pos1 = active_neighbors[0].position
		var pos2 = active_neighbors[1].position
		
		# Ordina le posizioni
		if pos1 > pos2:
			var temp = pos1
			pos1 = pos2
			pos2 = temp
		
		var gap1 = pos2 - pos1
		var gap2 = (2 * PI) - gap1
		
		var gap_center: float
		if gap1 > gap2:
			gap_center = normalize_angle(pos1 + gap1 / 2.0)
		else:
			gap_center = normalize_angle(pos2 + gap2 / 2.0)
		
		# Verifica se il centro del gap è sicuro
		if is_position_safe(gap_center):
			return gap_center
		
		# Se non è sicuro, cerca nelle vicinanze
		var search_start = gap_center - desired_spacing * 0.3
		var search_end = gap_center + desired_spacing * 0.3
		return find_safe_position_in_range(search_start, search_end)

func calculate_safe_support_position(critical_neighbors: Array) -> float:
	"""Calcola posizione sicura per supportare vicini critici"""
	if critical_neighbors.size() == 0:
		return -1.0
	
	var most_critical_id = critical_neighbors[0]
	var most_critical_health = get_neighbor_health(most_critical_id)
	
	for neighbor_id in critical_neighbors:
		var health = get_neighbor_health(neighbor_id)
		if health < most_critical_health:
			most_critical_health = health
			most_critical_id = neighbor_id
	
	var neighbor_pos = get_neighbor_position(most_critical_id)
	
	# Calcola movimento limitato verso il vicino critico
	var diff = neighbor_pos - theta
	
	# Normalizza la differenza
	if diff > PI:
		diff -= 2 * PI
	elif diff < -PI:
		diff += 2 * PI
	
	# Movimento molto limitato (solo 10% verso il vicino)
	var target = normalize_angle(theta + diff * 0.1)
	
	# Verifica se la posizione è sicura
	if is_position_safe(target):
		return target
	
	return -1.0  # Nessuna posizione sicura trovata

func calculate_safe_balanced_position() -> float:
	"""Calcola posizione bilanciata sicura"""
	var active_neighbors = []
	
	for neighbor_id in [left_neighbor_id, right_neighbor_id]:
		if is_neighbor_active(neighbor_id):
			active_neighbors.append(get_neighbor_position(neighbor_id))
	
	if active_neighbors.size() == 0:
		return -1.0  # Nessun vicino attivo
		
	elif active_neighbors.size() == 1:
		# Posizionati a distanza sicura dall'unico vicino
		var neighbor_pos = active_neighbors[0]
		var target1 = normalize_angle(neighbor_pos + desired_spacing)
		var target2 = normalize_angle(neighbor_pos - desired_spacing)
		
		# Scegli la posizione più vicina che sia sicura
		var dist1 = angle_distance(theta, target1)
		var dist2 = angle_distance(theta, target2)
		
		if dist1 < dist2:
			if is_position_safe(target1):
				return target1
			elif is_position_safe(target2):
				return target2
		else:
			if is_position_safe(target2):
				return target2
			elif is_position_safe(target1):
				return target1
				
	else:
		# Due vicini attivi, posizionati al centro se sicuro
		var center = normalize_angle((active_neighbors[0] + active_neighbors[1]) / 2.0)
		if is_position_safe(center):
			return center
		
		# Se il centro non è sicuro, cerca nelle vicinanze
		var search_start = center - desired_spacing * 0.2
		var search_end = center + desired_spacing * 0.2
		return find_safe_position_in_range(search_start, search_end)
	
	return -1.0

func normalize_angle(angle: float) -> float:
	"""Normalizza un angolo tra 0 e 2π"""
	while angle >= 2 * PI:
		angle -= 2 * PI
	while angle < 0:
		angle += 2 * PI
	return angle

func autonomous_movement(delta: float):
	"""Movimento autonomo migliorato"""
	if repositioning_active:
		execute_repositioning(delta)
	
	# Aggiorna posizione normale
	theta += angular_velocity * delta
	
	# Normalizza angolo
	while theta >= 2 * PI:
		theta -= 2 * PI
	while theta < 0:
		theta += 2 * PI

func execute_repositioning(delta: float):
	"""Esegue movimento di riposizionamento con controllo anti-glitch"""
	var diff = target_theta - theta

	# Normalizza differenza
	if diff > PI:
		diff -= 2 * PI
	elif diff < -PI:
		diff += 2 * PI

	# Anti-glitch: evita loop oscillatori continui
	var direction = sign(diff)
	if direction != last_direction:
		direction_change_counter += 1
		last_direction = direction
		direction_timer = 0.0
	else:
		direction_timer += delta

	if direction_change_counter >= MAX_DIRECTION_CHANGES and direction_timer < DIRECTION_RESET_TIME:
		print("[ANTI-GLITCH] Satellite ", satellite_id, " ha rilevato un loop oscillatorio. Forzato stop.")
		repositioning_active = false
		angular_velocity = original_angular_velocity
		direction_change_counter = 0
		return
	elif direction_timer >= DIRECTION_RESET_TIME:
		direction_change_counter = 0
		direction_timer = 0.0

	if abs(diff) < 0.01:
		# Riposizionamento completato
		repositioning_active = false
		angular_velocity = original_angular_velocity
		print("Satellite ", satellite_id, " completed repositioning")
		# Notifica completamento
		send_repositioning_complete_notification()
	else:
		# Continua movimento verso target
		angular_velocity = original_angular_velocity * repositioning_speed_multiplier * direction

func start_autonomous_repositioning(new_target: float, reason: String):
	"""Inizia riposizionamento autonomo con controlli di sicurezza migliorati"""
	
	# Controlli di sicurezza
	var distance = angle_distance(theta, new_target)
	
	if distance > MAX_REPOSITIONING_DISTANCE:
		print("SAT ", satellite_id, " ABORTING repositioning: distance too large (", rad2deg(distance), "°)")
		return
	
	if not is_position_safe(new_target):
		print("SAT ", satellite_id, " ABORTING repositioning: target position not safe")
		return
	cooldown_timer = repositioning_cooldown
	repositioning_active = true
	target_theta = new_target
	
#	print("SAT ", satellite_id, ": REPOSITIONING START")
#	print("  - Current pos: ", rad2deg(theta), "°")
#	print("  - Target pos: ", rad2deg(new_target), "°")
#	print("  - Distance: ", rad2deg(distance), "°")
#	print("  - Reason: ", reason)
	
	# Notifica intenzione ai vicini
	var intent_msg = {
		"type": "repositioning_intent",
		"sender_id": satellite_id,
		"target_position": target_theta,
		"reason": reason,
		"timestamp": OS.get_ticks_msec()
	}
	
	send_message_to_neighbor(left_neighbor_id, intent_msg)
	send_message_to_neighbor(right_neighbor_id, intent_msg)

func receive_message(message: Dictionary):
	"""Riceve e gestisce messaggi dai vicini"""
	match message.type:
		"heartbeat":
			handle_enhanced_heartbeat(message)
		"failure_notification":
			handle_neighbor_failure(message)
		"repositioning_intent":
			handle_neighbor_repositioning_intent(message)
		"repositioning_complete":
			handle_neighbor_repositioning_complete(message)

func handle_enhanced_heartbeat(message: Dictionary):
	"""Gestisce heartbeat migliorato con più informazioni"""
	var sender_id = message.sender_id
	neighbor_states[sender_id] = {
		"active": true,
		"last_heartbeat": 0.0,  # Reset timer
		"position": message.position,
		"health": message.health,
		"workload": message.get("workload", 0.0),
		"stability": message.get("stability", 1.0),
		"isolation": message.get("isolation", 0.0),
		"repositioning": message.get("repositioning", false)
	}

func check_neighbor_timeouts(delta: float, simulation_speed: float):
	"""Controllo timeout migliorato"""
	for neighbor_id in neighbor_states:
		if simulation_speed != 0:
			neighbor_states[neighbor_id].last_heartbeat += delta / simulation_speed
		else:
			neighbor_states[neighbor_id].last_heartbeat += 0
		if neighbor_states[neighbor_id].last_heartbeat > fault_tolerance_threshold:
			if neighbor_states[neighbor_id].active:
				neighbor_states[neighbor_id].active = false
				#print("Satellite ", satellite_id, " detected neighbor ", neighbor_id, " timeout")

func send_repositioning_complete_notification():
	"""Notifica completamento riposizionamento"""
	var complete_msg = {
		"type": "repositioning_complete",
		"sender_id": satellite_id,
		"final_position": theta,
		"timestamp": OS.get_ticks_msec()
	}
	
	send_message_to_neighbor(left_neighbor_id, complete_msg)
	send_message_to_neighbor(right_neighbor_id, complete_msg)

func angle_distance(angle1: float, angle2: float) -> float:
	"""Calcola distanza minima tra due angoli"""
	var diff = abs(angle2 - angle1)
	if diff > PI:
		diff = 2 * PI - diff
	return diff

func is_neighbor_active(neighbor_id: int) -> bool:
	if neighbor_id in neighbor_states:
		return neighbor_states[neighbor_id].active
	return false

func get_neighbor_position(neighbor_id: int) -> float:
	"""Ottieni posizione del vicino con fallback sicuro"""
	if neighbor_id in neighbor_states and neighbor_states[neighbor_id].active:
		return neighbor_states[neighbor_id].position
	
	# Restituisci la posizione teorica iniziale
	var satellites_per_orbit = 24
	var neighbor_pos_in_orbit = neighbor_id % satellites_per_orbit
	var my_pos_in_orbit = position_in_orbit
	
	if neighbor_id == left_neighbor_id:
		var left_pos_in_orbit = (my_pos_in_orbit - 1 + satellites_per_orbit) % satellites_per_orbit
		return (left_pos_in_orbit * 2 * PI) / satellites_per_orbit
	elif neighbor_id == right_neighbor_id:
		var right_pos_in_orbit = (my_pos_in_orbit + 1) % satellites_per_orbit
		return (right_pos_in_orbit * 2 * PI) / satellites_per_orbit
	
	# Fallback: posizione teorica basata sull'ID
	return (neighbor_pos_in_orbit * 2 * PI) / satellites_per_orbit

func get_neighbor_health(neighbor_id: int) -> float:
	if neighbor_id in neighbor_states:
		return neighbor_states[neighbor_id].get("health", 0.0)
	return 0.0

func send_failure_notification():
	"""Invia notifica di fallimento imminente"""
	var failure_msg = {
		"type": "failure_notification",
		"sender_id": satellite_id,
		"final_health": health_status,
		"timestamp": OS.get_ticks_msec()
	}
	
	send_message_to_neighbor(left_neighbor_id, failure_msg)
	send_message_to_neighbor(right_neighbor_id, failure_msg)

func handle_neighbor_failure(message: Dictionary):
	"""Gestisce fallimento di un vicino"""
	var failed_neighbor = message.sender_id
	if failed_neighbor in neighbor_states:
		neighbor_states[failed_neighbor].active = false
		neighbor_states[failed_neighbor].health = 0.0
		
		# Reagisci al fallimento solo se non già in riposizionamento
		if not repositioning_active: 
			var situation = { "coverage_gaps": [failed_neighbor], "critical_neighbors": [] }
			make_strategic_decisions(situation)

func handle_neighbor_repositioning_intent(message: Dictionary):
	"""Gestisce intenzione di riposizionamento del vicino"""
	var neighbor_id = message.sender_id
	var neighbor_target = message.target_position
	var reason = message.get("reason", "unknown")
	
	# Verifica potenziali collisioni e adatta comportamento
	if angle_distance(neighbor_target, theta) < MIN_SAFE_DISTANCE:
		print("Satellite ", satellite_id, " WARNING: potential collision with neighbor ", neighbor_id)
		# Potrebbe decidere di aspettare o modificare la propria strategia

func handle_neighbor_repositioning_complete(message: Dictionary):
	"""Gestisce completamento riposizionamento del vicino"""
	var neighbor_id = message.sender_id
	var final_position = message.final_position
	
	# Aggiorna conoscenza della posizione del vicino
	if neighbor_id in neighbor_states:
		neighbor_states[neighbor_id].position = final_position
		neighbor_states[neighbor_id].repositioning = false


func calculate_orbital_position(radius: float, inclination_deg: float) -> Vector3:
	"""Calcola la posizione orbitale 3D in modo autonomo"""
	var inclination = deg2rad(inclination_deg)
	var RAAN = deg2rad(orbit_id * 360.0 / total_orbits)
	
	var x = radius * cos(theta)
	var z = radius * sin(theta)
	var y = 0.0
	var pos = Vector3(x, y, z)
	pos = pos.rotated(Vector3(1, 0, 0), inclination)
	pos = pos.rotated(Vector3(0, 1, 0), RAAN)
	return pos

func autonomous_coverage_check():
	"""Verifica autonomamente la copertura della propria area"""
	var pos = calculate_orbital_position(orbit_radius, orbit_inclination_deg)
	# Logica semplificata per verificare la copertura
	return health_status > 0.7 and active
	
# AGGIUNTA: Funzione di debug per identificare problemi
func debug_repositioning_decision(reason: String, target: float):
	"""Debug per identificare movimenti anomali"""
	var distance = angle_distance(theta, target)
	var distance_deg = rad2deg(distance)
	
	print("SAT ", satellite_id, " - REPOSITIONING DEBUG:")
	print("  Current: ", rad2deg(theta), "°")
	print("  Target: ", rad2deg(target), "°")
	print("  Distance: ", distance_deg, "°")
	print("  Reason: ", reason)
	print("  Desired spacing: ", rad2deg(desired_spacing), "°")
	
	# Controlla se il movimento è ragionevole
	if distance_deg > 45.0:  # Più di 45° è probabilmente un errore
		print("  WARNING: Movement too large! Investigating...")
		
		# Debug dei vicini
		print("  Neighbors:")
		for neighbor_id in [left_neighbor_id, right_neighbor_id]:
			if neighbor_id in neighbor_states:
				var state = neighbor_states[neighbor_id]
				print("    ", neighbor_id, ": active=", state.active, " pos=", rad2deg(state.position), "° health=", state.get("health", 0.0))
			else:
				print("    ", neighbor_id, ": NOT IN STATES")
