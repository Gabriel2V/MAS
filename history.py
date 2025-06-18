import numpy as np
import matplotlib.pyplot as plt
from matplotlib.ticker import MaxNLocator
import os

class SimulationAnalyzer:
	def __init__(self, data_file="history.txt"):
		self.data_file = data_file
		self.data = self.load_data()
		self.setup_plot_style()
		
	def load_data(self):
		"""Carica i dati con header migliorato"""
		if not os.path.exists(self.data_file):
			print(f"File {self.data_file} non trovato!")
			return None
			
		return np.genfromtxt(self.data_file, delimiter=",", 
						   names=["latency", "hops", "alive_sats", "uniformity"],
						   dtype=[float, int, int, float])

	def setup_plot_style(self):
		"""Configura lo stile dei grafici"""
		plt.style.use('seaborn')
		plt.rcParams['figure.figsize'] = [10, 6]
		plt.rcParams['font.size'] = 12

	def plot_combined_stats(self):
		"""Grafico combinato con più metriche"""
		if self.data is None:
			return
			
		fig, axs = plt.subplots(2, 2, figsize=(15, 10))
		
		# Grafico 1: Distribuzione dei salti
		unique_hops = np.unique(self.data['hops'])
		colors = plt.cm.viridis(np.linspace(0, 1, len(unique_hops)))
		
		for hop, color in zip(unique_hops, colors):
			axs[0,0].hist(self.data[self.data['hops'] == hop]['hops'], 
						 bins=np.arange(min(unique_hops)-0.5, max(unique_hops)+1.5, 1),
						 color=color, alpha=0.7, label=f'{hop} hops')
		axs[0,0].set_title('Distribution of Satellite Hops')
		axs[0,0].set_xlabel('Number of hops')
		axs[0,0].set_ylabel('Frequency')
		axs[0,0].legend()
		axs[0,0].xaxis.set_major_locator(MaxNLocator(integer=True))

		# Grafico 2: Latenza
		axs[0,1].hist(self.data['latency'] / 3, bins=30, color='turquoise', alpha=0.7)
		axs[0,1].set_title('Connection Latency Distribution')
		axs[0,1].set_xlabel('Milliseconds (ms)')
		axs[0,1].set_ylabel('Frequency')

		# Grafico 3: Satelliti attivi vs Hops
		axs[1,0].scatter(self.data['alive_sats'], self.data['hops'], 
						c=self.data['latency'], cmap='viridis', alpha=0.6)
		axs[1,0].set_title('Active Satellites vs Hops')
		axs[1,0].set_xlabel('Active Satellites')
		axs[1,0].set_ylabel('Number of hops')
		plt.colorbar(axs[1,0].collections[0], ax=axs[1,0], label='Latency (ms)')

		# Grafico 4: Uniformità della distribuzione
		axs[1,1].hist(self.data['uniformity'], bins=20, color='purple', alpha=0.7)
		axs[1,1].set_title('Orbital Distribution Uniformity')
		axs[1,1].set_xlabel('Uniformity Metric (lower is better)')
		axs[1,1].set_ylabel('Frequency')

		plt.tight_layout()
		plt.savefig('combined_metrics.png', dpi=300)
		plt.show()

	def plot_time_series(self):
		"""Analisi temporale delle metriche"""
		if self.data is None:
			return
			
		fig, ax = plt.subplots(figsize=(12, 6))
		
		# Usa l'indice come proxy temporale
		time = np.arange(len(self.data))
		
		ax.plot(time, self.data['alive_sats'], label='Active Satellites', color='green')
		ax.plot(time, self.data['uniformity'], label='Uniformity', color='red')
		ax.set_xlabel('Simulation Step')
		ax.set_ylabel('Metric Value')
		ax.set_title('System Performance Over Time')
		ax.legend()
		
		plt.savefig('time_series.png', dpi=300)
		plt.show()

if __name__ == "__main__":
	analyzer = SimulationAnalyzer()
	analyzer.plot_combined_stats()
	analyzer.plot_time_series()
