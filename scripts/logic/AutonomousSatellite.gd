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

# Parametri di degrado 
var base_degradation_rate: float = 0.001
var stress_multiplier: float = 1.0  # Aumenta sotto stress
var repair_rate: float = 0.00005    # Auto-riparazione lenta

var registered = false

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
	

func _process(delta: float):
	# Registra il satellite nel sistema di comunicazione
	if not registered:
		get_comm_system().register_satellite(self)
		registered = true
	
	simulation_speed = get_node("/root/Main").simulation_speed
	
	if health_status <= 0.0:
		if active:
			autonomous_shutdown()
		return
	
	if original_angular_velocity == 0: # never init	
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

# Funzione modificata per l'autonomous shutdown con inoltro del vicino sopravvissuto
func autonomous_shutdown():
	if not active:
		return

	active = false
	print("Satellite ", satellite_id, " shutting down. Notifying neighbors.")

	# Invia notifica di fallimento con suggerimento su nuovo vicino
	if is_neighbor_active(left_neighbor_id):
		var msg = {
			"type": "neighbor_replacement",
			"sender_id": satellite_id,
			"replacing_neighbor": left_neighbor_id,
			"direction": "right",
			"timestamp": OS.get_ticks_msec()
		}
		send_message_to_neighbor(right_neighbor_id, msg)

	if is_neighbor_active(right_neighbor_id):
		var msg = {
			"type": "neighbor_replacement",
			"sender_id": satellite_id,
			"replacing_neighbor": right_neighbor_id,
			"direction": "left",
			"timestamp": OS.get_ticks_msec()
		}
		send_message_to_neighbor(left_neighbor_id, msg)

	# Invia comunque notifica di fallimento
	send_failure_notification()
	
# Nuova funzione: ricezione messaggi di sostituzione vicino
func handle_neighbor_replacement(message: Dictionary):
	"ricezione messaggi di sostituzione vicino"
	var direction = message.get("direction", "")
	var replacement_id = message.get("replacing_neighbor", -1)

	if replacement_id == -1 or not (replacement_id in neighbor_states):
		return

	print("Satellite ", satellite_id, " aggiorna ", direction, " neighbor con: ", replacement_id)

	if direction == "left":
		left_neighbor_id = replacement_id
	elif direction == "right":
		right_neighbor_id = replacement_id

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
	send_message_to_neighbor(left_neighbor_id, heartbeat_msg)
	send_message_to_neighbor(right_neighbor_id, heartbeat_msg)

func autonomous_decision_making(delta: float):
	"""Sistema decisionale avanzato"""
	decision_timer += delta
	
	if decision_timer >= decision_interval:
		# Analisi situazione completa
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
	"""Prende decisioni strategiche basate sulla situazione"""
	# Priorità 1: Coprire gap critici
	if situation.coverage_gaps.size() > 0 and not repositioning_active:
		var optimal_position = calculate_gap_coverage_position(situation.coverage_gaps, neighbor_states)
		if angle_distance(theta, optimal_position) > desired_spacing * 0.2:
			start_autonomous_repositioning(optimal_position, "gap_coverage")
		return
	
	# Priorità 2: Supportare vicini critici
	if situation.critical_neighbors.size() > 0 and health_status > 0.7:
		var support_position = calculate_support_position(situation.critical_neighbors)
		if angle_distance(theta, support_position) > desired_spacing * 0.15:
			start_autonomous_repositioning(support_position, "neighbor_support")
		return
	
	# Priorità 3: Ottimizzazione distribuzione
	if stability_score < 0.5 and not repositioning_active:
		var balanced_position = calculate_balanced_position()
		if angle_distance(theta, balanced_position) > desired_spacing * 0.1:
			start_autonomous_repositioning(balanced_position, "optimization")

func calculate_gap_coverage_position(gaps: Array, neighbor_states: Dictionary) -> float:
	"""Calcola lo spostamento necessario per coprire un gap creatosi dal fallimento di un satellite vicino.
	
	Args:
		gaps: Array contenente gli ID dei satelliti mancanti (gap)
		neighbor_states: Dizionario con {sat_id: {position: float, ...}} degli stati dei vicini
		
	Returns:
		float: Lo spostamento da applicare alla posizione corrente (delta)
	"""
	
	# Se non ci sono gap, nessuno spostamento necessario
	if gaps.size() == 0:
		return 0.0
	
	# Per ogni gap rilevato
	for gap_id in gaps:
		# Verifica che il gap sia tra i nostri vicini conosciuti
		if not (gap_id in neighbor_states):
			continue
		
		# Trova i vicini attivi adiacenti al gap
		var active_neighbors = []
		for neighbor_id in neighbor_states.keys():
			if neighbor_id == gap_id:
				continue
			if is_neighbor_active(neighbor_id):
				active_neighbors.append(neighbor_id)
		
		# Se abbiamo esattamente due vicini attivi (uno per lato)
		if active_neighbors.size() == 2:
			var left_id = active_neighbors[0]
			var right_id = active_neighbors[1]
			
			# Ordina i vicini per posizione
			if neighbor_states[left_id].position > neighbor_states[right_id].position:
				var temp = left_id
				left_id = right_id
				right_id = temp
			
			# Calcola la nuova posizione di equilibrio
			var total_distance = neighbor_states[right_id].position - neighbor_states[left_id].position
			var target_distance = total_distance / 3.0
			
			# Se siamo il satellite di sinistra, ci spostiamo a destra
			if self.satellite_id == left_id:
				return target_distance - (neighbor_states[gap_id].position - neighbor_states[left_id].position)
			
			# Se siamo il satellite di destra, ci spostiamo a sinistra
			elif self.satellite_id == right_id:
				return (neighbor_states[gap_id].position - neighbor_states[right_id].position) - target_distance
	
	# Caso default: nessuno spostamento necessario
	return 0.0



