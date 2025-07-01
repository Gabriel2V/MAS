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
var current_repositioning_reason: String = ""
var repositioning_retry_timer: float = 0.0
var retry_repositioning_target: float = 0.0
var safety_check_timer: float = 0.0
const SAFETY_CHECK_INTERVAL: float = 0.5  # Controlla ogni 0.5 secondi
var emergency_stop_active: bool = false
var path_blocked_timer: float = 0.0
const MAX_PATH_BLOCKED_TIME: float = 3.0
var repositioning_start_time: int = 0
const MAX_REPOSITIONING_TIME: int = 30000  # 30 secondi massimo

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
	
	# Gestione retry riposizionamento
	if repositioning_retry_timer > 0:
		repositioning_retry_timer -= delta
		if repositioning_retry_timer <= 0:
			# Riprova il riposizionamento se la posizione è ora sicura
			if not repositioning_active and is_position_safe(retry_repositioning_target):
				start_autonomous_repositioning(retry_repositioning_target, current_repositioning_reason)

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
	# Controlla distanza da tutti i satelliti conosciuti
	var positions = [theta]  # La mia posizione
	
	# Posizioni dei vicini diretti
	for neighbor_id in neighbor_states:
		if neighbor_states[neighbor_id].active:
			positions.append(neighbor_states[neighbor_id].position)
			# Se il vicino ha un target, considera anche quello
			if neighbor_states[neighbor_id].get("repositioning", false):
				var target = neighbor_states[neighbor_id].get("target_position", 0.0)
				positions.append(target)
	for pos in positions:
		if pos != theta and angle_distance(target_pos, pos) < MIN_SAFE_DISTANCE:
			return false
	
	
	# Controlla se altri satelliti stanno convergendo verso questa posizione
	for neighbor_id in neighbor_states:
		if neighbor_states[neighbor_id].get("repositioning", false):
			var neighbor_target = neighbor_states[neighbor_id].get("target_position", 0.0)
			if angle_distance(target_pos, neighbor_target) < MIN_SAFE_DISTANCE * 2:
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
	"""Esegue movimento di riposizionamento con controllo anti-glitch e controlli periodici"""
	
	safety_check_timer += delta
	if safety_check_timer >= SAFETY_CHECK_INTERVAL:
		if not perform_continuous_safety_check():
			return  # Movimento interrotto per sicurezza
		safety_check_timer = 0.0
	
	if emergency_stop_active:
		handle_emergency_stop(delta)
		return
	
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
		#print("[ANTI-GLITCH] Satellite ", satellite_id, " ha rilevato un loop oscillatorio. Forzato stop.")
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
		emergency_stop_active = false
		angular_velocity = original_angular_velocity
		path_blocked_timer = 0.0
		#print("Satellite ", satellite_id, " completed repositioning")
		# Notifica completamento
		send_repositioning_complete_notification()
	else:
		# Continua movimento verso target
		# Controllo percorso
		if is_immediate_path_blocked(direction):
			handle_blocked_path(delta)
			return
		var safe_velocity = calculate_safe_movement_velocity(direction, diff)
		angular_velocity = safe_velocity

