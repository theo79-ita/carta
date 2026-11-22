# Carta 0.2.12 Glass

Carta è un’app Markdown nativa per macOS, con un’anteprima per la lettura e una macchina da scrivere per comporre il testo.

## Avvio

Estrai **Carta-0.2.12-Glass.zip** e apri **Carta 0.2.12 Glass.app**. Nello ZIP trovi anche **Carta.icon**, modificabile con Icon Composer di Apple. Nel progetto puoi avviare la stessa build da **dist/Carta.app**. Puoi trascinare l’app in Applicazioni oppure avviarla direttamente da questa cartella. Richiede macOS 13 o successivo; la build viene prodotta per l’architettura del Mac usato per compilarla.

Apri un file con **⌘O**, trascinalo nella finestra o usa **Apri con → Carta** nel Finder. L’app registra il supporto per i file Markdown senza cambiare l’app predefinita.

## Scrittura

Nel menu in alto a sinistra, **Scrittura normale** apre un editor con ritorno a capo automatico. **Macchina da scrivere** apre lo stesso testo su carta avorio, con inchiostro scuro e carrello in vetro. Puoi cambiare variante durante una modifica. Con **⌘N** inizi un nuovo documento nella variante usata per ultima. La modalità **Lettura** mostra l’anteprima Markdown anche prima di salvare.

In entrambe le modalità di scrittura, premi e rilascia **⌥ Option** da solo per aprire le categorie Markdown accanto al cursore del testo. Usa **↑ ↓** per scegliere una voce, **→** per entrare in un sottomenu e **←** per risalire. **Invio** applica il comando ed **Esc** chiude il menu.

Con un clic destro o **Ctrl-clic** sul foglio, apri **Inserisci Markdown**. Puoi formattare una selezione, numerare più righe, creare una tabella da celle separate da tabulazioni o cambiare l’allineamento della colonna su cui fai clic. I modelli inseriti a cursore vuoto selezionano il primo campo da compilare. **⌘Z** annulla l’inserimento. Il gruppo **Altri editor · solo sorgente** raccoglie le sintassi da utilizzare in altri lettori.

Nella macchina da scrivere il foglio resta fermo mentre batti i caratteri. L’indice del righello segue il cursore. Con Invio l’indice torna al margine e il righello scende sopra la nuova riga. Quando la riga raggiunge circa i due terzi dell’area di scrittura, il foglio scorre di poche righe. Puoi scorrerlo anche con il trackpad. Lucchetto e altoparlante sono alle estremità del vetro. I controlli rispettano **Riduci trasparenza**.

Il foglio verticale misura 210 × 297 mm secondo le dimensioni fisiche comunicate dal monitor. Cambiando schermo o risoluzione, Carta ricalcola la scala. Nelle finestre piccole puoi scorrere il foglio. Se la misura comunicata dal monitor è approssimativa, fai clic su **A4** nell’angolo in basso a destra e inserisci la distanza in millimetri misurata con un righello fra le due tacche, oppure seleziona la diagonale in pollici. Carta ricorda la correzione per quel display. I fogli successivi proseguono sullo schermo senza aggiungere interruzioni al file Markdown.

Il campanello avvisa a sei caratteri dal margine destro, fissato a 60 colonne. Premi **Invio** per riportare il carrello a sinistra e passare alla riga successiva. Fai clic sul **lucchetto** per sbloccarlo. Il pulsante con l’altoparlante disattiva i suoni. Puoi correggere il testo con **Backspace** e selezionarlo con il mouse o la tastiera.

Usa **⌘S** per salvare e **⇧⌘S** per salvare con un altro nome. Se il file originale è cambiato su disco, puoi salvare la tua versione con un altro nome. I nuovi file sono in UTF-8. Carta usa la codifica originale durante il salvataggio sullo stesso file se può rappresentare tutto il testo.

## Lettura

- Foglio avorio con caratteri serif, indice richiudibile in vetro e tempo di lettura rimanente sempre visibile sotto il documento. La stima parte da 220 parole al minuto e segue la posizione di scorrimento, anche quando torni indietro o salti a un titolo.
- Anteprima Markdown con tabelle, liste di attività, citazioni, immagini e blocchi di codice copiabili.
- Tabelle larghe con colonne leggibili, allineamenti Markdown e scorrimento orizzontale nelle finestre strette.
- Indice navigabile generato dai titoli, file recenti e ricerca nel documento (⌘F).
- Temi automatico, chiaro, scuro e carta; dimensione del testo da 13 a 24 px.
- Vista del sorgente (⇧⌘U), aggiornamento automatico e stampa / PDF dal dialogo di stampa macOS (⌘P).
- Immagini relative all’interno della cartella del documento e collegamenti ad altri file Markdown.
- Lettura UTF-8, UTF-16 con BOM e Windows-1252; limite di 20 MB per documento.

L’app apre un documento alla volta. I file `.mdx` vengono trattati come testo Markdown, senza eseguire JSX.

## Compilazione e test

Per correzioni e piccoli miglioramenti incrementa il terzo numero di versione (0.2.5 → 0.2.6 → 0.2.7). Incrementa il secondo numero solo quando introduci una funzionalità importante e riparti da zero con il terzo (per esempio, da 0.2.7 a 0.3.0). A ogni rilascio aggiorna il nome e la versione in `scripts/Info.plist` e i riferimenti al pacchetto in questo README.

Sono sufficienti gli strumenti da riga di comando di Xcode con Swift 5.9 o successivo. Non occorre scaricare pacchetti durante la compilazione.

```sh
./scripts/build-app.sh
open dist/Carta.app
./scripts/test.sh
```

I test verificano salvataggio, codifiche, conflitti su disco, comportamento della macchina da scrivere e rendering tramite WebKit. `./scripts/test.sh --without-webkit` esegue i controlli sui documenti e sulla macchina da scrivere quando WebKit non è disponibile. Il test runner usa gli strumenti da riga di comando di Xcode.

La build locale è firmata ad hoc. Per distribuirla ad altri utenti occorrono la firma Developer ID e la notarizzazione Apple.

## Dati e risorse

I documenti vengono elaborati localmente. La lista dei file recenti e le preferenze vengono salvate nei valori predefiniti macOS. Le immagini HTTP/HTTPS presenti nei documenti possono essere scaricate dai rispettivi server; i link esterni si aprono nel browser solo su clic. Le immagini locali non possono uscire dalla cartella del documento, nemmeno attraverso collegamenti simbolici.

Il contenuto HTML è filtrato con DOMPurify; una Content Security Policy blocca script dei documenti, frame, moduli e connessioni via JavaScript. Le librerie di rendering sono incluse nell’app e non richiedono una connessione.

## Librerie incluse

- [Marked](https://marked.js.org), versione 18.0.14, licenza MIT.
- [DOMPurify](https://github.com/cure53/DOMPurify), versione 3.4.16, licenza Apache-2.0 oppure MPL-2.0.

Le licenze originali sono in `Sources/Carta/Resources/vendor/`. Per la licenza MIT di Carta e tutte le attribuzioni, consulta [LICENSE](../LICENSE) e [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
