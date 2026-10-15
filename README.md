# Proton4Mac

**I tuoi giochi Windows. Una libreria sul Mac.**

Proton4Mac è un fork indipendente di [Valve Proton](https://github.com/ValveSoftware/Proton), con un’app nativa per macOS: scegli un `.exe`, ritrovalo nella libreria e avvialo. Il codice è gratuito e aperto; CrossOver non è una dipendenza.

> **Versione 0.2 · sperimentale.** Il launcher funziona con un runtime Wine per macOS già installato. Il runtime Valve è stato compilato e ha superato le prime prove; la sua integrazione completa è in sviluppo. Non è ancora un sostituto completo di Proton su Linux e non garantisce la compatibilità di ogni gioco.

## Inizia a giocare

1. Apri **Proton4Mac.app**.
2. Premi **Aggiungi giochi…** e scegli l’eseguibile Windows del gioco. Puoi selezionarne diversi oppure trascinarli nella finestra.
3. Seleziona il gioco nella libreria e premi **Avvia gioco**. Al primo avvio viene preparato il suo ambiente Windows: può richiedere fino a due minuti.

Quando il motore DXMT per Wine 10 è installato, i nuovi giochi lo selezionano automaticamente. Puoi cambiare motore prima del primo avvio.

L’app ricorda giochi, ambienti e log tra un’apertura e l’altra. **Ferma** chiude la sessione del gioco selezionato; **Mostra log** apre i dettagli direttamente nell’app.

Mantieni l’intera cartella del gioco: il solo `.exe` spesso non basta. Se scarichi un archivio, estrailo prima. Se i file sono su iCloud, devono essere disponibili localmente.

### Doppio clic dal Finder

Dal menu **Proton4Mac → Associa i file .exe a Proton4Mac**, imposta l’app come gestore degli eseguibili Windows. macOS può chiedere una conferma iniziale. Da quel momento il doppio clic su un `.exe` lo aggiunge alla libreria e ne richiede immediatamente l’avvio; gli eseguibili già presenti non vengono duplicati.

Per le cartelle protette di macOS, come Download e Documenti, l’app può chiedere una volta di scegliere la cartella del gioco. L’autorizzazione viene ricordata. Le conferme di sicurezza del sistema restano sotto il controllo di macOS.

### Installer e giochi installati

Puoi aggiungere anche un installer `.exe`. Dopo l’installazione, seleziona la stessa voce e usa **Cambia file .exe…** per indicare l’eseguibile installato: l’ambiente Windows viene conservato.

**Rimuovi dalla libreria** elimina solo la voce. Conserva i file del gioco, l’ambiente e i salvataggi.

## Le tue sorgenti, in un solo posto

**Sorgenti** contiene collegamenti a Steam, SteamRIP, Xbox / Game Pass, Xbox Cloud Gaming, GOG ed Epic Games. Puoi aggiungere o rimuovere qualsiasi indirizzo web `http` o `https`.

I siti si aprono nel browser interno. I download compatibili con WebKit chiedono dove salvare il file; non vengono eseguiti automaticamente. Archivi, pagine di download, account ed eventuali conferme restano parte del servizio scelto. Non esistono scraping di cataloghi o downloader specifici di SteamRIP.

Un collegamento a un servizio **non equivale a un’integrazione del suo account**. Al momento non vengono sincronizzati acquisti, licenze, salvataggi cloud o librerie remote. L’app Xbox per Windows, Gaming Services e i giochi UWP non diventano compatibili aggiungendo un URL. Anche la riproduzione di Xbox Cloud Gaming nel browser incorporato richiede una verifica specifica; è presente il collegamento, non una certificazione del servizio.

## Un’app sul Retina del MacBook

Il launcher, il browser interno, i pannelli e i log preferiscono il display integrato del MacBook. Il percorso di avvio predefinito carica un controllo locale delle finestre nei processi Wine per mantenerle sul Retina e impedire cambi di modalità o catture degli schermi esterni.

Se il display integrato non è disponibile, l’app non apre una finestra su un monitor esterno. Questa scelta è intenzionale per l’attuale configurazione del progetto. Le finestre di sistema, i componenti esterni e i percorsi grafici non ancora testati non offrono la stessa garanzia. I controlli non modificano le impostazioni globali dei monitor.

## DirectX 11 su Metal

È disponibile un motore opzionale basato su DXMT. Dopo l’[installazione del motore](macos/docs/GRAPHICS.md), scegli **Grafica: DXMT · DirectX 11 su Metal** oppure **Grafica: Valve 11 + Metal · sperimentale** prima del primo avvio del gioco. Gli ambienti già creati conservano il motore originale. La compatibilità varia da gioco a gioco; DirectX 12 resta da portare: i [controlli delle capacità Vulkan](macos/docs/vulkan-capabilities.json) mostrano funzioni richieste ancora mancanti anche con MoltenVK 1.4.2 su questo M1 Max.

## Stato della compatibilità

| Componente | Stato verificato |
| --- | --- |
| Libreria locale, selezione `.exe`, ricerca, rimozione e cambio eseguibile | Implementati; test di persistenza e deduplicazione |
| Associazione `.exe` | Gestore macOS verificato; importazione automatica verificata |
| Esecuzione dall’app | Prova Windows x64 OpenGL riuscita su M1 Max |
| Windows `cmd`, OpenGL, Direct3D 9 | Prove sintetiche riuscite con Wine 10.0 |
| Baking Bad | Schermata iniziale renderizzata; gameplay e prestazioni non certificati |
| Runtime Valve di Proton 11 | Compilato per Darwin; comando Windows, OpenGL e Direct3D 9 riusciti |
| Direct3D 11 su Metal | DXMT opzionale: dispositivo FL11.0, clear, readback e present riusciti |
| DirectX 12, Steam Play macOS, overlay e anti-cheat | Non completati / non validati |
| M1 base, Mac con 8 GB, A18 Pro | Nessun risultato su questo hardware |

Le prove attuali vengono da **M1 Max, 32 GB RAM, macOS 27.0**. Non sono benchmark del modello M1 base. Gli ambienti separati sono prefissi Wine, non sandbox di sicurezza.

## Requisiti e compilazione dell’app

Servono macOS 12 o successivo per il launcher, Python 3, Xcode o Command Line Tools e un runtime Wine compatibile con macOS. Il runtime x86_64 provato su Apple Silicon richiede Rosetta. I requisiti dei singoli motori grafici possono essere più recenti.

```sh
git clone --branch proton4mac https://github.com/Tia004/Proton4Mac.git
cd Proton4Mac
python3 macos/build_app.py
```

L’app viene creata in `macos/build/Proton4Mac.app`. Spostala in una posizione stabile, per esempio `~/Applications`, prima di associarla agli `.exe`. La build è firmata localmente: non è una distribuzione notarizzata né un installer del runtime.

Il progetto è stato provato con un’installazione esistente di Wine Stable 10.0. Non fornisce ancora un percorso verificato di installazione da zero del runtime. La [cask wine-stable](https://github.com/Homebrew/homebrew-cask/blob/master/Casks/w/wine-stable.rb) risulta disabilitata dal 1 settembre 2026; non vengono disattivate le protezioni di macOS per aggirarlo.

### Uso dal terminale

```sh
python3 macos/proton4mac.py doctor
python3 macos/proton4mac.py run --prefix mio-gioco '/percorso/Gioco.exe'
PROTON4MAC_PREFIX=mio-gioco ./proton run '/percorso/Gioco.exe'
```

Passa `--wine /percorso/wine` **prima** del sottocomando per scegliere un runtime. Ogni ambiente conserva il proprio runtime e non passa silenziosamente a un altro. Gli argomenti del gioco seguono il percorso dell’eseguibile e non vengono interpretati da una shell.

Il comportamento predefinito vincola le finestre al Retina. Il parametro CLI `--display system` disabilita questo controllo soltanto per l’avvio richiesto.

Dati e log si trovano in `~/Library/Application Support/Proton4Mac/`:

```text
library.json     giochi e sorgenti
prefixes/        ambienti Windows separati
logs/            esiti e dettagli degli avvii
```

Il launcher limita le variabili di ambiente trasmesse ai giochi, escludendo le credenziali della sessione del terminale. Non importa né modifica ambienti CrossOver esistenti.

## Sviluppo del porting

Le modifiche macOS sono in `macos/`. Il launcher originale mantiene il percorso Linux; le istruzioni upstream sono in [README.proton.md](README.proton.md).

- [Analisi delle sorgenti, architettura e lavoro restante](macos/docs/PORTING.md)
- [Prove eseguite e limiti dei risultati](macos/docs/VALIDATION.md)
- [Build sperimentale del runtime Valve e patch Darwin](macos/patches/wine/README.md)

```sh
python3 macos/build_app.py
python3 -m unittest discover -s macos/tests -v
macos/build/library-tests
python3 macos/tests/build_probe.py
python3 macos/tests/run_probes.py
```

La CI compila l’app e verifica la logica del launcher e della libreria. I test grafici reali richiedono Wine e hardware locale. Nessun file commerciale dei giochi viene incluso nel repository.

## Licenze e crediti

Il nuovo codice macOS usa [BSD-3-Clause](macos/LICENSE). Proton, Wine e ogni sottoprogetto conservano le proprie licenze; le patch al codice Wine sono modifiche a Wine e seguono la sua LGPL. Dipendenze e relativi obblighi di redistribuzione vanno verificati prima di pubblicare un runtime completo.

Il progetto si basa sul lavoro di Valve, Wine, CodeWeavers, Khronos e degli altri autori upstream. L’open source consente anche servizi e distribuzioni commerciali: Proton4Mac sceglie un’interfaccia e un percorso di sviluppo gratuiti. È un progetto indipendente, non approvato da Valve, Apple o CodeWeavers.