func start_autonomous_repositioning(new_target: float, reason: String):
	"""Inizia riposizionamento autonomo con controlli di sicurezza migliorati"""
	
	# Controlli di sicurezza
	var distance = angle_distance(theta, new_target)
	
	if distance > MAX_REPOSITIONING_DISTANCE:
		#print("SAT ", satellite_id, " ABORTING repositioning: distance too large (", rad2deg(distance), "°)")
		return
	
	if not is_position_safe(new_target):
		#print("SAT ", satellite_id, " ABORTING repositioning: target position not safe")
		return
	cooldown_timer = repositioning_cooldown
	repositioning_active = true
	target_theta = new_target
	repositioning_start_time = OS.get_ticks_msec()  # NUOVO: traccia inizio
	emergency_stop_active = false  # NUOVO: reset emergenza
	path_blocked_timer = 0.0  # NUOVO: reset timer blocco
	
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
	current_repositioning_reason = reason  # Salva la ragione
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
		"collision_avoidance":
			handle_collision_avoidance_notification(message)
		"priority_claim":
			handle_priority_claim(message)

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
	var timestamp = message.get("timestamp", 0)
	
	# Aggiorna stato del vicino
	if neighbor_id in neighbor_states:
		neighbor_states[neighbor_id].repositioning = true
		neighbor_states[neighbor_id].target_position = neighbor_target
	
	# Verifica potenziali collisioni
	var collision_distance = angle_distance(neighbor_target, theta)
	var future_collision_distance = calculate_future_collision_risk(neighbor_id, neighbor_target)
	
	if collision_distance < MIN_SAFE_DISTANCE or future_collision_distance < MIN_SAFE_DISTANCE:
		#print("Satellite ", satellite_id, " COLLISION RISK detected with neighbor ", neighbor_id)
		execute_collision_avoidance(neighbor_id, neighbor_target, reason)

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

func calculate_future_collision_risk(neighbor_id: int, neighbor_target: float) -> float:
	"""Calcola il rischio di collisione considerando le traiettorie future"""
	if not (neighbor_id in neighbor_states):
		return PI  # Distanza massima se non conosco il vicino
	
	var neighbor_current = neighbor_states[neighbor_id].position
	var my_future_pos = theta
	
	# Se sono anch'io in riposizionamento, usa la mia posizione target
	if repositioning_active:
		my_future_pos = target_theta
	
	# Simula il movimento del vicino verso il target
	var steps = 10
	var min_distance = PI
	
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		var neighbor_pos = lerp_angle(neighbor_current, neighbor_target, t)
		var distance = angle_distance(neighbor_pos, my_future_pos)
		min_distance = min(min_distance, distance)
	
	return min_distance

func execute_collision_avoidance(neighbor_id: int, neighbor_target: float, neighbor_reason: String):
	"""Esegue manovre di evasione collisione"""
	
	# Strategia 1: Se il vicino ha priorità più alta, mi sposto io
	var i_have_priority = should_i_have_priority(neighbor_id, neighbor_reason)
	
	if not i_have_priority:
		var safe_position = find_collision_avoidance_position(neighbor_target)
		if safe_position != -1:
			#print("Satellite ", satellite_id, " executing collision avoidance maneuver")
			start_autonomous_repositioning(safe_position, "collision_avoidance")
			
			# Invia notifica di evasione
			send_collision_avoidance_notification(neighbor_id, safe_position)
		else:
			# Se non trovo posizione sicura, aspetto che il vicino completi
			#print("Satellite ", satellite_id, " WAITING for neighbor ", neighbor_id, " to complete repositioning")
			pause_repositioning_until_clear(neighbor_id)
	else:
		# Ho priorità, chiedo al vicino di aspettare
		send_priority_claim_message(neighbor_id)

func should_i_have_priority(neighbor_id: int, neighbor_reason: String) -> bool:
	"""Determina chi ha priorità in caso di conflitto"""
	
	# Priorità per ragioni critiche
	var critical_reasons = ["gap_coverage", "emergency_repositioning"]
	var my_reason = get_current_repositioning_reason()
	
	# Se sto coprendo un gap critico, ho priorità
	if my_reason in critical_reasons and not neighbor_reason in critical_reasons:
		return true
	
	# Se il vicino copre gap critico e io no, lui ha priorità
	if neighbor_reason in critical_reasons and not my_reason in critical_reasons:
		return false
	
	# Se entrambi hanno ragioni critiche o non critiche, usa l'ID
	# ID più basso ha priorità (per evitare deadlock)
	return satellite_id < neighbor_id

