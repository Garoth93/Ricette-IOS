# CLAUDE.md — regole di lavoro per questa repo

App iOS **nativa (Swift + SwiftUI)** sviluppata senza Mac: il codice viene
scritto su Linux (Claude Code) e compilato **solo** su GitHub Actions con
runner macOS. Non va su App Store: l'app arriva sull'iPhone con **TestFlight**
(account Apple a pagamento, firma automatica in CI, `testflight.yml`); il
`.ipa` non firmato per Sideloadly (`build-ipa.yml`) resta come ripiego.

Stessa impostazione di `Garoth93/tessere-IOS` (procedure TestFlight e backup
iCloud descritte nel suo CLAUDE.md), `Garoth93/montagna-360` (Cresta),
`Garoth93/valigia-IOS`.

## Vincoli fissi

- Nativo vero: Swift/SwiftUI. Niente WebView, niente cross-platform.
- Nessun `.xcodeproj` committato: generato in CI da `apps/<app>/project.yml`
  con XcodeGen.
- Mai committare segreti, certificati, profili, `.p8`, Team ID (solo nei
  secrets della repo).
- **Privacy**: mai committare dati personali (ricette dell'utente, backup,
  file `.ricetta`, foto). I test usano solo dati sintetici
  (`Synthetic.swift`, nomi `... TEST`). Nell'app non c'è nessun "genera dati
  di prova".
- Tutto locale, nessun server e nessuna chiamata di rete. iCloud solo come
  **backup in iCloud Drive** (niente CloudKit).
- Firma solo in `testflight.yml`. Non modificare impostazioni della repo o
  secrets: spiegare all'utente cosa configurare.

## Struttura

| App        | Package logica  | Bundle ID                  | Deployment target |
|------------|-----------------|----------------------------|-------------------|
| Ricettario | RicettarioCore  | `com.garoth93.ricettario`  | iOS 26.0 |

Niente widget e niente App Group (scelta: un'app di ricette non ne ha
bisogno; i timer avvisano con notifiche locali). Container iCloud
`iCloud.com.garoth93.backup` (solo app), spuntato a mano su
developer.apple.com sull'App ID `com.garoth93.ricettario`.

```
apps/Ricettario/            app SwiftUI (project.yml per XcodeGen)
  Sources/                  schermate, AppModel, backup iCloud, timer, foto
  Shared/Theme.swift        tema Material 3 (seme scelto dall'utente)
  Ricettario.entitlements   iCloud (TestFlight)
  Ricettario.sideload.entitlements  vuoto (build-ipa, account gratuito)
packages/RicettarioCore/    logica Foundation-only, testata su Linux
scripts/                    asc_bundle_ids.py, asc_revoke_certs.py (TestFlight)
```

### Package `RicettarioCore` (tutto testato)

- `Units.swift`: `CookUnit` (massa, volume, pezzi), `QuantityKind`,
  `UnitPreferences` (sistema come inserite/metrico/imperiale, tieni cucchiai,
  converti volumi in peso con la densità, tazza 240/250 ml),
  `UnitConverter.display`, `Fmt` (numeri italiani, frazioni ½ ¼ ⅓, durate,
  `parseAmount` per "1 1/2", "½", "1,5").
- `Models.swift`: `CatalogIngredient` (pool: `seed.<slug>` / `user.<uuid>`,
  densità, `wholeOnly`, `scales`), `RecipeIngredient` (quantità in **unità
  base** g/ml/pezzi, `nil` = q.b., unità inserita = preferenza di
  visualizzazione), `RecipeStep` (testo con token, foto, timer), `Recipe`,
  `ShoppingItem`, `RicettarioSettings`, `RicettarioData` (revision),
  `RecipeOps.sanitized` (pulizia prima del salvataggio). Decodifica
  tollerante ovunque (campo mancante = default).
