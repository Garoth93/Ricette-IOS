import XCTest
@testable import RicettarioCore

final class StepTextTests: XCTestCase {
    let ings = Synthetic.recipe().ingredients

    func testParseAndToken() {
        let t = "A \(StepText.token(Synthetic.flourID)) b \(StepText.token(Synthetic.eggsID, fraction: 0.5))"
        XCTAssertEqual(StepText.parse(t), [
            .text("A "), .ingredient(id: Synthetic.flourID, fraction: 1), .text(" b "), .ingredient(id: Synthetic.eggsID, fraction: 0.5)
        ])
        XCTAssertEqual(StepText.references(t), [Synthetic.flourID, Synthetic.eggsID])
    }

    func testMalformedTokensStayText() {
        XCTAssertEqual(StepText.parse("{{ing:nope}} e {{ing:"), [.text("{{ing:nope}} e {{ing:")])
    }

    func testEditableRoundTrip() {
        let stored = "Mescola \(StepText.token(Synthetic.flourID, fraction: 0.5)) e \(StepText.token(Synthetic.eggsID))."
        let editable = StepText.editable(stored, ingredients: ings)
        XCTAssertEqual(editable, "Mescola {1/2 Farina 00} e {Uova}.")
        XCTAssertEqual(StepText.stored(editable, ingredients: ings), stored)
    }

    func testEditorTypedTokens() {
        let s = StepText.stored("Metti {farina 00}, {25% uova} e {zucchero} {", ingredients: ings)
        XCTAssertEqual(StepText.parse(s), [
            .text("Metti "), .ingredient(id: Synthetic.flourID, fraction: 1), .text(", "),
            .ingredient(id: Synthetic.eggsID, fraction: 0.25), .text(" e {zucchero} {")
        ])
    }

    func testDuplicateNames() {
        let a = RecipeIngredient(name: "Zucchero", amount: 100, unit: .g)
        let b = RecipeIngredient(name: "Zucchero", amount: 50, unit: .g)
        let names = StepText.editorNames([a, b])
        XCTAssertEqual(names[a.id], "Zucchero")
        XCTAssertEqual(names[b.id], "Zucchero (2)")
        let stored = StepText.stored("{Zucchero (2)}", ingredients: [a, b])
        XCTAssertEqual(StepText.references(stored), [b.id])
    }

    func testSanitizeDropsRemovedIngredients() {
        var r = Synthetic.recipe()
        let previous = r
        r.ingredients.removeAll { $0.id == Synthetic.eggsID }
        r.ingredients.append(RecipeIngredient(name: "   ", amount: 3, unit: .g))
        r.steps.append(RecipeStep(text: "  "))
        r.tags = ["a", "A", " b "]
        let clean = RecipeOps.sanitized(r, previous: previous)
        XCTAssertEqual(clean.ingredients.count, 4)
        XCTAssertEqual(clean.steps.count, 2)
        XCTAssertTrue(clean.steps[0].text.hasSuffix("con uova."), clean.steps[0].text)
        XCTAssertEqual(clean.tags, ["a", "b"])
    }

    func testFractionParse() {
        XCTAssertEqual(Fraction.parse("1/2"), 0.5)
        XCTAssertEqual(Fraction.parse("30%"), 0.3)
        XCTAssertEqual(Fraction.parse("0,25"), 0.25)
        XCTAssertNil(Fraction.parse("farina"))
        XCTAssertEqual(StepText.fractionLabel(0.5), "1/2")
        XCTAssertEqual(StepText.fractionLabel(0.3), "30%")
    }

    func testTimerDetection() {
        XCTAssertEqual(TimerDetector.detect("Cuoci in forno a 180 gradi per 30 minuti"), 1800)
        XCTAssertEqual(TimerDetector.detect("Lascia riposare 1 ora e 30 minuti"), 5400)
        XCTAssertEqual(TimerDetector.detect("Cuoci 10-12 minuti"), 720)
        XCTAssertEqual(TimerDetector.detect("Frulla per 45 secondi"), 45)
        XCTAssertEqual(TimerDetector.detect("Lievitare per un'ora"), 3600)
        XCTAssertEqual(TimerDetector.detect("riposo di mezz'ora"), 1800)
        XCTAssertNil(TimerDetector.detect("Aggiungi 2 uova"))
    }
}