func find_collision_avoidance_position(neighbor_target: float) -> float:
	"""Trova una posizione sicura per evitare collisioni"""
	
	# Calcola tutte le posizioni occupate/target
	var occupied_positions = []
	occupied_positions.append(neighbor_target)  # Posizione target del vicino
	
	# Aggiungi posizioni di altri vicini attivi
	for neighbor_id in neighbor_states:
		if neighbor_states[neighbor_id].active and neighbor_id != neighbor_target:
			occupied_positions.append(neighbor_states[neighbor_id].position)
			if neighbor_states[neighbor_id].get("repositioning", false):
				var target_pos = neighbor_states[neighbor_id].get("target_position", 0.0)
				occupied_positions.append(target_pos)
	
	# Cerca posizione sicura in cerchi concentrici attorno alla posizione attuale
	var search_radii = [desired_spacing * 0.5, desired_spacing * 0.8, desired_spacing * 1.2]
	
	for radius in search_radii:
		for angle_offset in [0, PI/4, -PI/4, PI/2, -PI/2, 3*PI/4, -3*PI/4, PI]:
			var candidate_pos = normalize_angle(theta + angle_offset * radius / desired_spacing)
			
			if is_position_globally_safe(candidate_pos, occupied_positions):
				return candidate_pos
	
	return -1.0  # Nessuna posizione sicura trovata
	
func send_collision_avoidance_notification(neighbor_id: int, avoidance_position: float):
	"""Notifica al vicino che sto eseguendo evasione"""
	var avoidance_msg = {
		"type": "collision_avoidance",
		"sender_id": satellite_id,
		"avoiding_neighbor": neighbor_id,
		"avoidance_position": avoidance_position,
		"timestamp": OS.get_ticks_msec()
	}
	
	send_message_to_neighbor(neighbor_id, avoidance_msg)
	
func pause_repositioning_until_clear(blocking_neighbor_id: int):
	"""Mette in pausa il riposizionamento fino a quando il vicino non è libero"""
	if repositioning_active:
		repositioning_active = false
		angular_velocity = original_angular_velocity
		#print("Satellite ", satellite_id, " paused repositioning due to neighbor ", blocking_neighbor_id)
		
		# Imposta un timer per riprovare
		set_repositioning_retry_timer(5.0)  # Riprova tra 5 secondi

func send_priority_claim_message(neighbor_id: int):
	"""Rivendica priorità e chiede al vicino di aspettare"""
	var priority_msg = {
		"type": "priority_claim",
		"sender_id": satellite_id,
		"target_neighbor": neighbor_id,
		"my_reason": get_current_repositioning_reason(),
		"timestamp": OS.get_ticks_msec()
	}
	
	send_message_to_neighbor(neighbor_id, priority_msg)
	
func get_current_repositioning_reason() -> String:
	"""Ottieni la ragione del riposizionamento corrente"""
	# Variabile di istanza aggiornata quando inizia il riposizionamento
	return current_repositioning_reason if current_repositioning_reason else "optimization"

func is_position_globally_safe(pos: float, occupied_positions: Array) -> bool:
	"""Verifica se una posizione è sicura rispetto a tutte le posizioni occupate"""
	for occupied_pos in occupied_positions:
		if angle_distance(pos, occupied_pos) < MIN_SAFE_DISTANCE:
			return false
	return true

func set_repositioning_retry_timer(delay: float):
	"""Imposta timer per riprovare il riposizionamento"""
	repositioning_retry_timer = delay
	retry_repositioning_target = target_theta
	
func lerp_angle(from: float, to: float, weight: float) -> float:
	"""Interpolazione lineare tra angoli considerando la natura circolare"""
	var diff = to - from
	
	# Normalizza la differenza
	if diff > PI:
		diff -= 2 * PI
	elif diff < -PI:
		diff += 2 * PI
	
	return normalize_angle(from + diff * weight)
	
func handle_collision_avoidance_notification(message: Dictionary):
	"""Gestisce notifica di evasione collisione"""
	var avoiding_satellite = message.sender_id
	#print("Satellite ", satellite_id, " received collision avoidance notification from ", avoiding_satellite)
	
	# Il vicino si sta spostando per evitarmi, posso continuare con sicurezza
	# Ma tengo traccia della sua nuova posizione
	if avoiding_satellite in neighbor_states:
		neighbor_states[avoiding_satellite].target_position = message.avoidance_position

