# Sistema di comunicazione tra i nodi Satellite
extends Node
class_name SatelliteCommSystem

# Usa un sistema debole per evitare reference cycles
var satellites = {}  # {id: WeakRef}

func register_satellite(satellite: Node):
	satellites[satellite.satellite_id] = weakref(satellite)

func send_message(sender_id: int, receiver_id: int, message: Dictionary):
	if receiver_id in satellites:
		var satellite_ref = satellites[receiver_id]
		if satellite_ref.get_ref():
			# Ottieni la velocità di simulazione dal Main
			var main = get_tree().root.get_child(0)
			var simulation_speed = 1.0
			if main and main.has_method("get_simulation_speed"):
				simulation_speed = main.get_simulation_speed()
			# Aggiungi un delay randomico scalato in base alla velocità di simulazione
			var base_delay = rand_range(0.05, 0.15)
			var delay = base_delay / max(1.0, simulation_speed)  # Assicurati che il delay non sia mai negativo
			get_tree().create_timer(delay).connect(
				"timeout", 
				self, 
				"_deliver_message", 
				[receiver_id, message],
				CONNECT_ONESHOT
			)

func _deliver_message(receiver_id: int, message: Dictionary):
	var satellite_ref = satellites.get(receiver_id)
	if satellite_ref and satellite_ref.get_ref():
		satellite_ref.get_ref().receive_message(message)
