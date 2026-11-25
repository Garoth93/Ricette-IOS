import XCTest
@testable import RicettarioCore

final class ScalingTests: XCTestCase {
    let prefs = UnitPreferences()

    func testServingsFactor() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.setServings(6)
        XCTAssertEqual(s.factor, 1.5, accuracy: 1e-9)
        XCTAssertEqual(s.scaled(Synthetic.flourID)?.amount ?? 0, 450, accuracy: 1e-9)
        XCTAssertEqual(s.scaled(Synthetic.eggsID)?.amount, 6)
        XCTAssertEqual(s.servings, 6, accuracy: 1e-9)
    }

    func testAnchorEggs() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.setAnchor(Synthetic.eggsID, newAmount: 3)
        XCTAssertEqual(s.factor, 0.75, accuracy: 1e-9)
        XCTAssertEqual(s.anchorID, Synthetic.eggsID)
        XCTAssertEqual(s.scaled(Synthetic.flourID)?.amount ?? 0, 225, accuracy: 1e-9)
        XCTAssertEqual(s.servings, 3, accuracy: 1e-9)
    }

    func testOriginalNeverChanges() {
        let r = Synthetic.recipe()
        var s = ScaleSession(recipe: r)
        s.setServings(10)
        s.setAnchor(Synthetic.flourID, newAmount: 100)
        XCTAssertEqual(s.original, r)
    }

    func testSmartRoundingOfPieces() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.setServings(3) // 4 eggs × 0.75 = 3 exactly
        XCTAssertFalse(s.scaled(Synthetic.eggsID)!.isRounded)
        s.setServings(2.7) // factor 0.675 → 2.7 eggs → 3, flagged
        let eggs = s.scaled(Synthetic.eggsID)!
        XCTAssertEqual(eggs.amount, 3)
        XCTAssertEqual(eggs.exact ?? 0, 2.7, accuracy: 1e-9)
        XCTAssertTrue(eggs.isRounded)
        // Lemon is divisible: halves.
        XCTAssertEqual(s.scaled(Synthetic.lemonID)?.amount, 0.5)
        XCTAssertEqual(PieceRounding.round(0.2, wholeOnly: true), 1)
        XCTAssertEqual(PieceRounding.round(1.3, wholeOnly: false), 1.5)
        XCTAssertTrue(s.roundingNotes.contains { $0.id == Synthetic.eggsID })
    }

    func testStepperOnPieces() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.step(Synthetic.eggsID, by: -1)
        XCTAssertEqual(s.factor, 0.75, accuracy: 1e-9)
        s.step(Synthetic.eggsID, by: -1)
        XCTAssertEqual(s.scaled(Synthetic.eggsID)?.amount, 2)
        XCTAssertEqual(s.factor, 0.5, accuracy: 1e-9)
        s.step(Synthetic.eggsID, by: -1)
        s.step(Synthetic.eggsID, by: -1) // can't go to zero
        XCTAssertEqual(s.scaled(Synthetic.eggsID)?.amount, 1)
    }

    func testToTasteAndFixedDoNotScale() {
        var r = Synthetic.recipe()
        r.ingredients.append(RecipeIngredient(name: "Pepe", amount: nil, unit: .g))
        var s = ScaleSession(recipe: r)
        s.setServings(8)
        XCTAssertEqual(s.scaled(Synthetic.saltID)?.amount, 2)
        XCTAssertTrue(s.scaled(Synthetic.saltID)!.isFixed)
        let pepper = s.ingredients.last!
        XCTAssertNil(pepper.amount)
        // Anchoring a fixed ingredient does nothing.
        let f = s.factor
        s.setAnchor(Synthetic.saltID, newAmount: 10)
        XCTAssertEqual(s.factor, f)
    }

    func testStepTokensResolveWithScaledAmounts() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.setAnchor(Synthetic.eggsID, newAmount: 3)
        let text = StepRenderer.plain(s.original.steps[0].text, session: s, prefs: prefs)
        XCTAssertEqual(text, "Mescola 113 g di farina 00 con 3 uova.")
        let second = StepRenderer.plain(s.original.steps[1].text, session: s, prefs: prefs)
        XCTAssertTrue(second.contains("2 g di sale fino"), second)
    }

    func testMissingReference() {
        var r = Synthetic.recipe()
        r.steps = [RecipeStep(text: "Usa \(StepText.token(UUID()))")]
        let seg = StepRenderer.render(r.steps[0].text, session: ScaleSession(recipe: r), prefs: prefs)
        XCTAssertEqual(seg.last?.kind, .missing)
    }

    func testVariant() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.setServings(2.7)
        let v = s.makeVariant(now: Date(timeIntervalSince1970: 100))
        XCTAssertNotEqual(v.id, s.original.id)
        XCTAssertEqual(v.variantOf, s.original.id)
        XCTAssertEqual(v.servings, 3)
        XCTAssertEqual(v.ingredient(Synthetic.eggsID)?.amount, 3)
        XCTAssertEqual(v.ingredient(Synthetic.saltID)?.amount, 2)
        XCTAssertEqual(v.steps.map(\.text), s.original.steps.map(\.text))
        XCTAssertTrue(v.title.contains("Torta TEST"))
    }

    func testFactorClamp() {
        var s = ScaleSession(recipe: Synthetic.recipe())
        s.setAnchor(Synthetic.flourID, newAmount: 1_000_000)
        XCTAssertEqual(s.factor, ScaleSession.maxFactor)
        s.reset()
        XCTAssertFalse(s.isScaled)
    }

    func testPhrase() {
        let oil = RecipeIngredient(name: "Olio extravergine d'oliva", amount: 30, unit: .tbsp)
        XCTAssertEqual(StepRenderer.phrase(oil, amount: 30, prefs: prefs), "2 cucchiai d'olio extravergine d'oliva")
        let salt = RecipeIngredient(name: "Sale", amount: nil, unit: .g)
        XCTAssertEqual(StepRenderer.phrase(salt, amount: nil, prefs: prefs), "sale q.b.")
        let cheese = RecipeIngredient(name: "Parmigiano Reggiano", amount: 50, unit: .g)
        XCTAssertEqual(StepRenderer.phrase(cheese, amount: 50, prefs: prefs), "50 g di Parmigiano Reggiano")
    }
}
