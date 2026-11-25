import XCTest
@testable import RicettarioCore

final class DataTests: XCTestCase {
    func testSeedPool() {
        XCTAssertGreaterThan(Catalog.seed.count, 300)
        XCTAssertEqual(Set(Catalog.seed.map(\.id)).count, Catalog.seed.count)
        let eggs = Catalog.seed.first { $0.id == "seed.uova" }
        XCTAssertEqual(eggs?.unit, .piece)
        XCTAssertEqual(eggs?.wholeOnly, true)
        XCTAssertEqual(Catalog.seed.first { $0.id == "seed.sale-fino" }?.scales, false)
        XCTAssertEqual(Catalog.seed.first { $0.id == "seed.farina-00" }?.density, 0.53)
        XCTAssertEqual(Catalog.slug("Fiocchi d'avena"), "fiocchi-d-avena")
        XCTAssertEqual(Catalog.slug("Würstel"), "wurstel")
    }

    func testPoolOverridesHiddenCustom() {
        var d = RicettarioData()
        var flour = Catalog.seed.first { $0.id == "seed.farina-00" }!
        flour.density = 0.6
        d.seedOverrides[flour.id] = flour
        d.hiddenSeeds = ["seed.uova"]
        d.customIngredients = [CatalogIngredient(id: "user.x", name: "Spezia TEST", category: .herbs)]
        let pool = Catalog.pool(d)
        XCTAssertEqual(pool.first { $0.id == flour.id }?.density, 0.6)
        XCTAssertNil(pool.first { $0.id == "seed.uova" })
        XCTAssertNotNil(pool.first { $0.id == "user.x" })
        XCTAssertEqual(Catalog.search("far", in: pool).first?.name.hasPrefix("Far"), true)
        XCTAssertEqual(Catalog.search("parmig", in: pool).first?.id, "seed.parmigiano-reggiano")
        XCTAssertNotNil(Catalog.existing(named: "spezia test", in: pool))
    }

    func testRecipeQuery() {
        var a = Synthetic.recipe()
        a.favorite = true
        var b = Recipe(title: "Pasta TEST", tags: ["Primi"], updatedAt: Date(timeIntervalSince1970: 10))
        b.ingredients = [RecipeIngredient(name: "Pomodori", amount: 100, unit: .g)]
        XCTAssertEqual(RecipeQuery(text: "pomodori").apply([a, b]).map(\.title), ["Pasta TEST"])
        XCTAssertEqual(RecipeQuery(text: "TORTA farina").apply([a, b]).count, 1)
        XCTAssertEqual(RecipeQuery(tags: ["primi"]).apply([a, b]).count, 1)
        XCTAssertEqual(RecipeQuery(favoritesOnly: true).apply([a, b]).map(\.title), ["Torta TEST"])
        XCTAssertEqual(RecipeQuery(sort: .alphabetical).apply([a, b]).map(\.title), ["Pasta TEST", "Torta TEST"])
        XCTAssertEqual(Tags.parse("Primi, veloci ,  primi, #estate"), ["Primi", "veloci", "estate"])
    }

