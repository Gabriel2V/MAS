# Low Earth Orbit Satellite Constellation
## Sistema Multi-Agente per Costellazioni Satellitari Autonome e Resilienti

[![Godot](https://img.shields.io/badge/Godot-3.6-blue)](https://godotengine.org/)

## 📖 Panoramica

Questo progetto implementa una simulazione 3D di un sistema multi-agente per la modellazione di costellazioni satellitari autonome in orbita terrestre bassa (LEO), con particolare focus sulla resilienza ai guasti e la capacità di auto-riorganizzazione.

Il sistema simula satelliti operanti a circa 630 km di altitudine, modellati come agenti autonomi capaci di prendere decisioni indipendenti per mantenere la copertura ottimale anche in presenza di guasti.

## 🎯 Obiettivi del Progetto

- **Analisi della distribuzione spaziale**: Valutazione dell'efficacia degli algoritmi di riorganizzazione autonoma
- **Dinamiche di stabilizzazione**: Quantificazione dei tempi di convergenza dopo eventi di fault
- **Valutazione della copertura terrestre**: Analisi della continuità del servizio durante e dopo i guasti
- **Resilienza a guasti cascata**: Test della robustezza in scenari di stress estremo
- **Validazione realistica**: Confronto con costellazioni operative come Starlink

## 🏗️ Architettura del Sistema

### Componenti Principali

#### `Main.gd`
Controller principale del sistema che gestisce:
- Inizializzazione della costellazione con pattern Walker Delta
- Velocità di simulazione (0x-100x)
- Coordinamento tra sottosistemi di rendering, comunicazione e copertura
- Calcolo delle statistiche globali
- Interfaccia utente

#### `AutonomousSatellite.gd`
Cuore del sistema ad agenti, implementa:
- **Stati operativi**: ACTIVE, REPOSITIONING, FAILING, INACTIVE
- **Sistema di heartbeat**: Comunicazione inter-satellitare per monitoraggio stato
- **Algoritmi di decisione autonoma**: Basati su analisi dello stato interno e dei vicini
- **Modello di degrado stocastico**: Simulazione realistica dell'usura e auto-riparazione
- **Riposizionamento dinamico**: Algoritmi di adattamento per colmare gap orbitali

#### `SatelliteCommSystem.gd`
Middleware di comunicazione che gestisce:
- Instradamento messaggi tra agenti vicini
- Protocolli di comunicazione avanzati
- Topologia di rete dinamica
- Registro dei satelliti attivi

#### `SatelliteRenderer.gd`
Sistema di rendering ottimizzato:
- Utilizzo di MultiMeshInstance per migliaia di satelliti
- **Colorazione dinamica degli stati**:
  - 🟢 Verde: Operativo
  - 🟡 Giallo lampeggiante: Riposizionamento
  - 🔴 Rosso lampeggiante: Degradato
  - ⚫ Grigio: Inattivo
- Animazioni di caduta e rimozione graduale

#### `CoverageManager.gd`
Sistema di valutazione della copertura terrestre:
- **Griglia discreta**: Risoluzione 25° x 25° (14x7 celle)
- **Ponderazione geografica**: Compensazione deformazione sferica con peso coseno(latitudine)
- **Calcolo copertura**: Funzione di distanza euclidea 3D con raggio 10.0 km
- **Precisione geometrica**: Coordinate cartesiane tridimensionali

#### `DataCollector.gd`
Modulo di raccolta e analisi dati sperimentali:
- **Campionamento continuo**: Metriche raccolte ogni secondo (configurabile)
- **Diverse metriche raccolte**: Stati satelliti, copertura, distribuzione spaziale
- **Analisi connettività**: Numero medio vicini, satelliti isolati, rapporto connettività
- **Rilevamento guasti cascata**: Finestra 15 secondi, soglia minima 3 guasti
- **Esportazione automatica**: Dati in formato JSON con metadati completi

#### Componenti Aggiuntivi
- **`Earth.gd`**: Simulazione rotazione terrestre (24 ore virtuali)
- **`CameraReactiveScript.gd`**: Sistema di controllo camera interattivo

## 🚀 Caratteristiche Principali

### Sistema Multi-Agente
- Ogni satellite opera come agente autonomo
- Capacità sensoriali, decisionali e attuative distribuite
- Emergenza di comportamenti complessi da regole locali semplici

### Resilienza ai Guasti
- Auto-riorganizzazione in caso di guasti singoli o multipli
- Algoritmi di riposizionamento dinamico
- Mantenimento della copertura ottimale locale

### Simulazione Realistica
- Parametri orbitali accurati per LEO
- Modelli di degrado e riparazione stocastici
- Pattern Walker Delta per distribuzione iniziale

### Comunicazione Inter-Satellitare
- Protocolli di heartbeat per monitoraggio stato
- Topologia di rete dinamica
- Riduzione requisiti comunicazione terra-spazio

## 🛠️ Requisiti Tecnici

- **Godot Engine**: 3.6 o superiore
- **Sistema Operativo**: Windows, macOS, Linux
- **Hardware**: GPU con supporto OpenGL 3.3+

## 📦 Installazione

1. Clona il repository:
```bash
git clone https://github.com/username/leo-satellite-constellation.git
```

2. Apri il progetto in Godot Engine

3. Avvia la simulazione dalla scena principale

## 🎮 Utilizzo

### Controlli Base
- **Mouse drag**: Navigazione camera 3D
- **Pannello UI**: Controllo velocità simulazione (0x-100x)
- **Statistiche**: Monitoraggio in tempo reale dello stato della costellazione

### Stati dei Satelliti
- **Verde**: Satellite operativo
- **Giallo lampeggiante**: Satellite in riposizionamento
- **Rosso lampeggiante**: Satellite in fase di guasto (5 secondi di transizione)
- **Grigio/Invisibile**: Satellite inattivo (fuori servizio)

## 📊 Metriche e Analisi

Il sistema fornisce analisi dettagliate attraverso il modulo `DataCollector.gd`:

### Metriche Principali
- **Stati dei satelliti**: Numero di satelliti attivi, in riposizionamento, degradati e non funzionanti
- **Copertura terrestre**: Percentuale di copertura globale, continuità del servizio e qualità geografica
- **Distribuzione spaziale**: Uniformità orbitale, distanze medie tra satelliti vicini e identificazione di gap critici
- **Dinamiche di stabilizzazione**: Tempo di convergenza, presenza di oscillazioni e score di stabilità del sistema
- **Resilienza a cascata**: Rilevamento di guasti a cascata, severità degli eventi e capacità di recupero
- **Connettività di rete**: Numero medio di vicini attivi, satelliti isolati e rapporto di connettività generale
- **Gap orbitali**: Analisi dettagliata delle lacune nella copertura con identificazione di gap critici

### Sistema di Copertura Terrestre
- **Griglia discreta**: Risoluzione 25° x 25° (14 celle in larghezza, 7 in altezza)
- **Ponderazione geografica**: Peso basato su coseno(latitudine) per compensare deformazione sferica
- **Raggio di copertura**: 10.0 km con calcolo distanza euclidea 3D
- **Precisione geometrica**: Coordinate cartesiane tridimensionali

### Raccolta e Esportazione Dati
- **Campionamento**: Ogni secondo (configurabile) durante l'intera simulazione
- **Formato output**: JSON strutturato con metadati completi
- **Riproducibilità**: Documentazione parametri di simulazione e condizioni sperimentali
- **Analisi comparativa**: Supporto per confronti tra esperimenti multipli

## 🔬 Approccio Scientifico

Il progetto si basa su letteratura scientifica consolidata nel campo dei sistemi multi-agente applicati alle costellazioni satellitari, con particolare attenzione alla validazione attraverso confronti con sistemi operativi reali come Starlink.

*Sviluppato per la ricerca nell'ambito dei sistemi ad agenti spaziali, autonomi e resilienti*