- `SeedIngredients.swift` + `Catalog.swift`: ~340 ingredienti comuni
  (`nome|categoria|unità|densità|flag`, flag `w` solo interi, `n` non scala);
  l'id deriva dal nome: **non rinominare** una riga, aggiungerne una nuova.
  Pool = seed (con `seedOverrides`, meno `hiddenSeeds`) + `customIngredients`.
  Ricerca, `RecipeQuery` (testo senza accenti, tag, preferite, ordinamenti),
  `Tags`, `TimerDetector` (propone il timer dal testo: "30 minuti", "1 ora e
  mezza", "mezz'ora").
- `StepText.swift`: token salvati `{{ing:<uuid>}}` / `{{ing:<uuid>|0.5}}`;
  nell'editor forma leggibile `{Farina 00}` / `{1/2 Farina 00}` / `{30% Farina}`
  (`editable` ↔ `stored`, nomi doppi → "Zucchero (2)").
- `Scaling.swift`: `ScaleSession` (originale immutabile, `factor`,
  `setServings`, `setAnchor` = nuova qta / vecchia qta, `step` ±1 sui pezzi),
  `PieceRounding` (interi o metà, mai sotto 1, `isRounded` segnala la
  differenza), q.b. e "non scala" fissi, `makeVariant`, `StepRenderer`
  (token → "125 g di farina", "3 uova", "sale q.b.").
- `Shopping.swift`: `ShoppingList.add` (somma stesse voci non spuntate, massa
  e volume uniti con la densità), raggruppamento per categoria, testo;
  `RecipeText.plain`.
- `Backup.swift`: `JSONFileStore`, `BackupFile` (versione, foto base64 solo
  nell'export manuale), `RecipeShareFile` (`.ricetta`), `DataMerge`
  (merge per id + più recente / replace / import ricetta condivisa),
  `CloudBackupPlan`.

### App

- `AppModel` (`@Observable`, `@MainActor`): `mutate` unico punto di modifica
  (salvataggio differito 0,5 s in `ricettario-data.json`, `.bak` della
  versione precedente, file illeggibile messo da parte), pool in cache, foto
  JPEG max 1600 px in `Application Support/Ricettario/Photos` (orfane rimosse),
  import/export, file `.ricetta` aperti da altre app (`onOpenURL`).
  Mai leggere `data` dentro la closure di `mutate` (accesso esclusivo).
- Schermate: Ricette (ricerca, tag, preferite, ordinamento), scheda ricetta,
  editor (ingredienti dal pool con quantità/unità/q.b./densità, pagine con
  `TextEditor` + menu "Inserisci ingrediente" con frazioni, al cursore),
  **Usa ricetta** (`UseRecipeView`, sessione solo in memoria, persone ±,
  àncora toccando una quantità, ± sui pezzi, arrotondamenti segnalati, salva
  come variante, spesa), **modalità cottura** (`CookingModeView`: pagine,
  testo grande regolabile, `isIdleTimerDisabled`, checklist ingredienti,
  timer), Spesa, Ingredienti (pool), Impostazioni.
- `TimerCenter`: più timer insieme, pausa/+1 min, notifica locale alla fine.
- `CloudBackupService`: come Cresta (vedi tessere-IOS), cartella
  `Ricettario`, foto in `photos/`, BGAppRefresh `com.garoth93.ricettario.backup`.

## Convenzioni di codice

- Swift 5 language mode (`SWIFT_VERSION: 5.0`), tools-version 5.9 nel package
  (Linux `swift:6.0` e Xcode 26 compilano lo stesso codice).
- Logica nel package (struct value-type, `Codable`, `Equatable`, `Sendable`,
  niente SwiftUI/UIKit), ogni regola ha un test.
- App: `@Observable` + `@MainActor`, `.environment(...)`; testi e permessi in
  italiano; target iOS 26 (API SwiftUI di iOS 26 senza `#available`).
- Grafica Material 3 Expressive come Cresta (seme "Pomodoro" di default).
- Commit piccoli e descrittivi; niente identificatori di modello AI nei commit.

## Xcode, CI e TestFlight

- Runner `macos-26`, `XCODE_VERSION: "26.6"` in ogni workflow; Linux
  `swift:6.0-noble`.
- `build-simulator.yml` (ogni push), `test-linux.yml` (ogni push),
  `build-ipa.yml` (main e `claude/**`, `.ipa` non firmato con
  `Ricettario.sideload.entitlements`), `testflight.yml` (manuale, push su main
  e `claude/**`, ogni 2 mesi). Build number = `github.run_number`.
- `MARKETING_VERSION` in `project.yml` da alzare a mano per le nuove versioni.
- Lo step "App ID capabilities" stampa le capability e cancella i profili
  senza il container iCloud (`--container`), così Xcode li ricrea.

## Regole di lavoro (per Claude)

1. Dopo **ogni push** controllare la CI e correggere da soli gli errori fino
   a build verde. Mai dichiarare "funziona" se la CI non è verde.
2. Non si vede l'interfaccia: nelle scelte grafiche ambigue usare il
   comportamento standard e dire all'utente cosa verificare sul telefono.
3. Test del package in locale:
   `docker run --rm -v "$PWD":/src -w /src swift:6.0-noble swift test --package-path packages/RicettarioCore`
   (avviare `dockerd` se non è attivo).
