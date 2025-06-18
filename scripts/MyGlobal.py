from godot import exposed, export
from godot import Node
# Costanti temporali
SECOND = 1
MINUTE = 60 * SECOND
HOUR = 60 * MINUTE
DAY = 24 * HOUR

# Parametri simulazione
TIME = MINUTE
HEARTBEAT_INTERVAL = 5 * SECOND
HEARTBEAT_TIMEOUT = 3 * HEARTBEAT_INTERVAL
CONTROL_GAIN = 0.01  # Guadagno per controllo proporzionale
