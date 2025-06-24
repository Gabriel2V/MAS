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
			# Aggiungi un piccolo delay randomico per simulare latenza
			var delay = rand_range(0.05, 0.15)
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
