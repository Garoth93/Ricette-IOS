import Foundation
@testable import RicettarioCore

/// Synthetic data only (never real user recipes).
enum Synthetic {
    static let flourID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F1")!
    static let eggsID = UUID(uuidString: "00000000-0000-0000-0000-0000000000E9")!
    static let milkID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
    static let saltID = UUID(uuidString: "00000000-0000-0000-0000-0000000000B5")!
    static let lemonID = UUID(uuidString: "00000000-0000-0000-0000-0000000000C7")!

    static func recipe(servings: Int = 4) -> Recipe {
        Recipe(title: "Torta TEST", servings: servings, ingredients: [
            RecipeIngredient(id: flourID, catalogID: "seed.farina-00", name: "Farina 00", amount: 300, unit: .g, density: 0.53),
            RecipeIngredient(id: eggsID, catalogID: "seed.uova", name: "Uova", amount: 4, unit: .piece, wholeOnly: true),
            RecipeIngredient(id: milkID, name: "Latte TEST", amount: 240, unit: .cup, density: 1.03),
            RecipeIngredient(id: saltID, name: "Sale fino", amount: 2, unit: .g, scales: false),
            RecipeIngredient(id: lemonID, name: "Limone", amount: 1, unit: .piece)
        ], steps: [
            RecipeStep(text: "Mescola \(StepText.token(flourID, fraction: 0.5)) con \(StepText.token(eggsID))."),
            RecipeStep(text: "Aggiungi il resto: \(StepText.token(flourID, fraction: 0.5)) e \(StepText.token(saltID)).", timerSeconds: 600)
        ], tags: ["Dolci", "TEST"], createdAt: Date(timeIntervalSince1970: 1_000_000), updatedAt: Date(timeIntervalSince1970: 1_000_000))
    }
}