func calculate_support_position(critical_neighbors: Array) -> float:
	"""Calcola posizione per supportare vicini critici"""
	if critical_neighbors.size() == 0:
		return theta
	
	# Avvicinati al vicino più critico
	var most_critical_id = critical_neighbors[0]
	var most_critical_health = get_neighbor_health(most_critical_id)
	
	for neighbor_id in critical_neighbors:
		var health = get_neighbor_health(neighbor_id)
		if health < most_critical_health:
			most_critical_health = health
			most_critical_id = neighbor_id
	
	var neighbor_pos = get_neighbor_position(most_critical_id)
	return theta + (neighbor_pos - theta) * 0.3  # Avvicinati del 30%

func calculate_balanced_position() -> float:
	"""Calcola posizione bilanciata ottimale"""
	var active_neighbors = []
	
	for neighbor_id in [left_neighbor_id, right_neighbor_id]:
		if is_neighbor_active(neighbor_id):
			active_neighbors.append(get_neighbor_position(neighbor_id))
	
	if active_neighbors.size() == 0:
		return theta  # Rimani dove sei
	elif active_neighbors.size() == 1:
		# Posizionati a distanza ottimale dall'unico vicino
		return active_neighbors[0] + desired_spacing
	else:
		# Posizionati al centro tra i vicini
		return (active_neighbors[0] + active_neighbors[1]) / 2.0

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
	#print("ang vel", angular_velocity)
	#print("og ang vel", original_angular_velocity)
	"""Esegue movimento di riposizionamento"""
	var diff = target_theta - theta
	
	# Normalizza differenza
	if diff > PI:
		diff -= 2 * PI
	elif diff < -PI:
		diff += 2 * PI
	
	if abs(diff) < 0.01:
		# Riposizionamento completato
		repositioning_active = false
		angular_velocity = original_angular_velocity
		print("Satellite ", satellite_id, " completed repositioning")
		
		# Notifica completamento
		send_repositioning_complete_notification()
	else:
		# Continua movimento verso target
		var direction = sign(diff)
		angular_velocity = original_angular_velocity * repositioning_speed_multiplier * direction

func start_autonomous_repositioning(new_target: float, reason: String):
	"""Inizia riposizionamento autonomo con ragione"""
	repositioning_active = true
	target_theta = new_target
	
	#print("Satellite ", satellite_id, " starting repositioning for: ", reason, " to ", rad2deg(target_theta), "°")
	
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
	match message.type:
		"failure_notification":
			handle_neighbor_failure(message)
		"heartbeat":
			handle_enhanced_heartbeat(message)
		"repositioning_intent":
			handle_neighbor_repositioning_intent(message)
		"repositioning_complete":
			handle_neighbor_repositioning_complete(message)
		"neighbor_replacement":
			handle_neighbor_replacement(message)

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
	if neighbor_id in neighbor_states:
		return neighbor_states[neighbor_id].position
	# Invece di restituire theta, calcola una posizione stimata
	if neighbor_id == left_neighbor_id:
		return theta - desired_spacing
	elif neighbor_id == right_neighbor_id:
		return theta + desired_spacing
	return theta

func get_neighbor_health(neighbor_id: int) -> float:
	if neighbor_id in neighbor_states:
		return neighbor_states[neighbor_id].get("health", 0.0)
	return 0.0

func send_failure_notification():
	var failure_msg_left = {
		"type": "failure_notification",
		"sender_id": satellite_id,
		"final_health": health_status,
		"replacement_hint": {
			"new_neighbor": right_neighbor_id  # per il satellite a sinistra
		},
		"timestamp": OS.get_ticks_msec()
	}

	var failure_msg_right = {
		"type": "failure_notification",
		"sender_id": satellite_id,
		"final_health": health_status,
		"replacement_hint": {
			"new_neighbor": left_neighbor_id  # per il satellite a destra
		},
		"timestamp": OS.get_ticks_msec()
	}

	send_message_to_neighbor(left_neighbor_id, failure_msg_left)
	send_message_to_neighbor(right_neighbor_id, failure_msg_right)

func handle_neighbor_failure(message: Dictionary):
	var failed_neighbor = message.sender_id
	var replacement = message.get("replacement_hint", {}).get("new_neighbor", -1)

	print("Satellite", satellite_id, "ha ricevuto notifica di fallimento da", failed_neighbor, "→ nuovo vicino suggerito:", replacement)

	if failed_neighbor in neighbor_states:
		neighbor_states[failed_neighbor].active = false
		neighbor_states[failed_neighbor].health = 0.0

	# Aggiorna i riferimenti ai vicini se necessario
	if failed_neighbor == left_neighbor_id:
		left_neighbor_id = replacement
		print("Satellite", satellite_id, "→ nuovo left_neighbor:", left_neighbor_id)
	elif failed_neighbor == right_neighbor_id:
		right_neighbor_id = replacement
		print("Satellite", satellite_id, "→ nuovo right_neighbor:", right_neighbor_id)

	# Se non siamo già in riposizionamento, reagisci
	if not repositioning_active and active and health_status > 0.3:
		var situation = {
			"coverage_gaps": [failed_neighbor],
			"critical_neighbors": []
		}
		make_strategic_decisions(situation)


func handle_neighbor_repositioning_intent(message: Dictionary):
	"""Gestisce intenzione di riposizionamento del vicino"""
	var neighbor_id = message.sender_id
	var neighbor_target = message.target_position
	var reason = message.get("reason", "unknown")
	
	# Evita collisioni adattando il proprio comportamento
	#if abs(neighbor_target - theta) < desired_spacing * 0.3:
		#print("Satellite ", satellite_id, " avoiding collision with neighbor ", neighbor_id)
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
