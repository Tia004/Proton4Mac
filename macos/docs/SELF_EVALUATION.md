# Delivery evaluation

This is a useful initial milestone; the original request for a complete Proton
runtime port is not fulfilled by the launcher.

| Axis | Score | Evidence and improvement |
| --- | --- | --- |
| Accuracy | 4/5 | Unit tests, real pixel probes and a Baking Bad title frame substantiate narrow claims. Shader/runtime failures and gameplay remain unresolved; avoid compatibility claims beyond the observed frame. |
| Completeness | 2/5 | Fork, source inventory, Darwin entry and app exist. Valve Wine and graphics dependencies were not ported or built; Steam integration and low-end hardware validation remain missing. Complete those milestones before calling this a Proton port. |
| Clarity | 4/5 | README and audit distinguish external Wine from Valve Wine and a menu from gameplay. A single supported-runtime installer remains undefined. |
| Actionability | 3/5 | Local app and CLI can use the installed Wine; synthetic tests are reproducible. A new user still needs a compatible runtime and build tools; the current Homebrew Wine cask is disabled. Establish a verified free runtime distribution path. |
| Conciseness | 4/5 | User-facing instructions are short; the larger machine inventory exists to document coverage. Keep raw game/REA logs out of the public repository. |

Overall: 3.4/5. Critical gap: completeness. The missing runtime and Steam work
require substantial dependency-level engineering, not a wording repair.

Highest-impact next steps: reproducible Darwin Wine build; validated graphics
and gameplay path; native Steam integration and base-M1 measurements.

Self-check: the user should judge this as a working prototype and partial
delivery, not the complete conversion requested. The final response must state
that limitation explicitly. No additional permission request is warranted for
routine follow-up engineering already within the authorized scope.

## Aggiornamento 0.2

Il launcher è stato sostituito con una libreria nativa persistente, associazione
`.exe`, importazione automatica, sorgenti web personalizzabili e finestre sul
Retina. 16 test Python e 15 controlli della libreria passano. OpenGL dalla libreria
e Direct3D 11 FL11.0 con DXMT hanno prodotto il pixel atteso e uscita 0. Il motore
DXMT opzionale è installato separatamente dal Wine originale.

Il runtime Valve ora è stato effettivamente compilato e installato per Darwin,
con otto patch riproducibili sul commit esatto di Proton 11; riporta `wine-11.0`.
Ha superato comando Windows, OpenGL e D3D9; anche Valve Wine 11 + DXMT ha superato
shader HLSL, disegno, readback e presentazione. Restano Steam, DirectX 12 e i test
su M1 base/A18 Pro. Le dipendenze provengono ancora da una Wine gratuita già
installata: manca una distribuzione autosufficiente verificata.

Un dialogo di sistema per l’associazione è comparso sul Samsung durante i test.
È stato dichiarato all’utente; il vincolo Retina non copre le finestre di macOS.
Il consenso alla cartella, il suo riuso, la scelta DXMT e il download interno sono
stati poi verificati sul Retina dopo lo sblocco. Il successivo blocco del Mac ha
impedito la verifica visiva dell’ultima voce Valve 11 nel selettore; il relativo
motore è stato verificato con successo dal terminale.

Le sorgenti web non sono connettori di account o autorizzazioni ai cataloghi.
Nessuna credenziale, acquisto o download di un gioco commerciale è stato usato
per verificare il browser. Il lavoro è una consegna parziale sostanziale; non
va presentato come un porting completo di Proton.

Le otto patch si applicano senza conflitti ai file del commit Wine fissato e
ricostruiscono esattamente i file di porting usati nella build. Il controllo
Vulkan è stato ripetuto con MoltenVK 1.4.2: le funzioni obbligatorie mancanti
sono un blocco misurato per il percorso vkd3d-proton attuale.
