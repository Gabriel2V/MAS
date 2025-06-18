from godot import exposed, export
from godot import *
from datetime import datetime, timedelta
import sys, os
import time
from math import sqrt
import igraph
from dijkstar import Graph, find_path

sys.path.append('res://')

from scripts.extractxyz import extractxyz

sys.path.append('./')

from scripts import MyGlobal as MG


def FindMaxRadius(satellite):
	EARTH_RADIUS = 63.71
	# This offsets for light being unable to pass directly next to earth
	# simulating mountains and molehills
	C = 1	# 100 km
	distance = satellite.get_global_translation().length()
	# distance ** 2 = EARTH_RADIUS ** 2 + x ** 2
	x = sqrt(distance**2 - EARTH_RADIUS**2)
	print(x)
	return x - C


@exposed
class Orbit(Spatial):
	# Aggiungi queste variabili export per configurazione
	simulation_mode = export(bool, default=False)  # True per Walker Delta, False per TLE
	walker_params = export(Dictionary, default={
		'total_sats': 24,
		'num_planes': 3,
		'altitude_km': 550,
		'inclination_deg': 53
	})

	def _ready(self):
		if self.simulation_mode:
			self.initialize_walker_constellation()
		else:
			self.initialize_tle_system()  # Il tuo metodo attuale

	def initialize_walker_constellation(self):
		"""Inizializza la costellazione Walker Delta"""
		earth_radius = 6371  # km
		self.orbit_radius = earth_radius + self.walker_params['altitude_km']
		
		# Calcolo parametri Walker
		sats_per_plane = self.walker_params['total_sats'] // self.walker_params['num_planes']
		phase_step = 360 / self.walker_params['total_sats'] * self.walker_params.get('phase_shift', 1)
		
		for plane in range(self.walker_params['num_planes']):
			plane_node = Spatial.new()
			plane_node.set_name(f"Plane_{plane}")
			
			# Aggiungi qui la logica di posizionamento satelliti
			for sat_num in range(sats_per_plane):
				sat = self.Satellite.instance()
				# Configura posizione iniziale
				angle = 2 * PI * sat_num / sats_per_plane
				phase_offset = deg2rad(phase_step * plane)
				
				# Posiziona il satellite
				sat.angular_position = (angle + phase_offset) % (2 * PI)
				sat.orbit_id = plane
				sat.set_name(f"Walker_{plane}_{sat_num}")
				
				plane_node.add_child(sat)
			
			self.add_child(plane_node)

	def initialize_tle_system(self):
		"""Mantieni la tua attuale implementazione TLE"""
		# Il tuo codice esistente qui
		with open(self.tlefilename, 'r') as file:
			self.tlestring = file.read()
		self.satellitelist = extractxyz(self.tlestring, self.curtime)
		
		print("children count:", self.special_child.get_child_count())
		print("children:", self.special_child.get_children())
		for sat in self.satellitelist:#[:int(len(self.satellitelist)/4)]:
			if sat[1].length() > 67: # 63.71 + 3.3
				self.special_child.add_child(self.spawn_object(sat[1], sat[0]))
			else:
				self.deprecated_sats.append(sat[0])
			
		self.add_child(self.special_child)
		print("children count:", self.special_child.get_child_count())
		Engine.time_scale = 1500	# set relative time of simulation
		
		lowestsat = min(self.special_child.get_children(), key=lambda x : x.get_global_translation().length())
		print('lowestsat h:', lowestsat.get_global_translation().length())
		# Max distance between a ground station and satellites
		self.maxR = FindMaxRadius(lowestsat)
		# Max distance between two satellites
		self.maxD = 2 * self.maxR

		# self.special_child.get_children()
		
		# screenshot test
		#screenshot_name = "user://screenshot_NS" + str(self.iter) + ".png"
		#self.get_viewport().get_texture().get_data().save_png(screenshot_name)


	def _process(self, delta):
		self.iter += 1
		print("debug:", self.iter)
		print("delta:", delta)
		
		self.curtime += timedelta(seconds=delta)
		
		self.satellitelist = extractxyz(self.tlestring, self.curtime)
		
		#for i, sat in enumerate(self.special_child.get_children()):
		#	sat.set_global_translation(self.satellitelist[i][1])
		
		for sat in self.satellitelist:
			name = sat[0]
			pos = sat[1]
			node = self.special_child.get_node(name)
			if node is None:
				continue
			if pos.length() > 67:
				node.set_global_translation(pos)
			else:
				node.queue_free()
				self.deprecated_sats.append(name)
				
		print("debug: sat_count:", self.special_child.get_child_count())
		
		# dijkstra
		# Orbit_graph is a dijkstar Graph
		self.Orbit_graph = Graph(undirected=True)
		self.construct_graph()
		path = find_path(self.Orbit_graph, str(self.Stations[0].get_name()), str(self.Stations[1].get_name()))
		print(path)
		nodenames = path[0]
		#nodenames[0] == 'TelHai'
		#nodenames[-1] == 'NewYork'
		#nodenames[1:-1]

		# draw path
		self.lines_child.queue_free()
		self.lines_child = Spatial.new()
		curnode = self.Stations[0]
		for name in nodenames[1:-1]:
			nextnode = self.special_child.get_node(name)
			if nextnode is None:
				print(f'\t\tdebug: not found:', name)
				for sat in self.satellitelist:
					if sat[0] == name:
						print(f'\t\t\tpos: {sat[1].length()}')
						break
			print(f'\tdebug: {nextnode}')
			self.draw_line(curnode.get_global_translation(),
						  nextnode.get_global_translation())
			curnode = nextnode
		
		nextnode = self.Stations[1]
		self.draw_line(curnode.get_global_translation(),
					  nextnode.get_global_translation())
		self.add_child(self.lines_child)
		
		screenshot_name = "user://screenshot_NS" + str(self.iter) + ".png"
		
		img = self.get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png(screenshot_name)
		
		self.append_history(path)
		#Raccolta metriche
		self.collect_metrics()
	
