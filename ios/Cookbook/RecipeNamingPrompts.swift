import Foundation

enum RecipeNamingPrompts {
    static let webpage = "Name the recipe with a concise, natural name for the dish represented by its ingredients and instructions. Prefer the recipe-specific heading attached to those ingredients and instructions. The captured page title and URL are context only, not preferred recipe names; ignore site names, publication branding, and article framing. For example, if the page title is ‘The Best Weeknight Dinner Ideas | Example Site’ and the recipe heading is ‘Lemon Garlic Chicken,’ use ‘Lemon Garlic Chicken.’ If no clear recipe heading exists, infer a concise dish name grounded in the recipe content without inventing specifics."

    static let magazinePhoto = "Name the recipe with a concise, natural name for the dish represented by its ingredients and instructions. Prefer the printed recipe heading when it names the dish. Ignore magazine or publication branding and nearby feature or article headlines. If no clear recipe heading exists, infer a concise dish name grounded in the visible recipe without guessing or inventing specifics."
}
