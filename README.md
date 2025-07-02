# Low Earth Orbit Satellite Constellation - Centralized Control
## Implementazione con Controllo Centralizzato per Confronto Sperimentale

[![Godot](https://img.shields.io/badge/Godot-3.6-blue)](https://godotengine.org/)
[![Branch](https://img.shields.io/badge/Branch-Centralized-orange)](.)

## 📖 Panoramica

Questo branch realizza una versione alternativa del sistema di costellazione satellitare LEO con **controllo accentrato**, sviluppata per finalità di confronto sperimentale con l'approccio multi-agente distribuito del branch principale.

Pur conservando gli stessi principi teorici di modellazione orbitale e configurazione Walker-Delta, questa implementazione adotta un paradigma completamente differente: un **SatelliteManager accentrato** coordina globalmente l'intera costellazione, assumendo tutte le decisioni operative in maniera deterministica.

## 🎯 Obiettivi del Branch

- **Confronto sperimentale**: Valutazione delle differenze prestazionali tra approccio distribuito e centralizzato
- **Validazione metodologica**: Verifica dell'efficacia degli algoritmi multi-agente attraverso baseline centralizzata

## 🏗️ Architettura del Sistema

### Differenze Architetturali Principali

| Aspetto | Branch Principale (Multi-Agente) | Branch Centralizzato |
|---------|-----------------------------------|----------------------|
| **Controllo** | Distribuito tra agenti autonomi | Centralizzato in SatelliteManager |
| **Decision-making** | Locale con comunicazione inter-satellitare | Globale con visibilità completa |
| **Rilevamento guasti** | Auto-diagnostica distribuita | Scansione centralizzata |
| **Riposizionamento** | Algoritmi locali adattivi | Assegnazione deterministica centrale |
| **Scalabilità** | Alta (comportamenti emergenti) | Limitata (collo di bottiglia centrale) |

### Componente Centrale: `SatelliteManager`

Il nucleo del sistema accentrato che coordina:

#### Struttura Dati Unificata
- **Dizionario satelliti**: Condizione completa di ogni satellite (attivo, guasto, in caduta, rimosso)
- **Posizioni angolari**: Monitoraggio theta di ogni satellite
- **Parametri operativi**: Velocità orbitale, adiacenti, timer heartbeat
- **Condizione riposizionamento**: Parametri di riconfigurazione orbitale

#### Funzioni Operative
- **Inizializzazione**: Configurazione orbitale Walker-Delta e allocazione posizioni iniziali
- **Aggiornamento condizione**: Scansione e aggiornamento di tutti i satelliti ogni frame
- **Gestione malfunzionamenti**: Applicazione probabilità di fault deterministica
- **Coordinamento riposizionamento**: Orchestrazione globale delle riconfigurazioni

### Processo di Rilevamento e Gestione Malfunzionamenti

#### 1. Scansione Accentrata
- `SatelliteManager` valuta probabilità di malfunzionamento per ogni satellite
- Applicazione deterministica dei fault attraverso `update_satellites()`
- Attivazione sequenza di guasto controllata centralmente

#### 2. Riposizionamento Deterministico
Quando un malfunzionamento viene rilevato:

```
1. Identificazione orbita coinvolta
2. Calcolo posizioni angolari ideali (calculate_optimal_positions)
3. Allocazione posizioni target ottimali (minimizzazione spostamenti)
4. Marcatura satelliti come "in riposizionamento"
5. Modifica temporanea velocità angolare
6. Monitoraggio raggiungimento obiettivo
7. Ripristino velocità nominali
```

## 🔄 Componenti Condivisi con Branch Principale

### Modellazione Orbitale
- **Pattern Walker-Delta**: Stessa configurazione di distribuzione iniziale
- **Parametri LEO**: Orbite 630 km altezza
- **Sistema di coordinate**: Coordinate cartesiane tridimensionali

### Sistema di Copertura
- **`CoverageManager.gd`**: Griglia discreta 25° x 25° identica
- **Ponderazione geografica**: Stesso sistema di compensazione sferica
- **Raggio copertura**: 10.0 km con calcolo distanza euclidea 3D

### Raccolta Dati
- **`DataCollector.gd`**: Stesse categorie di metriche
- **Formato esportazione**: JSON strutturato compatibile per confronti
- **Campionamento**: Intervallo configurabile (default 1 secondo)

### Visualizzazione
- **`SatelliteRenderer.gd`**: Sistema di colorazione identico
- **Stati satelliti**: Verde, giallo lampeggiante, rosso lampeggiante, grigio/rimosso
- **Animazioni**: Caduta e rimozione graduale

## ⚖️ Vantaggi e Limitazioni

### Vantaggi del Controllo Accentrato
- **Controllo preciso**: Gestione predicibile e deterministica
- **Ottimizzazione globale**: Decisioni basate su informazione completa
- **Debugging semplificato**: Logica accentrata più facile da tracciare
- **Coerenza**: Comportamento uniforme e riproducibile

### Limitazioni Architetturali
- **Scalabilità ridotta**: Collo di bottiglia computazionale centrale
- **Punto singolo di fallimento**: Vulnerabilità del componente centrale
- **Realismo limitato**: Non replica vincoli operativi spaziali reali
- **Comportamenti emergenti**: Impossibilità di emergenza spontanea

## 🛠️ Installazione e Utilizzo

### Requisiti
- **Godot Engine**: 3.6 o superiore
- **Sistema Operativo**: Windows, macOS, Linux
- **Hardware**: GPU con supporto OpenGL 3.3+

### Avvio
1. Checkout del branch accentrato:
```bash
git checkout centralized
```

2. Apertura in Godot Engine

3. Avvio dalla scena principale

### Interfaccia Utente
- **Controlli identici** al branch principale

## 🔬 Scopo Scientifico

Questa implementazione funge da **baseline per validazione** dell'approccio multi-agente:

- **Confronto prestazioni**: Quantificazione vantaggi distribuzione
- **Validazione algoritmi**: Verifica correttezza logiche autonome
- **Studio scalabilità**: Identificazione soglie critiche
- **Analisi trade-off**: Compromessi tra controllo e autonomia