def collect_metrics(self):
	# Calcola uniformità della distribuzione
	angular_positions = []
	for sat in self.satellites:
		if sat.operational:
			angular_positions.append(sat.angular_position)
	
	angular_positions.sort()
	spacings = [(angular_positions[(i+1)%len(angular_positions)] - angular_positions[i]) % (2*math.pi)
				 for i in range(len(angular_positions))]
	
	uniformity = math.sqrt(sum((s - 2*math.pi/len(angular_positions))**2 for s in spacings) / len(spacings))
	
	# Registra metriche
	with open("metrics.csv", "a") as f:
		f.write(f"{OS.get_system_time_msecs()},{uniformity},{len(angular_positions)}\n")


def append_history(self, path):
	"""Registra dati più completi per l'analisi"""
	total_cost = path[-1]  # Latenza totale
	hops = len(path[0])    # Numero di salti
	
	# Calcola metriche del sistema
	active_sats = sum(1 for sat in self.special_child.get_children() 
					if sat.operational)
	
	# Calcola uniformità (solo in modalità simulazione)
	if self.simulation_mode:
		uniformity = self.calculate_uniformity()
	else:
		uniformity = 0  # Non applicabile per TLE
	
	with open(self.history_file_path, 'a+') as history_file:
		history_file.write(f"{total_cost},{hops},{active_sats},{uniformity}\n")

def calculate_uniformity(self):
	"""Calcola l'uniformità della distribuzione angolare"""
	if not self.simulation_mode:
		return 0
		
	angles = []
	for plane in self.get_children():
		for sat in plane.get_children():
			if sat.operational:
				angles.append(sat.angular_position)
	
	if len(angles) < 2:
		return 0
		
	angles.sort()
	spacings = np.diff(angles + [angles[0] + 2*np.pi])
	ideal_spacing = 2*np.pi / len(angles)
	return np.std(spacings) / ideal_spacing  # Deviazione standard normalizzata


	def _get_line_material(self):
		mat = SpatialMaterial()
		mat.flags_unshaded = True
		mat.vertex_color_use_as_albedo = True
		return mat


	def draw_line(self, pos1, pos2):
		g = ImmediateGeometry.new()
		g.material_override = self._get_line_material()
		g.begin(Mesh.PRIMITIVE_LINES)
		g.set_color(self.LineColor)
		g.add_vertex(pos1)
		g.add_vertex(pos2)
		g.end()
		self.lines_child.add_child(g)


	def construct_graph(self):
		#satellites = self.special_child.get_children()
		for i in range(len(self.satellitelist)):
			if self.satellitelist[i][0] in self.deprecated_sats:
				continue
			Sat1Loc = self.satellitelist[i][1]
			for j in range(len(self.Stations)):
				GrStLoc = self.Stations[j].get_global_translation()
				distance = (Sat1Loc - GrStLoc).length()
				if distance < self.maxR:
					self.Orbit_graph.add_edge(self.satellitelist[i][0], str(self.Stations[j].get_name()), distance)

			for j in range(i+1, len(self.satellitelist)):
				if self.satellitelist[j][0] in self.deprecated_sats:
					continue
				Sat2Loc = self.satellitelist[j][1]
				distance = (Sat1Loc - Sat2Loc).length()
				if distance < self.maxD:
					self.Orbit_graph.add_edge(self.satellitelist[i][0], self.satellitelist[j][0], distance)


	def spawn_object(self, position, name):
		# Create an instance of the scene
		instance = self.Satellite.instance()

		# Set the position of the instance if it's a spatial or 2D node
		instance.set_global_translation(position)	# For 3D

		instance.set_name(name)

		return instance
