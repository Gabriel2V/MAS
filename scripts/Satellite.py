from godot import exposed, export
from godot import *
import sys
import math

sys.path.append('./')
from scripts import MyGlobal as MG

@exposed
class Satellite(Spatial):
	# Stato del satellite
	operational = True
	neighbors = {}  # {id: (last_heartbeat, angular_position)}
	target_angular_spacing = 0
	current_angular_velocity = 0
	
	def _ready(self):
		# Inizializza parametri orbitali
		self.orbit_id = self.get_parent().get_name()  # Assume parent è l'orbita
		self.angular_position = self.calculate_initial_angle()
		self.heartbeat_timer = 0
		
	def _physics_process(self, delta):
		if not self.operational:
			return
			
		# Aggiorna posizione
		self.angular_position += self.current_angular_velocity * delta
		self.update_3d_position()
		
		# Gestione heartbeat
		self.heartbeat_timer += delta
		if self.heartbeat_timer >= MG.HEARTBEAT_INTERVAL:
			self.send_heartbeats()
			self.check_neighbors()
			self.heartbeat_timer = 0
			
		# Regolazione posizione
		self.adjust_spacing()
	
	def update_3d_position(self):
		# Converti posizione angolare in coordinate 3D
		orbit_radius = self.get_parent().radius
		x = orbit_radius * math.cos(self.angular_position)
		z = orbit_radius * math.sin(self.angular_position)
		self.set_translation(Vector3(x, 0, z))
	
	def send_heartbeats(self):
		# Invia heartbeat ai vicini
		for neighbor_id, (_, _) in self.neighbors.items():
			neighbor = self.get_parent().get_node(neighbor_id)
			if neighbor:
				neighbor.receive_heartbeat(self.get_name(), self.angular_position)
	
	def receive_heartbeat(self, sender_id, sender_angle):
		# Registra l'heartbeat ricevuto
		self.neighbors[sender_id] = (OS.get_ticks_msec(), sender_angle)
	
	def check_neighbors(self):
		# Verifica neighbors mancanti
		current_time = OS.get_ticks_msec()
		for neighbor_id, (last_time, _) in list(self.neighbors.items()):
			if current_time - last_time > MG.HEARTBEAT_TIMEOUT:
				self.handle_neighbor_failure(neighbor_id)
	
	def handle_neighbor_failure(self, neighbor_id):
		# Gestisci guasto vicino
		self.neighbors.pop(neighbor_id, None)
		self.recalculate_spacing()
	
	def recalculate_spacing(self):
		# Calcola nuova spaziatura ottimale
		active_sats = len(self.get_parent().get_children()) - len(
			[sat for sat in self.get_parent().get_children() if not sat.operational])
		self.target_angular_spacing = 2 * math.pi / active_sats
	
	def adjust_spacing(self):
		# Controllo proporzionale per regolare la velocità
		if len(self.neighbors) < 2:
			return
			
		# Calcola errori di spaziatura con i vicini
		left_neighbor_angle = min([pos for _, pos in self.neighbors.values()])
		right_neighbor_angle = max([pos for _, pos in self.neighbors.values()])
		
		error_left = (self.angular_position - left_neighbor_angle) % (2*math.pi) - self.target_angular_spacing
		error_right = (right_neighbor_angle - self.angular_position) % (2*math.pi) - self.target_angular_spacing
		
		# Regola velocità per ridurre l'errore
		self.current_angular_velocity += MG.CONTROL_GAIN * (error_left + error_right)