func handle_priority_claim(message: Dictionary):
	"""Gestisce rivendicazione di priorità"""
	var claiming_satellite = message.sender_id
	var their_reason = message.get("my_reason", "unknown")
	
	# Valuta se accettare la loro priorità
	if not should_i_have_priority(claiming_satellite, their_reason):
		#print("Satellite ", satellite_id, " yielding priority to ", claiming_satellite)
		pause_repositioning_until_clear(claiming_satellite)
	#else:
		#print("Satellite ", satellite_id, " maintaining priority over ", claiming_satellite)
		# Continua con il proprio riposizionamento

func perform_continuous_safety_check() -> bool:
	"""Esegue controlli di sicurezza durante il movimento"""
	# 1. Verifica se il target è ancora sicuro
	if not is_position_safe(target_theta):
		trigger_emergency_stop("target_unsafe")
		return false
	
	# 2. Verifica satelliti in avvicinamento
	var approaching_satellites = detect_approaching_satellites()
	if approaching_satellites.size() > 0:
		#print("Satellite ", satellite_id, " detected ", approaching_satellites.size(), " approaching satellites")
		if not handle_approaching_satellites(approaching_satellites):
			return false
	
	# 3. Verifica stato di salute
	if health_status < 0.3:
		#print("Satellite ", satellite_id, " health too low for complex maneuvers - EMERGENCY STOP")
		trigger_emergency_stop("low_health")
		return false
	
	# 4. Verifica tempo massimo di riposizionamento
	var repositioning_time = OS.get_ticks_msec() - repositioning_start_time
	if repositioning_time > MAX_REPOSITIONING_TIME:
		#print("Satellite ", satellite_id, " repositioning taking too long - EMERGENCY STOP")
		trigger_emergency_stop("timeout")
		return false
	
	return true

func detect_approaching_satellites() -> Array:
	"""Rileva satelliti che si stanno avvicinando alla mia posizione o percorso"""
	var approaching = []
	var my_velocity_direction = sign(angular_velocity)
	
	for neighbor_id in neighbor_states:
		if not neighbor_states[neighbor_id].active:
			continue
			
		var neighbor_pos = neighbor_states[neighbor_id].position
		var distance = angle_distance(theta, neighbor_pos)
		
		# Se è molto vicino, è un problema
		if distance < MIN_SAFE_DISTANCE * 2:
			approaching.append({
				"id": neighbor_id,
				"position": neighbor_pos,
				"distance": distance,
				"threat_level": "immediate"
				})
			continue
		 
		# Se si sta muovendo e il percorso si incrocia con il mio
		if neighbor_states[neighbor_id].get("repositioning", false):
			var neighbor_target = neighbor_states[neighbor_id].get("target_position", neighbor_pos)
			if will_paths_intersect(theta, target_theta, neighbor_pos, neighbor_target):
				approaching.append({
					"id": neighbor_id,
					"position": neighbor_pos,
					"target": neighbor_target,
					"distance": distance,
					"threat_level": "path_intersection"
					})
	return approaching

func will_paths_intersect(my_start: float, my_end: float, their_start: float, their_end: float) -> bool:
	"""Verifica se due percorsi orbitali si intersecheranno"""
	
	# Normalizza tutti gli angoli
	my_start = normalize_angle(my_start)
	my_end = normalize_angle(my_end)
	their_start = normalize_angle(their_start)
	their_end = normalize_angle(their_end)
	
	# Simula il movimento in piccoli step per verificare intersezioni
	var steps = 20
	var my_path = []
	var their_path = []
	
	for i in range(steps + 1):
		var t = float(i) / float(steps)
		my_path.append(lerp_angle(my_start, my_end, t))
		their_path.append(lerp_angle(their_start, their_end, t))
	
	# Verifica se i percorsi si avvicinano troppo
	for i in range(my_path.size()):
		for j in range(their_path.size()):
			if angle_distance(my_path[i], their_path[j]) < MIN_SAFE_DISTANCE:
				return true
	
	return false

