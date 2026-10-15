# Runtime Valve: sviluppo Darwin

Base esatta: `ValveSoftware/wine@e60892cc2398b0a83c332a2078c7b85e47bdb42b`, il gitlink del ramo Proton 11.0 usato da questo fork. Non viene sostituito con Wine upstream recente.

Le patch sono conservate nel repository principale, senza cambiare il gitlink a un commit locale non pubblicato. Modificano sorgenti Wine LGPL; non ricadono nella licenza BSD del nuovo launcher.

| Patch | Scopo |
| --- | --- |
| `0001` | Esclude la telemetria AMD DRM Linux da Darwin; restituisce non supportato anziché dati inventati |
| `0002` | Protegge `malloc.h`, `mallopt` e i futex Linux; fsync rimane disattivato su Darwin |
| `0003` | Esclude ntsync e topologia CPU Linux, conserva la gestione GS Mach e corregge un salto indiretto per l’assembler Apple |
| `0004` | Mantiene il percorso OpenGL nativo quando EGL non è compilato; evita riferimenti alle superfici EGL non disponibili |
| `0005` | Include esplicitamente `pthread.h` nel convertitore multimediale condiviso |
| `0006` | Allinea risorse plist e scelta del preloader del secondo loader alla configurazione Darwin |
| `0007` | Estrae correttamente i nomi delle dylib anche quando il loro install name non contiene una directory |
| `0008` | Adatta il nuovo layout delle finestre Wine 11 all’interfaccia Metal usata dal DXMT 0.80 fissato |

Queste sono correzioni di portabilità concrete, non una dichiarazione di equivalenza funzionale al runtime Linux. La loro validazione completa richiede build, avvio, test di sincronizzazione e carichi reali. Fsync/ntsync non vengono emulati con syscall numeriche Linux su macOS.

## Riprodurre la build

Occorrono Apple Command Line Tools, Autoconf/Automake, Flex, **Bison moderno**, LLVM con backend PE/COFF e linker LLD, header FreeType e dipendenze Darwin **x86_64**. Il compilatore Unix è quello Apple; il compilatore PE è LLVM. Una libreria Homebrew solo ARM64 non può essere collegata al runtime Unix x86_64.

```sh
git submodule update --init wine
python3 macos/build_runtime.py \
  --deps '/percorso/dipendenze-x86_64/lib' \
  --freetype-include '/percorso/include/freetype2' \
  --llvm-bin '/opt/homebrew/opt/llvm/bin' \
  --bison-bin '/opt/homebrew/opt/bison/bin' \
  --jobs 4
```

Lo script verifica il commit, applica le patch senza duplicarle, esegue i generatori di Wine, configura, compila e installa sotto `macos/build/valve-runtime`. Si possono eseguire le fasi separatamente con `--phase configure`, `build` o `install`. Un conflitto nelle patch ferma l’operazione. I log completi possono essere salvati reindirizzando l’output. A fase conclusa viene scritto `proton4mac-build.json` con pin e hash delle patch.

La configurazione usa Unix Darwin x86_64 e moduli Windows x86_64/i386 WoW64. Disabilita X11, Wayland e la compilazione delle suite di test upstream (le prove del progetto si compilano e si eseguono separatamente). I componenti opzionali dipendono dagli header e dalle librerie rilevati da `configure`; controllare il suo riepilogo. La build locale non fornisce una pipeline multimediale completa GStreamer/FFmpeg; audio, controller e video richiedono prove dedicate.

La sessione di sviluppo usa le dipendenze x86_64 di una **installazione gratuita già esistente di Wine 10.0**. Non è quindi una build autosufficiente delle dipendenze, né un pacchetto pronto da redistribuire. Resta da assemblare un SDK riproducibile e verificare tutti gli obblighi di licenza e i percorsi delle librerie dinamiche.

**Nessuna attivazione automatica:** il runtime in sviluppo non sostituisce quello dei giochi esistenti. Provare un runtime diverso con `--wine` e un **nuovo** nome di ambiente. Non cambiare i marker dei prefissi per forzarne la migrazione.

## Grafica Metal

È stato valutato [DXMT](https://github.com/3Shain/dxmt), che traduce Direct3D 10/11 su Metal. Il pacchetto ufficiale di prova è `v0.80`, SHA-256 `8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d`.

Una copia privata del runtime gratuito, con i moduli DXMT sovrapposti e un prefisso esclusivo per i test, ha superato `win32_d3d11.c`: dispositivo hardware FL11.0, clear, lettura del pixel atteso e presentazione dello swap chain, uscita 0. I file dell’installazione Wine originale non sono stati modificati. Il motore è disponibile come scelta opzionale prima del primo avvio di un gioco; vedere [installazione e prova](../../docs/GRAPHICS.md). Le prestazioni nei giochi restano da validare.

Questo risultato non riguarda DirectX 12. [vkd3d-proton](https://github.com/HansKristian-Work/vkd3d-proton) richiede capacità Vulkan avanzate: la sola presenza di MoltenVK non basta a soddisfarle.
