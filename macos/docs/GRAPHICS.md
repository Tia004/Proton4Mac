# Motore DXMT opzionale

DXMT traduce Direct3D 10/11 su Metal. La prova sintetica Direct3D 11 è riuscita su M1 Max con Wine 10.0 e DXMT 0.80; non certifica shader complessi, giochi, FPS o DirectX 12.

## Installazione locale per sviluppatori

Servono macOS 14+, Rosetta per il runtime x86_64 e una copia compatibile di Wine 10.0, oppure la build Valve Wine 11 di questo progetto con le otto patch applicate. Lo script non sostituisce l’installazione originale. Scarica l’archivio dal [rilascio ufficiale v0.80](https://github.com/3Shain/dxmt/releases/tag/v0.80), poi:

```sh
python3 macos/setup_dxmt.py \
  --archive '/percorso/dxmt-v0.80-builtin.tar.gz' \
  --wine-root '/Applications/Wine Stable.app/Contents/Resources/wine'
```

Lo script verifica lo SHA-256 fissato nel sorgente, controlla versione e struttura del runtime base, estrae soltanto file/directory senza link e crea una copia privata tramite cloni APFS. I moduli opzionali NVAPI/NVNGX non vengono installati. Se la destinazione esiste si ferma senza sovrascriverla.

Il motore viene installato sotto `~/Library/Application Support/Proton4Mac/runtimes/dxmt-v0.80/`. L’app rende disponibile **Grafica: DXMT · DirectX 11 su Metal** per i giochi che non hanno ancora creato un ambiente Windows. I giochi già inizializzati conservano il proprio motore. La scelta viene salvata nella libreria.

Questa è una procedura locale di sviluppo basata su un runtime esistente, non un pacchetto completo di Wine con dipendenze compilate e licenze assemblate per la redistribuzione.

## Riprodurre la prova

Le intestazioni libere Wine e le intestazioni IDL generate nella build servono solo a compilare questa prova:

```sh
python3 macos/tests/build_probe.py --d3d11
python3 macos/proton4mac.py \
  --wine "$HOME/Library/Application Support/Proton4Mac/runtimes/dxmt-v0.80/bin/wine" \
  run --prefix dxmt-test macos/build/probe/win32-d3d11.exe
```

Il test richiede un dispositivo hardware D3D11 al livello 11.0 e crea uno swap chain. Compila shader HLSL `vs_5_0` e `ps_5_0`, disegna un triangolo, copia il risultato in una texture staging, legge e confronta il pixel centrale e presenta un frame. La prova DXMT ha restituito `D3D11_PIXEL=407fbfff` e uscita 0. Un errore in ciascuno di questi passaggi produce un codice di uscita distinto. Non è un benchmark e non copre i carichi di shader di un gioco reale.

## Valve Wine 11 + DXMT

Dopo la build e l’installazione descritte nelle [patch Darwin](../patches/wine/README.md), è possibile creare un secondo motore privato:

```sh
python3 macos/setup_dxmt.py \
  --archive '/percorso/dxmt-v0.80-builtin.tar.gz' \
  --wine-root macos/build/valve-runtime \
  --destination "$HOME/Library/Application Support/Proton4Mac/runtimes/valve11-dxmt-v0.80"
```

Il selettore dell’app abilita **Grafica: Valve 11 + Metal · sperimentale** quando
quel motore è presente. Il programma con shader ha restituito il pixel
`407fbfff` e uscita 0 anche su questa combinazione, usando un ambiente nuovo.
Non vengono accettate build Wine 11 generiche: serve il manifest della build
fissata e l’adattatore DXMT.

Wine 11 crea le superfici client in modo diverso dal vecchio macdrv. L’adattatore
fornisce a DXMT la struttura attesa e registra una vera superficie Wine, collegata
alla gestione nativa di aggiornamento e distacco. Non viene reinterpretata la
nuova struttura interna come se avesse il vecchio layout. La compatibilità oltre
al DXMT 0.80 fissato richiede una nuova verifica dell’interfaccia.
