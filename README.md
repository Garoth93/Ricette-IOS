# Ricettario (iOS)

App iPhone nativa (Swift + SwiftUI) per scrivere, ricalcolare e cucinare le
tue ricette. Tutto resta sul telefono, con backup automatico in iCloud Drive.
Compilata da GitHub Actions (niente Mac) e installata con TestFlight.

## Cosa fa

- **Ricette** con due sezioni, entrambe facoltative: ingredienti e
  procedimento. Persone, tempi, tag, note, fonte, foto, preferite.
- **Ingredienti**: nome, quantità, unità (g, kg, ml, l, cucchiai, cucchiaini,
  tazze, oz, lb, pezzi, spicchi, fette, foglie…), "q.b.", nota. Pool di ~340
  ingredienti comuni già pronti, più quelli che aggiungi tu. Densità g/ml
  facoltativa per convertire tazze e cucchiai in grammi.
- **Procedimento a pagine**: testo libero, foto (libreria o fotocamera),
  timer. Dal menu *Inserisci ingrediente* richiami un ingrediente della
  ricetta, anche solo una parte (metà, un terzo, 30%…): nella ricetta compare
  con la quantità giusta, es. «aggiungi 125 g di farina».
- **Usa ricetta**: sessione temporanea, la ricetta salvata non cambia mai.
  - cambi le persone → tutto si ricalcola (fattore = nuove / originali);
  - tocchi una quantità e scrivi quanta ne hai (4 uova → 3 = × 0,75) →
    tutto si ricalcola, passaggi compresi;
  - uova e simili: ± di un'unità, mai decimali, con la differenza segnalata;
  - sale, pepe e "q.b." restano fissi;
  - chiudendo si perde tutto, a meno di **Salva come variante** (nuova ricetta).
- **Modalità cottura**: un passaggio per pagina, avanti/indietro, testo
  grande regolabile, schermo sempre acceso, checklist degli ingredienti,
  timer che suonano anche con l'app chiusa.
- **Lista della spesa** dalle ricette (anche con le quantità ricalcolate),
  voci uguali sommate, divisa per reparto, condivisibile.
- **Ricerca** (titolo, ingredienti, tag, note), filtri per tag e preferite,
  **duplica**, condividi come testo o come file `.ricetta`.
- **Unità** in Impostazioni: come inserite, metrico o imperiale; tazza 240 o
  250 ml; conversione in peso con la densità. Le quantità sono salvate in
  g/ml/pezzi e convertite solo quando le vedi.
- **Backup**: automatico in iCloud Drive › Backup › Ricettario (uno al giorno,
  ultimi 30, foto comprese) e export/import JSON manuale.

## Configurazione (una volta)

Vedi la checklist completa nel messaggio di setup; in breve:

1. developer.apple.com › Identifiers › App ID `com.garoth93.ricettario`
   con **iCloud** (CloudKit/iCloud Documents) › Configure › container
   `iCloud.com.garoth93.backup`. Niente App Group, niente widget.
2. App Store Connect › nuova app «Ricettario», ID pacchetto
   `com.garoth93.ricettario`, SKU `ricettario-ios`.
3. Secrets della repo: `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID`,
   `ASC_KEY_P8` (stessi valori delle altre app).
4. Actions › **testflight** › Run workflow (parte anche a ogni push su `main`).

## Struttura

```
apps/Ricettario/           app SwiftUI (project.yml per XcodeGen)
packages/RicettarioCore/   logica (unità, scaling, token, pool, spesa, backup), testata su Linux
.github/workflows/         build-simulator, test-linux, build-ipa, testflight
CLAUDE.md                  convenzioni e regole di lavoro
```

## Privacy

Nessun server, nessun account, nessuna rete. Nella repo non ci sono dati
personali: i test usano solo dati sintetici.
