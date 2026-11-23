import Foundation

@main
struct RecipeNamingPromptTests {
    static func main() throws {
        try webpagePromptPrefersDishHeadingOverArticleTitle()
        try webpagePromptHandlesMissingHeadingWithoutGuessing()
        try magazinePromptPrefersPrintedDishHeading()
        print("Recipe naming prompt checks passed")
    }

    private static func webpagePromptPrefersDishHeadingOverArticleTitle() throws {
        let prompt = RecipeNamingPrompts.webpage
        try require(prompt.contains("page title and URL are context only"), "web metadata must not be treated as the preferred recipe name")
        try require(prompt.contains("‘The Best Weeknight Dinner Ideas | Example Site’") && prompt.contains("the recipe heading is ‘Lemon Garlic Chicken,’ use ‘Lemon Garlic Chicken.’"), "the article-versus-dish example must stay explicit")
        try require(prompt.contains("recipe-specific heading attached to those ingredients and instructions"), "the dish heading must be tied to the extracted recipe")
    }

    private static func webpagePromptHandlesMissingHeadingWithoutGuessing() throws {
        let prompt = RecipeNamingPrompts.webpage
        try require(prompt.contains("If no clear recipe heading exists"), "web extraction must handle recipes without a heading")
        try require(prompt.contains("grounded in the recipe content without inventing specifics"), "a fallback name must be grounded and avoid unsupported details")
    }

    private static func magazinePromptPrefersPrintedDishHeading() throws {
        let prompt = RecipeNamingPrompts.magazinePhoto
        try require(prompt.contains("Prefer the printed recipe heading when it names the dish"), "magazine extraction must prefer the printed dish heading")
        try require(prompt.contains("Ignore magazine or publication branding"), "publication branding must not become the recipe name")
        try require(prompt.contains("grounded in the visible recipe without guessing"), "photo fallback names must stay grounded in visible content")
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
    }
}

private struct Failure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
