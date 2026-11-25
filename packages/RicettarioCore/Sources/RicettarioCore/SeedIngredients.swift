import Foundation

/// Built-in pool of common ingredients. One line per ingredient:
/// `name|category|unit|density g/ml|flags` (flags: `w` whole units only,
/// `n` does not scale). Ids are derived from the name ("seed.<slug>"):
/// never rename an entry, add a new one instead.
enum SeedTable {
    static let lines = """
    Farina 00|flour|g|0.53|
    Farina 0|flour|g|0.53|
    Farina Manitoba|flour|g|0.53|
    Farina integrale|flour|g|0.5|
    Farina di farro|flour|g|0.5|
    Farina di segale|flour|g|0.5|
    Farina di riso|flour|g|0.6|
    Farina di mais (fioretto)|flour|g|0.6|
    Farina di grano saraceno|flour|g|0.5|
    Farina di ceci|flour|g|0.45|
    Farina di mandorle|flour|g|0.4|
    Farina di cocco|flour|g|0.45|
    Semola rimacinata|flour|g|0.68|
    Semolino|flour|g|0.68|
    Polenta istantanea|flour|g|0.65|
    Amido di mais (maizena)|flour|g|0.54|
    Fecola di patate|flour|g|0.6|
    Fiocchi d'avena|flour|g|0.38|
    Pangrattato|flour|g|0.45|
    Crusca|flour|g|0.25|
    Cous cous|pasta|g|0.7|
    Bulgur|pasta|g|0.75|
    Quinoa|pasta|g|0.75|
    Orzo perlato|pasta|g|0.8|
    Farro|pasta|g|0.8|
    Miglio|pasta|g|0.8|
    Riso Carnaroli|pasta|g|0.85|
    Riso Arborio|pasta|g|0.85|
    Riso Basmati|pasta|g|0.8|
    Riso integrale|pasta|g|0.8|
    Riso Venere|pasta|g|0.8|
    Spaghetti|pasta|g||
    Penne|pasta|g||
    Fusilli|pasta|g||
    Rigatoni|pasta|g||
    Paccheri|pasta|g||
    Linguine|pasta|g||
    Tagliatelle|pasta|g||
    Lasagne (sfoglie)|pasta|g||
    Gnocchi di patate|pasta|g||
    Pasta all'uovo|pasta|g||
    Pasta corta|pasta|g||
    Pastina|pasta|g||
    Pane|pasta|g||
    Pane raffermo|pasta|g||
    Pane in cassetta|pasta|slice||w
    Pancarré|pasta|slice||w
    Piadina|pasta|piece||w
    Tortillas|pasta|piece||w
    Pasta sfoglia (rotolo)|pasta|piece||w
    Pasta brisée (rotolo)|pasta|piece||w
    Pasta frolla|pasta|g||
    Pasta per pizza|pasta|g||
    Grissini|pasta|piece||w
    Crackers|pasta|g||
    Fette biscottate|pasta|piece||w
    Biscotti secchi|baking|g||
    Savoiardi|baking|piece||w
    Amaretti|baking|piece||w
    Uova|dairy|piece||w
    Tuorli|dairy|piece||w
    Albumi|dairy|piece||w
    Latte intero|dairy|ml|1.03|
    Latte parzialmente scremato|dairy|ml|1.03|
    Latte vegetale|dairy|ml|1.02|
    Panna fresca|dairy|ml|1.0|
    Panna da cucina|dairy|ml|1.0|
    Burro|dairy|g|0.96|
    Burro chiarificato|dairy|g|0.9|
    Yogurt bianco|dairy|g|1.03|
    Yogurt greco|dairy|g|1.05|
    Mascarpone|dairy|g|1.0|
    Ricotta|dairy|g|1.0|
    Mozzarella|dairy|g||
    Mozzarella di bufala|dairy|g||
    Burrata|dairy|piece||w
    Stracchino|dairy|g||
    Gorgonzola|dairy|g||
    Parmigiano Reggiano|dairy|g|0.4|
    Grana Padano|dairy|g|0.4|
    Pecorino romano|dairy|g|0.4|
    Provola affumicata|dairy|g||
    Scamorza|dairy|g||
    Fontina|dairy|g||
    Asiago|dairy|g||
    Emmental|dairy|g||
    Feta|dairy|g||
    Formaggio spalmabile|dairy|g|1.0|
    Latte condensato|dairy|ml|1.3|
    Panna acida|dairy|g|1.0|
    Kefir|dairy|ml|1.03|
    Zucchero|baking|g|0.85|
    Zucchero di canna|baking|g|0.83|
    Zucchero a velo|baking|g|0.56|
    Miele|baking|g|1.42|
    Sciroppo d'acero|baking|ml|1.32|
    Lievito per dolci (bustina)|baking|pack||
    Lievito per dolci|baking|g|0.9|
    Lievito di birra fresco (cubetto)|baking|piece||
    Lievito di birra fresco|baking|g||
    Lievito di birra secco|baking|g|0.75|
    Lievito madre|baking|g||
    Bicarbonato|baking|g|1.1|
    Cremor tartaro|baking|g|1.0|
    Vanillina (bustina)|baking|pack||w
    Baccello di vaniglia|baking|piece||
    Estratto di vaniglia|baking|tsp|1.0|
    Cacao amaro|baking|g|0.42|
    Cioccolato fondente|baking|g||
    Cioccolato al latte|baking|g||
    Cioccolato bianco|baking|g||
    Gocce di cioccolato|baking|g|0.72|
    Gelatina in fogli|baking|leaf||w
    Agar agar|baking|g||
    Cocco rapé|baking|g|0.35|
    Uvetta|baking|g|0.65|
    Canditi|baking|g|0.7|
    Marmellata|baking|g|1.3|
    Crema di nocciole|baking|g|1.1|
    Colorante alimentare|baking|tsp||n
    Zenzero candito|baking|g||
    Mandorle|nuts|g|0.6|
    Mandorle a lamelle|nuts|g|0.35|
    Nocciole|nuts|g|0.6|
    Noci|nuts|g|0.5|
    Pistacchi|nuts|g|0.55|
    Pinoli|nuts|g|0.6|
    Anacardi|nuts|g|0.55|
    Arachidi|nuts|g|0.6|
    Burro di arachidi|nuts|g|1.08|
    Semi di sesamo|nuts|g|0.6|
    Semi di girasole|nuts|g|0.55|
    Semi di zucca|nuts|g|0.55|
    Semi di lino|nuts|g|0.65|
    Semi di chia|nuts|g|0.65|
    Semi di papavero|nuts|g|0.6|
    Datteri|nuts|piece||w
    Fichi secchi|nuts|piece||w
    Albicocche secche|nuts|piece||w
    Prugne secche|nuts|piece||w
    Olio extravergine d'oliva|oil|tbsp|0.92|
    Olio di semi|oil|ml|0.92|
    Olio di cocco|oil|g|0.92|
    Strutto|oil|g|0.9|
    Margarina|oil|g|0.96|
    Aceto di vino|oil|tbsp|1.01|
    Aceto balsamico|oil|tbsp|1.1|
    Aceto di mele|oil|tbsp|1.01|
    Succo di limone|oil|tbsp|1.03|
    Salsa di soia|sauces|tbsp|1.15|
    Passata di pomodoro|sauces|g|1.03|
    Pomodori pelati|sauces|g|1.03|
    Polpa di pomodoro|sauces|g|1.03|
    Concentrato di pomodoro|sauces|tbsp|1.1|
    Pomodori secchi|sauces|g||
    Brodo vegetale|sauces|ml|1.0|
    Brodo di carne|sauces|ml|1.0|
    Dado da brodo|sauces|piece||
    Maionese|sauces|g|0.95|
    Senape|sauces|tsp|1.05|
    Ketchup|sauces|g|1.1|
    Pesto alla genovese|sauces|g|1.0|
    Capperi|sauces|g|0.6|
    Olive nere|sauces|g||
    Olive verdi|sauces|g||
    Acciughe sott'olio|sauces|piece||w
    Tonno in scatola|fish|g||
    Tahina|sauces|g|1.0|
    Latte di cocco|sauces|ml|1.0|
    Salsa Worcestershire|sauces|tsp|1.1|
    Tabasco|sauces|tsp||n
    Ceci (lessati)|legumes|g||
    Ceci secchi|legumes|g|0.75|
    Fagioli borlotti (lessati)|legumes|g||
    Fagioli cannellini (lessati)|legumes|g||
    Fagioli neri (lessati)|legumes|g||
    Fagioli secchi|legumes|g|0.75|
    Lenticchie|legumes|g|0.8|
    Lenticchie rosse decorticate|legumes|g|0.8|
    Piselli|legumes|g|0.6|
    Fave|legumes|g||
    Edamame|legumes|g||
    Tofu|legumes|g||
    Tempeh|legumes|g||
    Sale fino|herbs|g|1.2|n
    Sale grosso|herbs|g|1.1|n
    Pepe nero|herbs|g|0.5|n
    Pepe bianco|herbs|g|0.5|n
    Noce moscata|herbs|g|0.5|n
    Peperoncino|herbs|piece||
    Peperoncino in polvere|herbs|tsp|0.5|
    Paprika|herbs|tsp|0.45|
    Paprika affumicata|herbs|tsp|0.45|
    Curry|herbs|tsp|0.45|
    Curcuma|herbs|tsp|0.5|
    Cumino|herbs|tsp|0.45|
    Cannella|herbs|tsp|0.5|
    Chiodi di garofano|herbs|piece||w
    Zenzero fresco|herbs|g||
    Zenzero in polvere|herbs|tsp|0.45|
    Zafferano (bustina)|herbs|pack||w
    Pistilli di zafferano|herbs|pinch||
    Origano|herbs|tsp|0.2|
    Timo|herbs|sprig||w
    Rosmarino|herbs|sprig||w
    Salvia|herbs|leaf||w
    Alloro|herbs|leaf||w
    Basilico|herbs|leaf||w
    Prezzemolo|herbs|bunch||
    Prezzemolo tritato|herbs|tbsp|0.25|
    Menta|herbs|leaf||w
    Erba cipollina|herbs|tbsp|0.25|
    Aneto|herbs|tbsp|0.25|
    Coriandolo fresco|herbs|bunch||
    Maggiorana|herbs|tsp|0.2|
    Finocchietto|herbs|tsp|0.3|
    Semi di finocchio|herbs|tsp|0.45|
    Anice stellato|herbs|piece||w
    Cardamomo|herbs|piece||w
    Bacche di ginepro|herbs|piece||w
    Aglio|vegetables|clove||w
    Aglio in polvere|herbs|tsp|0.5|
    Cipolla|vegetables|piece||
    Cipolla rossa|vegetables|piece||
    Cipollotto|vegetables|piece||w
    Scalogno|vegetables|piece||
    Porro|vegetables|piece||
    Carota|vegetables|piece||
    Sedano|vegetables|piece||
    Patate|vegetables|g||
    Patata|vegetables|piece||
    Patate dolci|vegetables|g||
    Zucchine|vegetables|g||
    Zucchina|vegetables|piece||
    Melanzana|vegetables|piece||
    Peperone|vegetables|piece||
    Pomodori|vegetables|g||
    Pomodoro|vegetables|piece||
    Pomodorini|vegetables|g||
    Cetriolo|vegetables|piece||
    Lattuga|vegetables|piece||
    Rucola|vegetables|g||
    Spinaci|vegetables|g||
    Bietole|vegetables|g||
    Cavolfiore|vegetables|piece||
    Broccoli|vegetables|g||
    Cavolo cappuccio|vegetables|g||
    Cavolo nero|vegetables|g||
    Verza|vegetables|g||
    Cavolini di Bruxelles|vegetables|g||
    Carciofi|vegetables|piece||w
    Asparagi|vegetables|g||
    Finocchio|vegetables|piece||
    Funghi champignon|vegetables|g||
    Funghi porcini|vegetables|g||
    Funghi porcini secchi|vegetables|g||
    Zucca|vegetables|g||
    Radicchio|vegetables|piece||
    Fagiolini|vegetables|g||
    Mais dolce|vegetables|g||
    Barbabietola|vegetables|piece||
    Ravanelli|vegetables|piece||w
    Avocado|vegetables|piece||
    Germogli di soia|vegetables|g||
    Limone|fruit|piece||
    Scorza di limone|fruit|piece||
    Lime|fruit|piece||
    Arancia|fruit|piece||
    Succo d'arancia|fruit|ml|1.04|
    Mandarino|fruit|piece||w
    Mela|fruit|piece||
    Pera|fruit|piece||
    Banana|fruit|piece||
    Fragole|fruit|g||
    Lamponi|fruit|g||
    Mirtilli|fruit|g||
    Frutti di bosco|fruit|g||
    Ciliegie|fruit|g||
    Pesca|fruit|piece||
    Albicocche|fruit|piece||w
    Prugne|fruit|piece||w
    Uva|fruit|g||
    Kiwi|fruit|piece||
    Ananas|fruit|g||
    Mango|fruit|piece||
    Melone|fruit|g||
    Anguria|fruit|g||
    Fichi|fruit|piece||w
    Melograno|fruit|piece||
    Cocco|fruit|g||
    Petto di pollo|meat|g||
    Cosce di pollo|meat|piece||w
    Pollo intero|meat|g||
    Tacchino|meat|g||
    Macinato di manzo|meat|g||
    Macinato misto|meat|g||
    Manzo|meat|g||
    Fettine di vitello|meat|g||
    Arrosto di vitello|meat|g||
    Maiale|meat|g||
    Lonza di maiale|meat|g||
    Costine di maiale|meat|g||
    Salsiccia|meat|g||
    Agnello|meat|g||
    Coniglio|meat|g||
    Pancetta|meat|g||
    Guanciale|meat|g||
    Prosciutto crudo|meat|g||
    Prosciutto cotto|meat|g||
    Speck|meat|g||
    Mortadella|meat|g||
    Salame|meat|g||
    Bresaola|meat|g||
    Würstel|meat|piece||w
    Salmone|fish|g||
    Salmone affumicato|fish|g||
    Merluzzo|fish|g||
    Baccalà|fish|g||
    Orata|fish|piece||w
    Branzino|fish|piece||w
    Pesce spada|fish|g||
    Tonno fresco|fish|g||
    Gamberi|fish|g||
    Gamberetti|fish|g||
    Calamari|fish|g||
    Seppie|fish|g||
    Polpo|fish|g||
    Cozze|fish|g||
    Vongole|fish|g||
    Alici fresche|fish|g||
    Acqua|drinks|ml|1.0|
    Acqua frizzante|drinks|ml|1.0|
    Vino bianco|drinks|ml|0.99|
    Vino rosso|drinks|ml|0.99|
    Birra|drinks|ml|1.01|
    Marsala|drinks|ml|1.03|
    Rum|drinks|ml|0.94|
    Liquore|drinks|ml|1.0|
    Caffè|drinks|ml|1.0|
    Caffè solubile|drinks|tsp|0.3|
    Tè|drinks|piece||w
    Ghiaccio|drinks|g||
    """
}
