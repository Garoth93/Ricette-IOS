import XCTest
@testable import RicettarioCore

final class UnitsTests: XCTestCase {
    let entered = UnitPreferences()

    func testNumberFormatting() {
        XCTAssertEqual(Fmt.number(1.5), "1,5")
        XCTAssertEqual(Fmt.number(2.0), "2")
        XCTAssertEqual(Fmt.number(0.333, digits: 2), "0,33")
        XCTAssertEqual(Fmt.fraction(1.5), "1 ½")
        XCTAssertEqual(Fmt.fraction(0.75), "¾")
        XCTAssertEqual(Fmt.fraction(1.0 / 3), "⅓")
        XCTAssertNil(Fmt.fraction(0.41))
        XCTAssertEqual(Fmt.duration(5400), "1 h 30 min")
        XCTAssertEqual(Fmt.clock(65), "01:05")
    }

    func testParseAmount() {
        XCTAssertEqual(Fmt.parseAmount("250"), 250)
        XCTAssertEqual(Fmt.parseAmount("1,5"), 1.5)
        XCTAssertEqual(Fmt.parseAmount("1/2"), 0.5)
        XCTAssertEqual(Fmt.parseAmount("1 1/2"), 1.5)
        XCTAssertEqual(Fmt.parseAmount("½"), 0.5)
        XCTAssertEqual(Fmt.parseAmount("2½"), 2.5)
        XCTAssertNil(Fmt.parseAmount("abc"))
        XCTAssertNil(Fmt.parseAmount(""))
    }

    func testAsEnteredPromotesGramsToKg() {
        XCTAssertEqual(UnitConverter.display(base: 250, entryUnit: .g, density: nil, prefs: entered).text, "250 g")
        XCTAssertEqual(UnitConverter.display(base: 1250, entryUnit: .g, density: nil, prefs: entered).text, "1,25 kg")
        XCTAssertEqual(UnitConverter.display(base: 500, entryUnit: .kg, density: nil, prefs: entered).text, "500 g")
        XCTAssertEqual(UnitConverter.display(base: 360, entryUnit: .cup, density: nil, prefs: entered).text, "1 ½ tazze")
        XCTAssertEqual(UnitConverter.display(base: 3, entryUnit: .piece, density: nil, prefs: entered).text, "3")
        XCTAssertEqual(UnitConverter.display(base: 2, entryUnit: .clove, density: nil, prefs: entered).text, "2 spicchi")
    }

    func testMetricAndImperial() {
        var metric = UnitPreferences(system: .metric, keepSpoons: false)
        XCTAssertEqual(UnitConverter.display(base: 240, entryUnit: .cup, density: nil, prefs: metric).text, "240 ml")
        metric.keepSpoons = true
        XCTAssertEqual(UnitConverter.display(base: 15, entryUnit: .tbsp, density: nil, prefs: metric).text, "1 cucchiaio")
        let imperial = UnitPreferences(system: .imperial)
        XCTAssertEqual(UnitConverter.display(base: 453.59237, entryUnit: .g, density: nil, prefs: imperial).text, "1 lb")
        XCTAssertEqual(UnitConverter.display(base: 56.7, entryUnit: .g, density: nil, prefs: imperial).text, "2 oz")
        XCTAssertEqual(UnitConverter.display(base: 120, entryUnit: .ml, density: nil, prefs: imperial).text, "½ tazza")
        XCTAssertEqual(UnitConverter.display(base: 30, entryUnit: .ml, density: nil, prefs: imperial).text, "2 cucchiai")
    }

    func testDensityWeighsVolumes() {
        let p = UnitPreferences(system: .metric, weighVolumes: true)
        // 1 cup of flour (240 ml × 0.53) ≈ 127 g.
        XCTAssertEqual(UnitConverter.display(base: 240, entryUnit: .cup, density: 0.53, prefs: p).text, "127 g")
        // Without density the volume stays a volume.
        XCTAssertEqual(UnitConverter.display(base: 240, entryUnit: .cup, density: nil, prefs: p).text, "1 tazza")
        XCTAssertEqual(UnitConverter.convert(base: 100, kind: .mass, to: .ml, density: 0.5, cupML: 240), 200)
    }

    func testCupSize() {
        XCTAssertEqual(UnitConverter.toBase(1, unit: .cup, cupML: 250), 250)
        let p = UnitPreferences(cupML: 250)
        XCTAssertEqual(UnitConverter.display(base: 250, entryUnit: .cup, density: nil, prefs: p).text, "1 tazza")
    }
}