    func testShoppingMerge() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.setServings(8)
        var list = ShoppingList.add(s.ingredients, recipeTitle: "Torta TEST", to: [], categories: { _ in .other })
        XCTAssertEqual(list.count, 5)
        XCTAssertEqual(list.first { $0.name == "Uova" }?.amount, 8)
        let other = Recipe(title: "Frittata TEST", ingredients: [RecipeIngredient(catalogID: "seed.uova", name: "uova", amount: 2, unit: .piece)])
        list = ShoppingList.add(ScaleSession(recipe: other).ingredients, recipeTitle: other.title, to: list, categories: { _ in .dairy })
        let eggs = list.first { $0.catalogID == "seed.uova" }!
        XCTAssertEqual(eggs.amount, 10)
        XCTAssertEqual(eggs.sources, ["Torta TEST", "Frittata TEST"])
        // Checked items are not merged into.
        list[list.firstIndex { $0.id == eggs.id }!].checked = true
        list = ShoppingList.add(ScaleSession(recipe: other).ingredients, recipeTitle: other.title, to: list, categories: { _ in .dairy })
        XCTAssertEqual(list.filter { $0.catalogID == "seed.uova" }.count, 2)
        let text = ShoppingList.text(list, prefs: UnitPreferences())
        XCTAssertTrue(text.contains("Farina 00 — 600 g"), text)
        XCTAssertFalse(ShoppingList.grouped(list).isEmpty)
    }

    func testShoppingMergeAcrossMassAndVolume() {
        let a = RecipeIngredient(catalogID: "seed.zucchero", name: "Zucchero", amount: 100, unit: .g, density: 0.85)
        let b = RecipeIngredient(catalogID: "seed.zucchero", name: "Zucchero", amount: 100, unit: .ml, density: 0.85)
        var list = ShoppingList.add(ScaleSession(recipe: Recipe(ingredients: [a])).ingredients, recipeTitle: "A", to: [], categories: { _ in .baking })
        list = ShoppingList.add(ScaleSession(recipe: Recipe(ingredients: [b])).ingredients, recipeTitle: "B", to: list, categories: { _ in .baking })
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].amount ?? 0, 185, accuracy: 1e-9)
    }

    func testTolerantDecoding() throws {
        let json = #"{"recipes":[{"title":"Vecchia TEST","ingredients":[{"name":"Acqua","unit":"ml","amount":100}]}]}"#
        let d = try JSONFileStore<RicettarioData>.decoder.decode(RicettarioData.self, from: Data(json.utf8))
        XCTAssertEqual(d.recipes.first?.servings, 4)
        XCTAssertEqual(d.recipes.first?.ingredients.first?.scales, true)
        XCTAssertEqual(d.settings.units.system, .asEntered)
    }

    func testBackupRoundTripAndMerge() throws {
        var d = RicettarioData(recipes: [Synthetic.recipe()])
        d.revision = 7
        let file = BackupFile(data: d, photos: ["a.jpg": Data([1, 2, 3])])
        let back = try BackupFile.decode(file.encoded())
        XCTAssertEqual(back.data.recipes, d.recipes)
        XCTAssertEqual(back.photoData["a.jpg"], Data([1, 2, 3]))
        XCTAssertThrowsError(try BackupFile.decode(Data("{}".utf8)))

        var newer = d.recipes[0]
        newer.title = "Torta TEST 2"
        newer.updatedAt = Date().addingTimeInterval(60)
        let incoming = RicettarioData(recipes: [newer, Recipe(title: "Nuova TEST")])
        let m = DataMerge.merge(d, with: incoming)
        XCTAssertEqual(m.added, 1)
        XCTAssertEqual(m.updated, 1)
        XCTAssertEqual(m.data.recipes.count, 2)
        XCTAssertEqual(DataMerge.replace(d, with: incoming).revision, 8)
    }

    func testShareFileImport() throws {
        var d = RicettarioData()
        let custom = CatalogIngredient(id: "user.1", name: "Spezia TEST", category: .herbs)
        d.customIngredients = [custom]
        var r = Synthetic.recipe()
        r.ingredients.append(RecipeIngredient(catalogID: custom.id, name: custom.name, amount: 1, unit: .g))
        r.photo = "cover.jpg"
        d.recipes = [r]
        let share = RecipeShareFile(recipe: r, data: d, photos: [:])
        XCTAssertEqual(share.ingredients, [custom])
        XCTAssertEqual(share.fileName, "Torta TEST.ricetta")
        let decoded = try RecipeShareFile.decode(share.encoded())
        // Importing into the same data: new id, custom ingredient reused.
        let result = DataMerge.importShared(decoded, into: d, photoNames: ["cover.jpg": "new.jpg"])
        XCTAssertEqual(result.data.recipes.count, 2)
        XCTAssertNotEqual(result.recipe.id, r.id)
        XCTAssertEqual(result.recipe.photo, "new.jpg")
        XCTAssertEqual(result.data.customIngredients.count, 1)
        XCTAssertThrowsError(try BackupFile.decode(share.encoded())) { XCTAssertEqual($0 as? BackupError, .wrongApp) }
    }

    func testCloudPlan() {
        let names = ["Ricettario-backup-latest.json", ".Ricettario-backup-2026-01-02.json.icloud", "Ricettario-backup-2026-01-01.json", "x.txt"]
        let e = CloudBackupPlan.entries(fromFileNames: names)
        XCTAssertEqual(e.map(\.name), ["Ricettario-backup-latest.json", "Ricettario-backup-2026-01-02.json", "Ricettario-backup-2026-01-01.json"])
        XCTAssertEqual(CloudBackupPlan.namesToPrune(names, keep: 1), ["Ricettario-backup-2026-01-01.json"])
        XCTAssertEqual(CloudBackupPlan.missing(["a.jpg", "b.jpg"], existing: [".a.jpg.icloud"]), ["b.jpg"])
        let d = RicettarioData(recipes: [Synthetic.recipe()])
        var d2 = d
        d2.revision = 99
        XCTAssertEqual(CloudBackupPlan.fingerprint(BackupFile(data: d, now: Date(timeIntervalSince1970: 1))),
                       CloudBackupPlan.fingerprint(BackupFile(data: d2, now: Date(timeIntervalSince1970: 2))))
    }

    func testRecipeText() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.setServings(2)
        let t = RecipeText.plain(s, prefs: UnitPreferences())
        XCTAssertTrue(t.contains("Per 2 persone"), t)
        XCTAssertTrue(t.contains("Uova — 2"), t)
        XCTAssertTrue(t.contains("⏱ 10 min"), t)
    }

    func testDuplicate() {
        let r = Synthetic.recipe()
        let d = r.duplicated(now: Date(timeIntervalSince1970: 5))
        XCTAssertNotEqual(d.id, r.id)
        XCTAssertEqual(d.title, "Torta TEST (copia)")
        XCTAssertEqual(d.ingredients, r.ingredients)
    }
}