func handle_approaching_satellites(approaching: Array) -> bool:
	"""Gestisce satelliti in avvicinamento"""
	
	for sat_info in approaching:
		var threat_level = sat_info.threat_level
		var sat_id = sat_info.id
		
		match threat_level:
			"immediate":
				# Minaccia immediata - stop di emergenza
				#print("Satellite ", satellite_id, " IMMEDIATE THREAT from ", sat_id, " - EMERGENCY STOP")
				trigger_emergency_stop("immediate_collision_risk")
				return false
			"path_intersection":
				# Percorsi che si incrociano - negozia o evita
				if should_i_have_priority(sat_id, "path_intersection"):
					# Ho priorità, continuo ma rallento
				#	print("Satellite ", satellite_id, " maintaining course but slowing down")
					repositioning_speed_multiplier = min(repositioning_speed_multiplier, 1.5)
				else:
					# Non ho priorità, rallento tanto
				#	print("Satellite ", satellite_id, " yielding right of way to ", sat_id)
					repositioning_speed_multiplier =  min(repositioning_speed_multiplier, 1)
	return true

func is_immediate_path_blocked(direction: int) -> bool:
	"""Verifica se il percorso immediato è bloccato"""
	var next_position = normalize_angle(theta + direction * angular_velocity * 0.1)  # Posizione tra 0.1 secondi
	
	for neighbor_id in neighbor_states:
		if neighbor_states[neighbor_id].active:
			var neighbor_pos = neighbor_states[neighbor_id].position
			if angle_distance(next_position, neighbor_pos) < MIN_SAFE_DISTANCE:
				return true
	return false

func handle_blocked_path(delta: float):
	"""Gestisce percorso bloccato"""
	path_blocked_timer += delta
	
	if path_blocked_timer > MAX_PATH_BLOCKED_TIME:
		trigger_emergency_stop("path_permanently_blocked")
	else:
		# Rallenta e aspetta
		angular_velocity = original_angular_velocity * 0.3 * sign(target_theta - theta)
		#print("Satellite ", satellite_id, " path temporarily blocked - slowing down")

func calculate_safe_movement_velocity(direction: int, diff: float) -> float:
	"""Calcola velocità sicura basata sulla situazione attuale"""
	var base_velocity = original_angular_velocity * repositioning_speed_multiplier * direction
	
	
	# Rallenta quando si avvicina al target
	var distance_to_target = abs(diff)
	var approach_factor = min(1.0, distance_to_target / (desired_spacing * 0.5))
	
	# Rallenta se la salute è bassa
	var health_factor = max(0.3, health_status)
	
	return base_velocity * approach_factor * health_factor

func trigger_emergency_stop(reason: String):
	"""Attiva stop di emergenza"""
	emergency_stop_active = true
	angular_velocity = original_angular_velocity
	repositioning_active = false
	
	#print("Satellite ", satellite_id, " EMERGENCY STOP: ", reason)
	
	# Informa i vicini
	var emergency_msg = {
		"type": "emergency_stop",
		"sender_id": satellite_id,
		"reason": reason,
		"position": theta,
		"timestamp": OS.get_ticks_msec()
		}
	send_message_to_neighbor(left_neighbor_id, emergency_msg)
	send_message_to_neighbor(right_neighbor_id, emergency_msg)
	
	# Imposta cooldown più lungo per emergenze
	cooldown_timer = repositioning_cooldown * 2

func handle_emergency_stop(delta: float):
	"""Gestisce stato di emergenza"""
	# Aspetta un po' prima di riprovare
	if cooldown_timer <= 0:
		emergency_stop_active = false
		#print("Satellite ", satellite_id, " emergency resolved - ready for new decisions")
